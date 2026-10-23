// Monthly challenge: lot collected at the partner shop, ProxiPlay lot without
// partner, and a started challenge can only be stopped by an explicit
// cancellation. Isolated demo emulator only.
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-monthly-partner';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const ft = require('firebase-functions-test')({projectId: process.env.GCLOUD_PROJECT});
const monthly = require('../monthly_challenge.js');
const {searchMerchantPrizeCodesCore: search, syncPrizeSearchCodeCore: sync, isSuggestiblePrize} =
  require('../merchant_prizes');
const upsert = ft.wrap(monthly.adminUpsertMonthlyChallengeCallable);
const asAdmin = {auth: {uid: 'admin', token: {admin: true}}};
const ts = iso => admin.firestore.Timestamp.fromDate(new Date(iso));
test.after(() => ft.cleanup());

async function reset() {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  await db.doc('users/winner').set({user_role: 'joueur', first_name: 'Lea', city: 'Lille'});
  await db.doc('users/merchant').set({user_role: 'commercant'});
  await db.doc('users/other_merchant').set({user_role: 'commercant'});
  await db.doc('enseignes/shop').set({name: 'Boutique', owner_id: db.doc('users/merchant')});
  await db.doc('enseignes/orphan').set({name: 'Sans proprio'});
}
// A finished September challenge with one qualified player.
async function finishedChallenge(challengeId, extra = {}) {
  const config = {challenge_id: challengeId, type: 'attendance', enabled: true, month: '2026-09',
    title: 'Defi de septembre', prize_title: 'Bon de 50 EUR', prize_value: 50, target_days: 5,
    start_date: ts('2026-09-01T00:00:00+02:00'), end_date: ts('2026-09-30T00:00:00+02:00'), ...extra};
  await db.doc('monthly_challenges/' + challengeId).set(config);
  await db.doc(`monthly_challenge_entries/${challengeId}_winner`).set({uid: 'winner', month: '2026-09',
    challenge_id: challengeId, type: config.type, user_ref: db.doc('users/winner'), status: 'qualified',
    qualified_at: ts('2026-09-20T10:00:00Z')});
  return monthly.normalizeMonthlyChallengeConfig(config);
}

test('a partner challenge awards a lot collected and verified at the partner shop', async () => {
  await reset();
  const config = await finishedChallenge('merchant_2026-09', {type: 'merchant',
    enseigne_ref: db.doc('enseignes/shop'), enseigne_name: 'Boutique'});
  const result = await monthly.drawWinnerForMonthlyChallenge(config, 'test');
  assert.equal(result.status, 'completed');
  const prizeRef = db.doc('prizes/monthly_challenge_merchant_2026-09');
  const prize = (await prizeRef.get()).data();
  assert.equal(prize.fulfillment_type, 'merchant');
  assert.equal(prize.enseigne_id.path, 'enseignes/shop');
  assert.equal(prize.owner_id.path, 'users/merchant');
  assert.equal(prize.winner_id.path, 'users/winner');
  assert.equal(isSuggestiblePrize(prize), true);
  // The partner finds it by its code; another merchant never does.
  await sync(prizeRef);
  assert.deepEqual((await search('merchant', prize.claim_code)).ids, [prizeRef.id]);
  assert.deepEqual((await search('other_merchant', prize.claim_code)).ids, []);
});

test('without a partner it stays a ProxiPlay lot, never offered to merchants', async () => {
  await reset();
  const config = await finishedChallenge('2026-09');
  assert.equal((await monthly.drawWinnerForMonthlyChallenge(config, 'test')).status, 'completed');
  const prize = (await db.doc('prizes/monthly_challenge_2026-09').get()).data();
  assert.equal(prize.fulfillment_type, 'platform');
  assert.equal(prize.owner_id, undefined);
  assert.equal(isSuggestiblePrize(prize), false);
});

