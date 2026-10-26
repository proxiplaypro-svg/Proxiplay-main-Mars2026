// Referral game safety (26/10/2026): one ticket per validated referral during
// a game and no classic bonus nor its communications; classic reward outside
// a game; a single active game, whatever the writers; a draw that waits for
// every ticket due; a ticket confirmation distinct from the bonus one; the
// displayed count equal to the drawn tickets. Disposable demo emulator only.
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST ||
    !String(process.env.GCLOUD_PROJECT || '').startsWith('demo-')) {
  throw new Error('An isolated demo Firestore emulator is required');
}
if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const ft = require('firebase-functions-test')({projectId: process.env.GCLOUD_PROJECT});
const share = require('../lib/share_promo');
const {acceptReferralForNewAccount} = require('../lib/share_promo/new_account_referral');
const {processReferralReward, retryPendingReferralRewards, pendingRef} = require('../referral_reward_queue');
const {enforceSingleActiveReferralGame, kLockPath} = require('../referral_game_lock');
const {drawReferralGame} = require('../referral_game_engine');
const grantAsAdmin = ft.wrap(share.grantReferralReward);
const state = ft.wrap(share.getSharePromoState);
const ack = ft.wrap(share.acknowledgeReferralBonusNotice);
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

// A referral validated at account creation, then its reward processed.
async function validate(code, invitee, {process = true} = {}) {
  await db.doc(`referrals/${code}`).set({inviterUid: 'inviter', inviteCode: code,
    status: 'pending', rewardStatus: 'not_earned', rewardType: 'all_games_until_midnight',
    rewardValue: 1, metadata: {}, createdAt: ts(Date.now() - 2 * HOUR)});
  await db.doc(`users/${invitee}`).set({user_role: 'joueur'});
  const outcome = await acceptReferralForNewAccount({referralRef: db.doc(`referrals/${code}`), uid: invitee});
  assert.equal(outcome.accepted, true, code);
  if (process) await processReferralReward(code, grantClassic);
}

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

test('during a game: one ticket per validated referral, no classic bonus nor its communications', async () => {
  assert.equal((await game('G')).status, 'locked');
  for (const [code, invitee] of [['r1', 'f1'], ['r2', 'f2'], ['r3', 'f3']]) await validate(code, invitee);
  const entries = await db.collection('referral_games/G/entries').get();
  assert.deepEqual(entries.docs.map((d) => d.id).sort(), ['r1', 'r2', 'r3'], 'three distinct tickets');
  const g = (await db.doc('referral_games/G').get()).data();
  assert.equal(g.ticket_count, 3);
  assert.equal(g.pending_reward_count, 0);
  const inviter = (await db.doc('users/inviter').get()).data();
  assert.equal(inviter.allGamesAccessUntil, undefined, 'no classic bonus');
  assert.equal(inviter.referralBonusExpiresAt, undefined);
  assert.equal(inviter.remaining_part, 3, 'tickets do not touch the daily chances');
  assert.equal((await db.collection('reward_events').get()).size, 0, 'no bonus e-mail trigger');
  assert.equal((await db.collection('ff_push_notifications').get()).size, 0, 'no bonus push');
  const shareState = (await db.doc('users/inviter/private/share_state').get()).data();
  assert.equal(shareState.referralBonusNotice, undefined, 'no bonus window');
  // Invitees get neither bonus nor ticket.
  for (const invitee of ['f1', 'f2', 'f3']) {
    const u = (await db.doc(`users/${invitee}`).get()).data();
    assert.equal(u.allGamesAccessUntil, undefined);
    assert.equal(entries.docs.some((d) => d.data().inviter_uid === invitee), false);
  }
});

