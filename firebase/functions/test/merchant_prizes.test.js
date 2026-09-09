process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-merchant-prizes';
const {test, before, after, beforeEach} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const {merchantPrizesPage, getMerchantPrizes} = require('../merchant_prizes');
let env;
before(async () => {
  env = await initializeTestEnvironment({projectId: process.env.GCLOUD_PROJECT,
    firestore: {host: '127.0.0.1', port: 8080,
      rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8')}});
});
after(async () => env?.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await db.doc('enseignes/shop').set({owner: '/users/merchant', owner_id: db.doc('users/merchant')});
  await db.doc('enseignes/other').set({owner: db.doc('users/other')});
  await db.doc('games/admin_game').set({owner_id: db.doc('users/merchant'),
    create_by: db.doc('users/admin'), enseigne_id: db.doc('enseignes/shop')});
  for (const [id, extra] of Object.entries({
    a_conflict: {owner_id: db.doc('users/other'), enseigne_id: db.doc('enseignes/shop')},
    b_modern: {owner_id: db.doc('users/merchant'), enseigne_id: db.doc('enseignes/shop'), fulfillment_type: 'merchant'},
    c_shop: {enseigne_id: db.doc('enseignes/shop')},
    d_owner: {owner_id: db.doc('users/merchant')},
    e_other_shop: {enseigne_id: db.doc('enseignes/other')},
    f_unrouted: {},
  })) await db.doc('prizes/' + id).set({game_id: db.doc('games/admin_game'),
    winner_id: db.doc('users/winner'), claimed: false, prize_type: 'principal', ...extra});
});
async function all(uid, gameId) {
  let cursor = '', ids = [];
  for (let i = 0; i < 20; i++) {
    const page = await merchantPrizesPage(uid, {gameId, cursor, pageSize: 1});
    ids.push(...page.ids);
    if (!page.hasMore) return ids;
    assert.notEqual(page.cursor, cursor);
    cursor = page.cursor;
  }
  throw Error('Pagination did not terminate');
}
test('actual mobile listing includes modern + historical prizes of admin game, across filtered empty pages', async () => {
  for (const game of ['', 'admin_game']) {
    const ids = await all('merchant', game);
    assert.deepEqual(ids, ['b_modern', 'c_shop', 'd_owner']);
    // The callable returns IDs; Flutter must also pass strict individual reads.
    for (const id of ids) {
      const ref = env.authenticatedContext('merchant').firestore().doc('prizes/' + id);
      await assertSucceeds(ref.get());
      await assertSucceeds(ref.update({claimed: true}));
      await db.doc('prizes/' + id).update({claimed: false});
    }
  }
});
test('other merchant cannot list the game, read or claim its legitimate prizes', async () => {
  await assert.rejects(all('other', 'admin_game'), {code: 'permission-denied'});
  for (const id of ['b_modern', 'c_shop', 'd_owner']) {
    const ref = env.authenticatedContext('other').firestore().doc('prizes/' + id);
    await assertFails(ref.get());
    await assertFails(ref.update({claimed: true}));
  }
});
test('explicit different owner prevents shop fallback; winner alone retains beneficiary access', async () => {
  const ref = env.authenticatedContext('merchant').firestore().doc('prizes/a_conflict');
  await assertFails(ref.get());
  await assertFails(ref.update({claimed: true}));
  await assertSucceeds(env.authenticatedContext('winner').firestore().doc('prizes/c_shop').get());
  await assertFails(env.authenticatedContext('wrong_winner').firestore().doc('prizes/c_shop').get());
});
test('conflicting shop ownership fails closed and anonymous callable is refused', async () => {
  await db.doc('enseignes/shop').update({owner: '/users/other'});
  assert.deepEqual((await merchantPrizesPage('merchant')).ids, ['b_modern', 'd_owner']);
  await assertFails(env.authenticatedContext('merchant').firestore().doc('prizes/c_shop').get());
  await assert.rejects(getMerchantPrizes.run({}, {}), {code: 'unauthenticated'});
});
