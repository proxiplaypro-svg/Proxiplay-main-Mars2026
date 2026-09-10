// Emulator-only business-path helpers. No production credentials or network APIs.
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-lifecycle';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');
const ft = require('firebase-functions-test')({projectId: process.env.GCLOUD_PROJECT});
const clock = require('../lib/emulator_runtime');
const defaultDate = clock.getEmulatorNowDate;
clock.getEmulatorNowDate = () => process.env.LIFECYCLE_TEST_NOW
  ? new Date(process.env.LIFECYCLE_TEST_NOW) : defaultDate();
clock.getNowTimestamp = sdk => sdk.firestore.Timestamp.fromDate(clock.getEmulatorNowDate());
// The referral suite installs its failure injection before loading that module.
if (process.env.LIFECYCLE_REFERRAL_ONLY === 'true') admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const functions = process.env.LIFECYCLE_REFERRAL_ONLY === 'true' ? {} : require('../index');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {merchantPrizesPage} = require('../merchant_prizes');
const {syncLotSnapshot} = require('../prize_lot_snapshot');
const db = admin.firestore();
const time = value => admin.firestore.Timestamp.fromDate(new Date(value));
const now = () => time(process.env.EMULATOR_TEST_DATE + 'T12:00:00Z');
const play = ft.wrap(functions.participateInGameTransaction || require('../participate_in_game_transaction').participateInGameTransaction);
let env;
test.before(async () => {
  env = await initializeTestEnvironment({projectId: process.env.GCLOUD_PROJECT,
    firestore: {host: '127.0.0.1', port: 8080, rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8')}});
});
test.beforeEach(async () => {
  delete process.env.LIFECYCLE_TEST_NOW;
  process.env.EMULATOR_TEST_DATE = '2026-09-09';
  await env.clearFirestore();
  for (const [id, role] of [['player', 'joueur'], ['merchant', 'commercant'], ['other', 'commercant'], ['operator', 'admin']]) {
    await db.doc('users/' + id).set({user_role: role, first_name: id, remaining_part: 30});
  }
  await db.doc('enseignes/shop').set({name: 'Fixture', owner: db.doc('users/merchant')});
});
test.after(async () => { delete process.env.EMULATOR_TEST_DATE; await env.cleanup(); ft.cleanup(); });
async function game(id = 'game', extra = {}) {
  await db.doc('games/' + id).set({name: 'Lot fixture', hasMainPrize: true, hasWinner: false,
    status: 'active', access_mode: 'public', create_by: db.doc('users/operator'), owner_id: db.doc('users/merchant'),
    enseigne_id: db.doc('enseignes/shop'), participations: 0,
    start_date: time('2026-09-01'), end_date: time('2026-09-30T20:00:00Z'),
    prize_usage_deadline: time('2030-01-01'), ...extra});
  return db.doc('games/' + id);
}
async function participate(id = 'game', uid = 'player', extra = {}) {
  return play({gameRef: id, from_qr: false, ...extra}, {auth: {uid}});
}
async function instant(gameId = 'game', id = 'instant', date = '2026-09-09T11:00:00Z') {
  await db.doc(`games/${gameId}/instant_winners/${id}`).set({date: time(date), hasWinner: false,
    secondary_prize_name: 'Gain instantané', secondary_prize_presentation: 'Fixture'});
}
const client = uid => env.authenticatedContext(uid).firestore();
async function verifyPrize(id, {platform = false, winner = 'player'} = {}) {
  const ref = db.doc('prizes/' + id), prize = (await ref.get()).data();
  assert.ok(prize, 'persisted prize');
  assert.equal(prize.winner_id.path, 'users/' + winner);
  assert.match(prize.claim_code, /^[A-Z0-9]+$/);
  assert.ok(prize.claim_code.length >= 8);
  assert.equal(prize.claimed, false);
  assert.equal(prize.fulfillment_type, platform ? 'platform' : 'merchant');
  const link = await assertSucceeds(client(winner).doc(`users/${winner}/my_lots/${id}`).get());
  assert.equal(link.data().prize_id.path, ref.path);
  await assertSucceeds(link.data().prize_id.get());
  await assertFails(client('wrong_winner').doc(ref.path).get());
  await assertFails(client('other').doc(ref.path).get());
  await assertFails(client('other').doc(ref.path).update({claimed: true}));
  const merchantRows = await merchantPrizesPage('merchant');
  assert.equal(merchantRows.ids.includes(id), !platform);
  if (platform) {
    await assertFails(client('merchant').doc(ref.path).update({claimed: true}));
    const operatorRows = await assertSucceeds(client('operator').collection('prizes').get());
    assert.ok(operatorRows.docs.some(d => d.id === id));
    const claim = ft.wrap(require('../operator_prize_claim').claimOperatorPrize);
    const input = {prizeId: id, winnerId: winner, code: prize.claim_code, requestId: 'lifecycle_retry_request'};
    await assert.rejects(claim(input, {auth: {uid: 'merchant'}}), {code: 'permission-denied'});
    const results = await Promise.all([claim(input, {auth: {uid: 'operator'}}), claim(input, {auth: {uid: 'operator'}})]);
    assert.deepEqual(results.map(r => r.status).sort(), ['already_claimed', 'claimed']);
  } else {
    await assertSucceeds(client('merchant').doc(ref.path).get());
    await assertFails(client(winner).doc(ref.path).update({claimed: true}));
    await assertSucceeds(client('merchant').doc(ref.path).update({claimed: true}));
    await assertFails(client('merchant').doc(ref.path).update({claimed: true}));
  }
  await syncLotSnapshot(id);
  const updated = await client(winner).doc(`users/${winner}/my_lots/${id}`).get();
  assert.equal(updated.data().prize_snapshot.claimed, true);
  assert.equal((await ref.get()).data().claimed, true);
  return prize;
}
module.exports = {test, assert, admin, db, ft, functions, time, now, game, instant, participate, verifyPrize, client, assertFails, assertSucceeds};
