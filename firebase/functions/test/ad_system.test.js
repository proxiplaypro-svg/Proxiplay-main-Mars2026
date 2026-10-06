process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-ad-system';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const {recordAdEventHandler} = require('../ad_system');

async function clearCollections() {
  const snap = await db.collection('ads').get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

test.beforeEach(async () => {
  await clearCollections();
});

test('rejects an unknown placement', async () => {
  await assert.rejects(
    () => recordAdEventHandler({placement: 'not_a_real_placement', type: 'impression'}),
    (err) => err.code === 'invalid-argument',
  );
});

test('rejects an unknown event type', async () => {
  await assert.rejects(
    () => recordAdEventHandler({placement: 'open', type: 'not_a_real_type'}),
    (err) => err.code === 'invalid-argument',
  );
});

test('records an impression without requiring authentication (data has no context.auth)', async () => {
  const result = await recordAdEventHandler({placement: 'open', type: 'impression'});
  assert.equal(result.status, 'recorded');
  const snap = await db.doc('ads/open').get();
  assert.equal(snap.data().impressions, 1);
});

test('records a click on the exact placement doc, distinct field from impressions', async () => {
  await recordAdEventHandler({placement: 'home_banner', type: 'impression'});
  await recordAdEventHandler({placement: 'home_banner', type: 'click'});
  const snap = await db.doc('ads/home_banner').get();
  assert.equal(snap.data().impressions, 1);
  assert.equal(snap.data().clicks, 1);
});

test('increments atomically across repeated calls (no overwrite/race)', async () => {
  await Promise.all([
    recordAdEventHandler({placement: 'open', type: 'impression'}),
    recordAdEventHandler({placement: 'open', type: 'impression'}),
    recordAdEventHandler({placement: 'open', type: 'impression'}),
  ]);
  const snap = await db.doc('ads/open').get();
  assert.equal(snap.data().impressions, 3);
});

test('works even if the placement document does not exist yet (merge-create)', async () => {
  await recordAdEventHandler({placement: 'open', type: 'click'});
  const snap = await db.doc('ads/open').get();
  assert.equal(snap.data().clicks, 1);
});