test('a partner shop without a merchant is reviewed instead of awarding an unclaimable lot', async () => {
  await reset();
  const config = await finishedChallenge('merchant_2026-09', {type: 'merchant',
    enseigne_ref: db.doc('enseignes/orphan')});
  const result = await monthly.drawWinnerForMonthlyChallenge(config, 'test');
  assert.notEqual(result.status, 'completed');
  assert.equal((await db.doc('prizes/monthly_challenge_merchant_2026-09').get()).exists, false);
  // The qualified player is kept for a retry once the shop is fixed.
  assert.equal((await db.doc('monthly_challenge_entries/merchant_2026-09_winner').get()).data().status, 'qualified');
});

// Challenge of the current month (started) and of next month (not started).
function input(month, extra = {}) {
  const [y, m] = month.split('-').map(Number);
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return {challenge_id: month, type: 'attendance', month, title: 'Defi', prize_title: 'Lot',
    prize_value: 10, target_days: 2, enabled: true,
    start_date: ts(`${month}-01T12:00:00Z`),
    end_date: ts(`${month}-${String(last).padStart(2, '0')}T12:00:00Z`), ...extra};
}
const currentMonth = monthly.getParisMonthKey();
const nextMonth = (() => { const [y, m] = currentMonth.split('-').map(Number);
  return m === 12 ? `${y + 1}-01` : `${y}-${String(m + 1).padStart(2, '0')}`; })();

test('a started challenge cannot be switched off; only an explicit cancellation stops it', async () => {
  await reset();
  await upsert(input(currentMonth), asAdmin);
  await assert.rejects(upsert(input(currentMonth, {enabled: false}), asAdmin),
    {code: 'failed-precondition', message: /annulation/});
  assert.equal((await db.doc('monthly_challenges/' + currentMonth).get()).data().enabled, true);
  await upsert({...input(currentMonth, {enabled: false}), cancel: true}, asAdmin);
  const stored = (await db.doc('monthly_challenges/' + currentMonth).get()).data();
  assert.equal(stored.enabled, false);
  assert.equal(stored.cancelled, true);
  assert.equal(stored.cancelled_by, 'admin');
  assert.ok(stored.cancelled_at);
});

test('a challenge not started yet, or already drawn, can be switched off', async () => {
  await reset();
  await upsert(input(nextMonth), asAdmin);
  await upsert(input(nextMonth, {enabled: false}), asAdmin);
  assert.equal((await db.doc('monthly_challenges/' + nextMonth).get()).data().enabled, false);
  await upsert(input(currentMonth), asAdmin);
  await db.doc('monthly_challenge_draws/' + currentMonth).set({status: 'completed'});
  await upsert(input(currentMonth, {enabled: false}), asAdmin);
  const stored = (await db.doc('monthly_challenges/' + currentMonth).get()).data();
  assert.equal(stored.enabled, false);
  assert.equal(stored.cancelled, undefined);
});

test('only an admin can save or cancel a challenge', async () => {
  await reset();
  await assert.rejects(upsert(input(nextMonth), {auth: {uid: 'merchant', token: {}}}), {code: 'permission-denied'});
  await assert.rejects(upsert(input(nextMonth), {}), {code: 'unauthenticated'});
});

test('the web Admin account reads a challenge with its partner as a path and its draw state', async () => {
  await reset();
  const get = ft.wrap(monthly.adminGetMonthlyChallengeConfigCallable);
  const webAdmin = {auth: {uid: 'web-admin', token: {email: 'proxiplay.pro@gmail.com'}}};
  await upsert(input(nextMonth, {type: 'merchant', challenge_id: 'merchant_' + nextMonth,
    enseigne_ref: 'enseignes/shop', enseigne_name: 'Boutique'}), webAdmin);
  const config = await get({type: 'merchant', month: nextMonth}, webAdmin);
  assert.equal(config.enseigne_ref, 'enseignes/shop');
  assert.equal(config.cancelled, false);
  assert.equal(config.draw_status, '');
  // The response can be sent by the callable protocol (no raw references).
  assert.doesNotThrow(() => JSON.stringify(config));
  await assert.rejects(get({type: 'merchant', month: nextMonth}, {auth: {uid: 'merchant', token: {email: 'x@example.test'}}}),
    {code: 'permission-denied'});
});
