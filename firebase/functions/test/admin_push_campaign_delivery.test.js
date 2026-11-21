process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-proxiplay-admin-push-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const functions = require("../index.js");
const db = admin.firestore();
const deliver = functions._testHelpers.sendAdminCampaign;

async function campaign(id, fields = {}) {
  const ref = db.collection("ff_push_notifications").doc(id);
  await ref.set({admin_campaign_version: 2, audience_mode: "single", user_refs: "users/push_test_0",
    status: "started", notification_title: "Test", notification_text: "Test", ...fields});
  return ref;
}

async function recipient(id) {
  await db.collection("users").doc(id).set({user_role: "joueur"});
  await db.collection("users").doc(id).collection("fcm_tokens").doc("device").set({fcm_token: `token_${id}`});
}

test("duplicate invocations reserve one campaign only", async () => {
  await recipient("push_test_0");
  const ref = await campaign("test_duplicate");
  let sends = 0;
  const fake = async ({tokens}) => { sends++; return {successCount: tokens.length, failureCount: 0}; };
  await Promise.all([deliver(ref, {sendMulticast: fake}), deliver(ref, {sendMulticast: fake})]);
  const data = (await ref.get()).data();
  assert.equal(sends, 1);
  assert.equal(data.status, "succeeded");
  assert.equal(data.targeted_players, 1);
  assert.equal(data.players_with_token, 1);
  assert.equal(data.num_sent, 1);
});

test("FCM failures produce a partial status and accurate counts", async () => {
  await recipient("push_test_1");
  const ref = await campaign("test_partial", {audience_mode: "all", user_refs: ""});
  const fake = async ({tokens}) => ({successCount: tokens.length - 1, failureCount: 1});
  await deliver(ref, {sendMulticast: fake});
  const data = (await ref.get()).data();
  assert.equal(data.status, "partial_failed");
  assert.equal(data.num_sent + data.num_failed, data.attempted_tokens);
});

test("a transport error fails once and is never automatically retried", async () => {
  const ref = await campaign("test_transport_error");
  let calls = 0;
  const fake = async () => { calls++; throw new Error("simulated FCM outage"); };
  await assert.rejects(() => deliver(ref, {sendMulticast: fake}), /simulated FCM outage/);
  await deliver(ref, {sendMulticast: fake});
  assert.equal(calls, 1);
  assert.equal((await ref.get()).data().status, "failed");
});

test("scheduled campaigns wait until due and cannot be claimed twice", async () => {
  const future = admin.firestore.Timestamp.fromMillis(Date.now() + 3600000);
  const ref = await campaign("test_scheduled", {status: "scheduled", scheduled_time: future});
  let calls = 0;
  await deliver(ref, {sendMulticast: async () => { calls++; return {successCount: 1, failureCount: 0}; }});
  assert.equal(calls, 0);
  assert.equal((await ref.get()).data().status, "scheduled");
});

test("1,421 recipients are split into FCM batches of at most 500", async () => {
  const writer = db.bulkWriter();
  for (let i = 0; i < 1421; i++) {
    const id = `bulk_push_${i}`;
    writer.set(db.collection("users").doc(id), {user_role: "joueur", created_time: admin.firestore.Timestamp.now()});
    writer.set(db.collection("users").doc(id).collection("fcm_tokens").doc("device"),
      {fcm_token: `token_${id}`});
  }
  await writer.close();
  const ref = await campaign("test_bulk", {audience_mode: "segment", segment_id: "nouveaux_j7", user_refs: ""});
  const sizes = [];
  await deliver(ref, {sendMulticast: async ({tokens}) => {
    sizes.push(tokens.length);
    return {successCount: tokens.length, failureCount: 0};
  }});
  const data = (await ref.get()).data();
  assert.equal(data.status, "succeeded");
  assert.equal(data.targeted_players, 1421);
  assert.equal(data.players_with_token, 1421);
  assert.equal(data.num_sent, 1421);
  assert.deepEqual(sizes, [500, 500, 421]);
});
