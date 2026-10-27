// Referral game suspension (Admin "Suspendre" / "Reactiver"): a suspended game
// gets no new ticket and is never started again automatically, its existing
// tickets are kept, a refused reactivation stays suspended, and a later repair
// never adds a ticket to a referral that already received the classic reward.
// Disposable demo emulator only.
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST ||
    !String(process.env.GCLOUD_PROJECT || '').startsWith('demo-')) {
  throw new Error('An isolated demo Firestore emulator is required');
}
// index.js initializes the default app itself: load it first.
const functions = require('../index.js');
if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const ft = require('firebase-functions-test')({projectId: process.env.GCLOUD_PROJECT});
const share = require('../lib/share_promo');
const {acceptReferralForNewAccount} = require('../lib/share_promo/new_account_referral');
const {reconcileReferralGameTickets} = require('../lib/share_promo/referral_games');
const {processReferralReward, pendingRef} = require('../referral_reward_queue');
const {enforceSingleActiveReferralGame, kLockPath} = require('../referral_game_lock');
const autoManage = ft.wrap(functions.autoManageReferralGames);
const lockTrigger = ft.wrap(functions.enforceSingleActiveReferralGame);
const grantAsAdmin = ft.wrap(share.grantReferralReward);
const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
const HOUR = 3600 * 1000;
const asAdmin = {auth: {uid: 'admin', token: {admin: true}}};
const grantClassic = (referralId) => grantAsAdmin({referralId}, asAdmin);

async function game(id, extra = {}) {
  const now = Date.now();
  await db.doc(`referral_games/${id}`).set({title: 'Jeu ' + id, status: 'active',
    start_date: ts(now - HOUR), end_date: ts(now + HOUR), ticket_count: 0, ...extra});
  return enforceSingleActiveReferralGame(id);
}

// Status change as the Admin API writes it, then the lock trigger.
async function setStatus(id, status) {
  const before = await db.doc(`referral_games/${id}`).get();
  await db.doc(`referral_games/${id}`).update({status});
  const after = await db.doc(`referral_games/${id}`).get();
  return lockTrigger(ft.makeChange(before, after), {params: {gameId: id}});
}

async function validate(code, invitee, {process = true} = {}) {
  await db.doc(`referrals/${code}`).set({inviterUid: 'inviter', inviteCode: code,
    status: 'pending', rewardStatus: 'not_earned', rewardType: 'all_games_until_midnight',
    rewardValue: 1, metadata: {}, createdAt: ts(Date.now() - 2 * HOUR)});
  await db.doc(`users/${invitee}`).set({user_role: 'joueur'});
  const outcome = await acceptReferralForNewAccount({referralRef: db.doc(`referrals/${code}`), uid: invitee});
  assert.equal(outcome.accepted, true, code);
  if (process) await processReferralReward(code, grantClassic);
}

const entries = async (id) =>
  (await db.collection(`referral_games/${id}/entries`).get()).docs.map((d) => d.id).sort();

test.beforeEach(async () => {
  for (const collection of await db.listCollections()) await db.recursiveDelete(collection);
  await db.doc('app_config/share_promo').set({enabled: true, isDraft: false,
    rewardType: 'all_games_until_midnight', rewardValue: 1,
    maxRewardsPerUser: 20, maxRewardsPerInvitee: 3, requireInviteeSignup: true});
  await Promise.all([
    db.doc('users/inviter').set({user_role: 'joueur', remaining_part: 3, email: 'parrain@example.fr'}),
    db.doc('users/admin').set({user_role: 'admin'}),
  ]);
});
test.after(() => ft.cleanup());

test('suspended: lock released, no new ticket (classic reward), existing and queued tickets kept', async () => {
  await game('S');
  await validate('r1', 'f1');
  await validate('r3', 'f3', {process: false}); // accepted while active, processed later
  assert.equal((await setStatus('S', 'suspended')).status, 'released');
  assert.equal((await db.doc(kLockPath).get()).data().game_id, null);

  await validate('r2', 'f2');
  assert.equal((await pendingRef('r2').get()).data().mode, 'classic');
  assert.ok((await db.doc('users/inviter').get()).data().allGamesAccessUntil, 'classic bonus');

  await processReferralReward('r3', grantClassic);
  assert.deepEqual(await entries('S'), ['r1', 'r3'], 'tickets of the active period kept');
  assert.equal((await db.doc('referral_games/S').get()).data().ticket_count, 2);
});

test('autoManageReferralGames never starts a suspended game, still starts a due draft', async () => {
  const now = Date.now();
  await db.doc('referral_games/S').set({status: 'suspended',
    start_date: ts(now - 2 * HOUR), end_date: ts(now + HOUR), ticket_count: 1});
  await autoManage({});
  assert.equal((await db.doc('referral_games/S').get()).data().status, 'suspended');
  await db.doc('referral_games/D').set({status: 'draft',
    start_date: ts(now - HOUR), end_date: ts(now + HOUR), ticket_count: 0});
  await autoManage({});
  assert.equal((await db.doc('referral_games/S').get()).data().status, 'suspended');
  assert.equal((await db.doc('referral_games/D').get()).data().status, 'active');
});

test('a refused reactivation stays suspended (not draft); allowed once the other game ends', async () => {
  await game('S');
  await setStatus('S', 'suspended');
  assert.equal((await game('B')).status, 'locked');
  assert.deepEqual(await setStatus('S', 'active'), {status: 'refused', activeGameId: 'B'});
  const s = (await db.doc('referral_games/S').get()).data();
  assert.equal(s.status, 'suspended');
  assert.equal(s.activation_refused_reason, 'another_active_game');
  // A draft refused the same way still goes back to draft, as before.
  await db.doc('referral_games/D').set({status: 'draft',
    start_date: ts(Date.now() - HOUR), end_date: ts(Date.now() + HOUR), ticket_count: 0});
  assert.equal((await setStatus('D', 'active')).status, 'refused');
  assert.equal((await db.doc('referral_games/D').get()).data().status, 'draft');

  await setStatus('B', 'ended');
  assert.equal((await setStatus('S', 'active')).status, 'locked');
  assert.equal((await db.doc(kLockPath).get()).data().game_id, 'S');
});

test('repair never adds a ticket to a referral rewarded with the classic bonus', async () => {
  await game('S');
  await validate('r1', 'f1');
  await setStatus('S', 'suspended');
  await validate('r2', 'f2'); // classic reward during the suspension
  await setStatus('S', 'active');
  await db.doc('referral_games/S/entries/r1').delete(); // lost ticket of the active period
  const result = await reconcileReferralGameTickets('S');
  assert.deepEqual(await entries('S'), ['r1'], 'r1 repaired, r2 untouched');
  assert.equal(result.created, 1);
  assert.equal(result.ineligible, 1);
});