test('a validated referral is processed once, even with double calls and retries', async () => {
  await game('G');
  await validate('r1', 'f1', {process: false});
  await Promise.all([processReferralReward('r1'), processReferralReward('r1'), retryPendingReferralRewards()]);
  await retryPendingReferralRewards();
  assert.equal((await db.collection('referral_games/G/entries').get()).size, 1);
  const g = (await db.doc('referral_games/G').get()).data();
  assert.equal(g.ticket_count, 1);
  assert.equal(g.pending_reward_count, 0);
  // The same invitee can never validate a second referral.
  await db.doc('referrals/r2').set({inviterUid: 'inviter', inviteCode: 'r2', status: 'pending', metadata: {}});
  const again = await acceptReferralForNewAccount({referralRef: db.doc('referrals/r2'), uid: 'f1'});
  assert.equal(again.accepted, false);
  // A shared link alone gives nothing.
  assert.equal((await pendingRef('r2').get()).exists, false);
});

test('outside the period or with a game not active: the classic reward', async () => {
  const now = Date.now();
  for (const [id, extra] of [
    ['future', {start_date: ts(now + HOUR), end_date: ts(now + 2 * HOUR)}],
    ['past', {start_date: ts(now - 2 * HOUR), end_date: ts(now - HOUR)}],
    ['draft', {status: 'draft'}],
    ['ended', {status: 'ended'}],
  ]) {
    for (const c of await db.listCollections()) {
      if (['referrals', 'referral_reward_pending', 'reward_events', 'referral_games', 'app_config'].includes(c.id)) {
        await db.recursiveDelete(c);
      }
    }
    await db.doc('app_config/share_promo').set({enabled: true, isDraft: false,
      rewardType: 'all_games_until_midnight', rewardValue: 1});
    await db.doc('users/inviter').set({user_role: 'joueur', email: 'parrain@example.fr'});
    await game(id, extra);
    await validate('r_' + id, 'f_' + id);
    assert.equal((await pendingRef('r_' + id).get()).data().mode, 'classic', id);
    assert.ok((await db.doc('users/inviter').get()).data().allGamesAccessUntil, id + ': classic bonus');
    assert.equal((await db.collection(`referral_games/${id}/entries`).get()).size, 0, id);
  }
});

test('a single active game: a second activation is refused, also when concurrent', async () => {
  assert.equal((await game('A')).status, 'locked');
  assert.deepEqual(await game('B'), {status: 'refused', activeGameId: 'A'});
  const b = (await db.doc('referral_games/B').get()).data();
  assert.equal(b.status, 'draft');
  assert.equal(b.activation_refused_reason, 'another_active_game');
  // A ends: the lock is released, then two games are activated at once.
  await db.doc('referral_games/A').update({status: 'ended'});
  assert.equal((await enforceSingleActiveReferralGame('A')).status, 'released');
  const now = Date.now();
  await Promise.all(['C', 'D'].map((id) => db.doc(`referral_games/${id}`).set({status: 'active',
    start_date: ts(now - HOUR), end_date: ts(now + HOUR), ticket_count: 0})));
  const results = await Promise.all(['C', 'D', 'C', 'D'].map((id) => enforceSingleActiveReferralGame(id)));
  const active = (await db.collection('referral_games').where('status', '==', 'active').get()).docs.map((d) => d.id);
  assert.equal(active.length, 1, JSON.stringify(results));
  assert.equal((await db.doc(kLockPath).get()).data().game_id, active[0]);
});

test('two active games without lock: the signup still succeeds, with the classic reward', async () => {
  const now = Date.now();
  for (const id of ['X', 'Y']) {
    await db.doc(`referral_games/${id}`).set({status: 'active',
      start_date: ts(now - HOUR), end_date: ts(now + HOUR), ticket_count: 0});
  }
  await validate('r1', 'f1');
  assert.equal((await pendingRef('r1').get()).data().mode, 'classic');
  assert.ok((await db.doc('users/inviter').get()).data().allGamesAccessUntil);
});

