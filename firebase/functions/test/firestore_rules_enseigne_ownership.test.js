// Regression: a shop (enseigne) onboarded via the admin console
// (proxiplay-admin/lib/admin/merchantServer.ts) writes `owner` as a STRING
// ('/users/{uid}') and `owner_id` as a real DocumentReference, while a shop
// created from the mobile app writes `owner` as a real DocumentReference
// only (lib/pages/commercant/add_enseigne_commercant_page_widget.dart).
// The self-update/delete rule used to check isOwnerRef(resource.data.owner)
// alone -- a strict path-type comparison that never matches a string, so a
// merchant onboarded via admin could never edit or delete their own shop
// from the app. Fixed by using ownsShopData(), the same tolerant
// owner/owner_id contract already used elsewhere in this file (ownsGame()).
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-proxiplay-enseigne-ownership",
    firestore: {
      rules: fs.readFileSync(
        path.join(__dirname, "..", "..", "firestore.rules"),
        "utf8",
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

test.after(async () => {
  await testEnv.cleanup();
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
});

async function seed(shopId, shopData, uid = "merchant_uid") {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db
      .collection("users")
      .doc(uid)
      .set({ uid, user_role: "commercant", account_status: "approved" });
    await db.collection("enseignes").doc(shopId).set(shopData);
  });
}

test("admin-onboarded shop (owner=string, owner_id=ref): owner can update it", async () => {
  await seed("admin_shop", {
    name: "Boutique",
    owner: "/users/merchant_uid",
    owner_id: testEnv.unauthenticatedContext().firestore().doc("users/merchant_uid"),
  });
  const merchant = testEnv.authenticatedContext("merchant_uid", {}).firestore();
  await assertSucceeds(
    merchant.collection("enseignes").doc("admin_shop").update({ phone_number: "0600000000" }),
  );
});

test("admin-onboarded shop (owner=string, owner_id=ref): owner can delete it", async () => {
  await seed("admin_shop_delete", {
    name: "Boutique",
    owner: "/users/merchant_uid",
    owner_id: testEnv.unauthenticatedContext().firestore().doc("users/merchant_uid"),
  });
  const merchant = testEnv.authenticatedContext("merchant_uid", {}).firestore();
  await assertSucceeds(merchant.collection("enseignes").doc("admin_shop_delete").delete());
});

test("no regression: mobile-created shop (owner=ref only, no owner_id) still editable by its owner", async () => {
  await seed("mobile_shop", {
    name: "Boutique",
    owner: testEnv.unauthenticatedContext().firestore().doc("users/merchant_uid"),
  });
  const merchant = testEnv.authenticatedContext("merchant_uid", {}).firestore();
  await assertSucceeds(
    merchant.collection("enseignes").doc("mobile_shop").update({ city: "Dunkerque" }),
  );
});

test("no security loosening: a different signed-in user still cannot edit someone else's shop", async () => {
  await seed("admin_shop_other", {
    name: "Boutique",
    owner: "/users/merchant_uid",
    owner_id: testEnv.unauthenticatedContext().firestore().doc("users/merchant_uid"),
  });
  const other = testEnv.authenticatedContext("other_uid", {}).firestore();
  await assertFails(
    other.collection("enseignes").doc("admin_shop_other").update({ phone_number: "0600000000" }),
  );
});

test("no security loosening: a managed_by_admin shop still cannot be self-edited by its owner", async () => {
  await seed("managed_shop", {
    name: "Boutique",
    owner: "/users/merchant_uid",
    owner_id: testEnv.unauthenticatedContext().firestore().doc("users/merchant_uid"),
    managed_by_admin: true,
  });
  const merchant = testEnv.authenticatedContext("merchant_uid", {}).firestore();
  await assertFails(
    merchant.collection("enseignes").doc("managed_shop").update({ phone_number: "0600000000" }),
  );
});

test("no regression: create still requires a real DocumentReference owner (unchanged)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("users")
      .doc("merchant_uid")
      .set({ uid: "merchant_uid", user_role: "commercant", account_status: "approved" });
  });
  const merchant = testEnv.authenticatedContext("merchant_uid", {}).firestore();
  await assertFails(
    merchant.collection("enseignes").doc("bad_create").set({
      name: "Boutique",
      owner: "/users/merchant_uid", // string at create time: still refused, unchanged
    }),
  );
  await assertSucceeds(
    merchant.collection("enseignes").doc("good_create").set({
      name: "Boutique",
      owner: merchant.doc("users/merchant_uid"),
    }),
  );
});
