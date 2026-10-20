// Winning-code search for merchants, including historical prizes created
// before claim_code_search existed. Isolated demo emulator only.
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST || !String(process.env.GCLOUD_PROJECT || '').startsWith('demo-')) {
  throw Error('demo emulator required');
}
if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const {searchMerchantPrizeCodesCore: search, syncPrizeSearchCodeCore: sync} = require('../merchant_prizes');

const merchant = db.doc('users/code_merchant');
const rival = db.doc('users/rival');
// Codes have the production format: 8, 12 or 20 uppercase alphanumerics.
async function seed() {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  await db.doc('enseignes/shop').set({owner: merchant});
  await db.doc('enseignes/rival_shop').set({owner: rival});
  await Promise.all([
    // Historical: no claim_code_search, as all 2,010 prizes in production today.
    db.doc('prizes/historical').set({owner_id: merchant, enseigne_id: db.doc('enseignes/shop'), claim_code: 'HX7K2M9Q', fulfillment_type: 'merchant', claimed: false}),
    db.doc('prizes/historical_long').set({owner_id: merchant, claim_code: 'HX7K2M9QAB12', claimed: false}),
    db.doc('prizes/used').set({owner_id: merchant, claim_code: 'USED1234', claimed: true}),
    db.doc('prizes/rival').set({owner_id: rival, enseigne_id: db.doc('enseignes/rival_shop'), claim_code: 'RIVAL123', claimed: false}),
  ]);
}

test('a full historical code is found before any migration, partial codes after it', async () => {
  await seed();
  assert.deepEqual((await search('code_merchant', 'HX7K2M9Q')).ids, ['historical']);
  assert.deepEqual((await search('code_merchant', ' hx7k-2m9q ')).ids, ['historical'], 'normalized input');
  assert.deepEqual((await search('code_merchant', 'HX7K')).ids, [], 'prefix needs claim_code_search');
  for (const id of ['historical', 'historical_long']) await sync(db.doc('prizes/' + id));
  assert.deepEqual(new Set((await search('code_merchant', 'HX7K')).ids), new Set(['historical', 'historical_long']));
  assert.deepEqual((await search('code_merchant', 'HX7K2M9QAB')).ids, ['historical_long']);
});

test('used, unknown and other merchants codes are never suggested', async () => {
  await seed();
  for (const id of ['used', 'rival']) await sync(db.doc('prizes/' + id));
  assert.deepEqual((await search('code_merchant', 'USED1234')).ids, []);
  assert.deepEqual((await search('code_merchant', 'USED')).ids, []);
  assert.deepEqual((await search('code_merchant', 'NOPE0000')).ids, []);
  assert.deepEqual((await search('code_merchant', 'RIVAL123')).ids, []);
  assert.deepEqual((await search('code_merchant', 'RIV')).ids, []);
  assert.deepEqual((await search('rival', 'RIVAL123')).ids, ['rival']);
});

test('search writes nothing to prizes', async () => {
  await seed();
  const before = (await db.collection('prizes').get()).docs.map(d => JSON.stringify(d.data())).sort();
  await search('code_merchant', 'HX7K2M9Q');
  await search('code_merchant', 'USED1234');
  const after = (await db.collection('prizes').get()).docs.map(d => JSON.stringify(d.data())).sort();
  assert.deepEqual(after, before);
});