test('a ticket processed after the end is kept; the draw waits for it, then counts it', async () => {
  await game('G');
  await validate('r1', 'f1');
  await validate('r2', 'f2', {process: false});
  assert.equal((await db.doc('referral_games/G').get()).data().pending_reward_count, 1);
  // The game ends right after the second acceptance, before its processing.
  const accepted = (await db.doc('referrals/r2').get()).data().acceptedAt.toMillis();
  const after = Date.now() + 2 * HOUR;
  await db.doc('referral_games/G').update({end_date: ts(accepted + 1), status: 'ended'});
  assert.equal((await drawReferralGame('G', {now: ts(after)})).status, 'manual_review_required',
    'the draw waits for the ticket due');
  assert.equal((await db.doc('referral_games/G').get()).data().draw_status, undefined);
  assert.equal((await processReferralReward('r2')).status, 'granted', 'eligibility from the acceptance date');
  const drawn = await drawReferralGame('G', {now: ts(after)});
  assert.equal(drawn.status, 'completed');
  const g = (await db.doc('referral_games/G').get()).data();
  const shown = await db.collection('referral_games/G/entries').where('inviter_uid', '==', 'inviter').get();
  assert.equal(shown.size, 2, 'what the app displays');
  assert.equal(g.total_ticket_count, 2, 'what the draw used');
  assert.equal(g.eligible_ticket_count, 2);
  assert.equal(g.ticket_count, 2);
  assert.equal(g.winner_uid, 'inviter');
});

test('a game drawn before processing: explicit manual review, counter released', async () => {
  await game('G');
  await validate('r1', 'f1', {process: false});
  await db.doc('referral_games/G').update({draw_status: 'completed', winner_uid: 'someone'});
  const result = await processReferralReward('r1');
  assert.deepEqual(result, {status: 'manual_review_required', reason: 'draw_already_finalized'});
  assert.equal((await pendingRef('r1').get()).data().status, 'manual_review_required');
  assert.equal((await db.doc('referral_games/G').get()).data().pending_reward_count, 0);
  assert.equal((await db.collection('referral_games/G/entries').get()).size, 0);
});

test('manual review procedure: cause fixed, event back to pending, ticket granted once', async () => {
  await game('G');
  await validate('r1', 'f1', {process: false});
  const accepted = (await db.doc('referrals/r1').get()).data().acceptedAt.toMillis();
  // Dates changed by mistake after the acceptance: review required.
  await db.doc('referral_games/G').update({start_date: ts(accepted + 1000)});
  assert.equal((await processReferralReward('r1')).status, 'manual_review_required');
  assert.equal((await drawReferralGame('G', {allowEarly: true})).status, 'manual_review_required',
    'the draw waits while the review is open');
  // Procedure: dates restored, event put back to pending, worker run.
  await db.doc('referral_games/G').update({start_date: ts(accepted - HOUR)});
  await pendingRef('r1').update({status: 'pending'});
  await retryPendingReferralRewards();
  assert.equal((await pendingRef('r1').get()).data().status, 'granted');
  const g = (await db.doc('referral_games/G').get()).data();
  assert.equal(g.pending_reward_count, 0, 'released once only');
  assert.equal(g.ticket_count, 1);
});

test('the ticket confirmation is shown once, apart from the bonus one', async () => {
  await game('G');
  await validate('r1', 'f1');
  await validate('r2', 'f2');
  const s = await state({}, {auth: {uid: 'inviter'}});
  assert.deepEqual(s.referralTicketNotice, {referralId: 'r2', gameId: 'G', gameTitle: 'Jeu G', ticketCount: 2});
  assert.equal(s.referralBonusNotice, null);
  assert.deepEqual(await ack({referralId: 'r2'}, {auth: {uid: 'inviter'}}), {acknowledged: false},
    'the bonus kind does not acknowledge a ticket');
  assert.deepEqual(await ack({referralId: 'r2', kind: 'ticket'}, {auth: {uid: 'inviter'}}), {acknowledged: true});
  assert.equal((await state({}, {auth: {uid: 'inviter'}})).referralTicketNotice, null);
  // A new ticket is confirmed again; none once the game is drawn.
  await validate('r3', 'f3');
  assert.equal((await state({}, {auth: {uid: 'inviter'}})).referralTicketNotice.ticketCount, 3);
  await db.doc('referral_games/G').update({draw_status: 'completed', winner_uid: 'inviter'});
  assert.equal((await state({}, {auth: {uid: 'inviter'}})).referralTicketNotice, null);
});
