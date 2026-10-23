// Winning-code verification for a merchant with many lots: successive
// verifications and searches stay fluid; abuse is still limited; access stays
// scoped to the merchant. Isolated demo emulator only.
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-prize-rate';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const ft = require('firebase-functions-test')({projectId: process.env.GCLOUD_PROJECT});
const mp = require('../merchant_prizes');
const list = ft.wrap(mp.getMerchantPrizes);
const search = ft.wrap(mp.searchMerchantPrizeCodes);
test.after(() => ft.cleanup());

const LOTS = 530;
const code = (i) => 'VERIF' + String(i).padStart(3, '0');
const as = (uid) => ({auth: {uid}});

async function reset() {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  const merchant = db.doc('users/merchant');
  await db.doc('enseignes/shop').set({owner: merchant});
  await db.doc('enseignes/other_shop').set({owner: db.doc('users/other')});
  let batch = db.batch(), n = 0;
  for (let i = 0; i < LOTS; i++) {
    batch.set(db.doc(`prizes/lot${String(i).padStart(3, '0')}`), {owner_id: merchant,
      enseigne_id: db.doc('enseignes/shop'), claim_code: code(i), claim_code_search: code(i),
      fulfillment_type: 'merchant', claimed: false});
    if (++n === 400) { await batch.commit(); batch = db.batch(); n = 0; }
  }
  await batch.commit();
}

// What the app's "Vérifier" does (loadMerchantPrizes): every page of the
// merchant's lots, then the exact code among them.
async function verify(uid, wanted) {
  let cursor = '', pages = 0;
  const ids = [];
  for (;;) {
    const page = await list({gameId: '', cursor}, as(uid));
    pages++;
    ids.push(...page.ids);
    if (!page.hasMore) break;
    cursor = page.cursor;
  }
  const docs = await Promise.all(ids.map((id) => db.doc(`prizes/${id}`).get()));
  return {pages, found: docs.find((d) => d.data().claim_code === wanted) || null, total: ids.length};
}

test('a merchant with 530 lots verifies codes in a row while typing, without being blocked', async () => {
  await reset();
  for (let v = 0; v < 5; v++) {
    // Typing an 8-character code: one search per keystroke from the 3rd one.
    const wanted = code(100 + v);
    for (let len = 3; len <= wanted.length; len++) await search({prefix: wanted.slice(0, len)}, as('merchant'));
    const result = await verify('merchant', wanted);
    assert.equal(result.total, LOTS);
    assert.equal(result.pages, Math.ceil(LOTS / 40));
    assert.ok(result.found, `verification ${v + 1} finds ${wanted}`);
  }
});

test('a verified code can then be handed over, once', async () => {
  await reset();
  const {found} = await verify('merchant', code(42));
  assert.equal(found.data().claimed, false);
  // The handover itself is the merchant's validation update (rules-checked
  // elsewhere); here the server-side state transition.
  await found.ref.update({claimed: true});
  const again = await verify('merchant', code(42));
  assert.equal(again.found.data().claimed, true, 'a second verification shows the lot as already collected');
});

test('starting too many listings in a minute is refused, then allowed again', async () => {
  await reset();
  const limit = mp.kMerchantPrizeRateLimits.listing;
  for (let i = 0; i < limit; i++) await list({gameId: '', cursor: ''}, as('merchant'));
  await assert.rejects(list({gameId: '', cursor: ''}, as('merchant')), {code: 'resource-exhausted'});
  // Another merchant is not affected.
  await list({gameId: '', cursor: ''}, as('other'));
  // A new window opens after one minute.
  await db.doc('_merchant_prize_listing_rate/merchant').update({start: Date.now() - 61000});
  await list({gameId: '', cursor: ''}, as('merchant'));
});

test('bulk paging and search flooding are still limited', async () => {
  await reset();
  const pages = mp.kMerchantPrizeRateLimits.pages;
  await db.doc('_merchant_prize_pages_rate/merchant').set({start: Date.now(), count: pages});
  await assert.rejects(list({gameId: '', cursor: 'lot100'}, as('merchant')), {code: 'resource-exhausted'});
  const searches = mp.kMerchantPrizeRateLimits.search;
  await db.doc('_merchant_prize_search_rate/merchant').set({start: Date.now(), count: searches});
  await assert.rejects(search({prefix: 'VER'}, as('merchant')), {code: 'resource-exhausted'});
  // Exhausted searches do not block verifying a code once the page ceiling
  // has room again.
  await db.doc('_merchant_prize_pages_rate/merchant').delete();
  await list({gameId: '', cursor: ''}, as('merchant'));
});

test('limits never widen access: another merchant sees none of these lots', async () => {
  await reset();
  const result = await verify('other', code(1));
  assert.equal(result.total, 0);
  assert.equal(result.found, null);
  assert.deepEqual((await search({prefix: code(1)}, as('other'))).ids, []);
  await assert.rejects(list({gameId: '', cursor: ''}, {}), {code: 'unauthenticated'});
  await assert.rejects(search({prefix: 'VER'}, {}), {code: 'unauthenticated'});
});
