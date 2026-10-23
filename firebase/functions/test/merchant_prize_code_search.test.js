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

test('claimed codes are suggested flagged by their data; unknown and other merchants codes never', async () => {
  await seed();
  for (const id of ['used', 'rival']) await sync(db.doc('prizes/' + id));
  assert.deepEqual((await search('code_merchant', 'USED1234')).ids, ['used']);
  assert.deepEqual((await search('code_merchant', 'USED')).ids, ['used']);
  assert.equal((await db.doc('prizes/used').get()).data().claimed, true, 'still claimed: the app shows it as such');
  assert.deepEqual((await search('code_merchant', 'NOPE0000')).ids, []);
  assert.deepEqual((await search('code_merchant', 'RIVAL123')).ids, []);
  assert.deepEqual((await search('code_merchant', 'RIV')).ids, []);
  assert.deepEqual((await search('rival', 'RIVAL123')).ids, ['rival']);
});

// Two merchants side by side: each only ever sees its own codes, including
// legacy prizes attached only to its shop, and nothing the caller sends can
// widen the scope.
test('two merchants are fully isolated, even when the callable is invoked directly', async () => {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  const alice = db.doc('users/alice'), bob = db.doc('users/bob');
  await db.doc('enseignes/alice_shop').set({owner: alice});
  await db.doc('enseignes/bob_shop').set({owner_id: bob});
  // Conflicting owner fields: the shop belongs to nobody.
  await db.doc('enseignes/disputed_shop').set({owner: alice, owner_id: bob});
  const prizes = {
    alice_owned: {owner_id: alice, claim_code: 'SHARED01'},
    alice_shop_only: {enseigne_id: db.doc('enseignes/alice_shop'), claim_code: 'SHARED02'},
    bob_owned: {owner_id: bob, claim_code: 'SHARED03'},
    bob_shop_only: {enseigne_id: db.doc('enseignes/bob_shop'), claim_code: 'SHARED04'},
    // Explicit owner wins over the shop: this one is Bob's even in Alice's shop.
    bob_in_alice_shop: {owner_id: bob, enseigne_id: db.doc('enseignes/alice_shop'), claim_code: 'SHARED05'},
    disputed: {enseigne_id: db.doc('enseignes/disputed_shop'), claim_code: 'SHARED06'},
  };
  for (const [id, data] of Object.entries(prizes)) {
    await db.doc('prizes/' + id).set({claimed: false, ...data});
    await sync(db.doc('prizes/' + id));
  }
  const ids = async uid => new Set((await search(uid, 'SHARED')).ids);
  assert.deepEqual(await ids('alice'), new Set(['alice_owned', 'alice_shop_only']));
  assert.deepEqual(await ids('bob'), new Set(['bob_owned', 'bob_shop_only', 'bob_in_alice_shop']));
  assert.deepEqual(await ids('stranger'), new Set());
  for (const code of ['SHARED03', 'SHARED04', 'SHARED05', 'SHARED06']) {
    assert.deepEqual((await search('alice', code)).ids, [], code);
  }

  // The callable takes the identity from the auth context only.
  const ft = require('firebase-functions-test')();
  const callable = ft.wrap(require('../merchant_prizes').searchMerchantPrizeCodes);
  const forged = {prefix: 'SHARED', uid: 'bob', merchantId: 'bob', ownerId: 'users/bob', enseigneId: 'bob_shop'};
  const viaCallable = await callable(forged, {auth: {uid: 'alice'}});
  assert.deepEqual(new Set(viaCallable.ids), new Set(['alice_owned', 'alice_shop_only']));
  await assert.rejects(callable(forged, {}), {code: 'unauthenticated'});
  ft.cleanup();
});

test('prizes that can still be handed over come before claimed ones', async () => {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  for (let i = 0; i < 6; i++) await db.doc('prizes/claimed' + i).set({owner_id: merchant, claim_code: 'ORD0000' + i, claimed: true});
  for (let i = 0; i < 2; i++) await db.doc('prizes/open' + i).set({owner_id: merchant, claim_code: 'ORD0009' + i, claimed: false});
  for (const d of (await db.collection('prizes').get()).docs) await sync(d.ref);
  const {ids} = await search('code_merchant', 'ORD');
  assert.equal(ids.length, 5);
  assert.deepEqual(ids.slice(0, 2).sort(), ['open0', 'open1']);
  assert.ok(ids.slice(2).every(id => id.startsWith('claimed')));
});

test('search writes nothing to prizes', async () => {
  await seed();
  const before = (await db.collection('prizes').get()).docs.map(d => JSON.stringify(d.data())).sort();
  await search('code_merchant', 'HX7K2M9Q');
  await search('code_merchant', 'USED1234');
  const after = (await db.collection('prizes').get()).docs.map(d => JSON.stringify(d.data())).sort();
  assert.deepEqual(after, before);
});
