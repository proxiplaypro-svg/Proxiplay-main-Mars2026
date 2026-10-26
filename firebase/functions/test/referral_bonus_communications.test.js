// Referral bonus communications (26/10/2026): in-app congratulation shown
// once per granted bonus while it lasts, congratulation e-mail sent once to
// the inviter, push opening the player home. Disposable demo emulator only.
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
const grant = ft.wrap(share.grantReferralReward);
const state = ft.wrap(share.getSharePromoState);
const ack = ft.wrap(share.acknowledgeReferralBonusNotice);
const {getNextMidnightTimestamp} = require('../lib/share_promo/firestore');
const {processReferralBonusEmail, kReferralBonusEmailText} = require('../referral_bonus_email');
const t = value => admin.firestore.Timestamp.fromDate(new Date(value));
const asAdmin = {auth: {uid: 'admin', token: {admin: true}}};
const asInviter = {auth: {uid: 'inviter'}};

async function acceptedReferral(id, invitee, acceptedAt = admin.firestore.Timestamp.now()) {
  await db.doc(`referrals/${id}`).set({inviterUid: 'inviter', inviteeUid: invitee,
    inviteCode: 'CODE' + id, status: 'accepted', rewardStatus: 'available',
    rewardType: 'all_games_until_midnight', rewardValue: 1, acceptedAt,
    metadata: {playerRewardRuleVersion: 2}, createdAt: acceptedAt});
}

test.beforeEach(async () => {
  for (const collection of await db.listCollections()) await db.recursiveDelete(collection);
  await db.doc('app_config/share_promo').set({enabled: true, isDraft: false,
    rewardType: 'all_games_until_midnight', rewardValue: 1,
    maxRewardsPerUser: 20, maxRewardsPerInvitee: 3, requireInviteeSignup: true});
  await Promise.all([
    db.doc('users/inviter').set({user_role: 'joueur', remaining_part: 3, email: 'Parrain@Example.fr'}),
    db.doc('users/invitee').set({user_role: 'joueur', email: 'filleul@example.fr'}),
    db.doc('users/invitee2').set({user_role: 'joueur', email: 'filleul2@example.fr'}),
    db.doc('users/admin').set({user_role: 'admin'}),
  ]);
});
test.after(() => ft.cleanup());

test('a granted bonus is announced once in the app, on every device of the account', async () => {
  await acceptedReferral('r1', 'invitee');
  assert.equal((await grant({referralId: 'r1'}, asAdmin)).granted, true);
  const deadline = getNextMidnightTimestamp(admin.firestore.Timestamp.now()).toMillis();
  const first = await state({}, asInviter);
  assert.deepEqual(first.referralBonusNotice, {referralId: 'r1', expiresAtMs: deadline});
  // A second device asks before the first acknowledges: same notice.
  assert.equal((await state({}, asInviter)).referralBonusNotice.referralId, 'r1');
  assert.deepEqual(await ack({referralId: 'r1'}, asInviter), {acknowledged: true});
  assert.deepEqual(await ack({referralId: 'r1'}, asInviter), {acknowledged: true}, 'idempotent');
  assert.equal((await state({}, asInviter)).referralBonusNotice, null, 'never shown again');
  // The invitee is never congratulated nor rewarded.
  assert.equal((await state({}, {auth: {uid: 'invitee'}})).referralBonusNotice, null);
  assert.equal((await db.doc('users/invitee').get()).data().allGamesAccessUntil, undefined);
  // The push opens the player home.
  const push = (await db.doc('ff_push_notifications/share_promo_reward_r1').get()).data();
  assert.equal(push.initial_page_name, 'HomeJoueurPage');
  assert.equal(push.user_refs, 'users/inviter');
});

test('a new bonus is announced again; an unknown or old one cannot be acknowledged', async () => {
  await acceptedReferral('r1', 'invitee');
  await grant({referralId: 'r1'}, asAdmin);
  await ack({referralId: 'r1'}, asInviter);
  await acceptedReferral('r2', 'invitee2');
  await grant({referralId: 'r2'}, asAdmin);
  assert.equal((await state({}, asInviter)).referralBonusNotice.referralId, 'r2');
  assert.deepEqual(await ack({referralId: 'r1'}, asInviter), {acknowledged: false});
  assert.deepEqual(await ack({referralId: 'nope'}, asInviter), {acknowledged: false});
  assert.equal((await state({}, asInviter)).referralBonusNotice.referralId, 'r2');
  await assert.rejects(ack({referralId: ''}, asInviter), {code: 'invalid-argument'});
  await assert.rejects(ack({referralId: 'r2'}, {}), {code: 'unauthenticated'});
});

test('an expired bonus is never announced (app, push nor e-mail)', async () => {
  await acceptedReferral('old', 'invitee', t('2026-03-29T20:30:00Z'));
  await grant({referralId: 'old'}, asAdmin);
  assert.equal((await state({}, asInviter)).referralBonusNotice, null);
  assert.equal((await db.doc('ff_push_notifications/share_promo_reward_old').get()).exists, false);
  const sent = [];
  const result = await processReferralBonusEmail(db, 'old', {send: async (...a) => sent.push(a)});
  assert.deepEqual(result, {status: 'skipped', reason: 'bonus_expired'});
  assert.equal(sent.length, 0);
});

test('the notice follows the access actually read by participation', () => {
  const now = Date.parse('2026-10-26T12:00:00Z');
  const notice = {referralId: 'r', expiresAt: t('2026-10-26T23:00:00Z')};
  assert.equal(share.pendingReferralBonusNotice({referralBonusNotice: notice}, t('2026-10-26T23:00:00Z'), now).referralId, 'r');
  assert.equal(share.pendingReferralBonusNotice({referralBonusNotice: notice}, t('2026-10-26T11:00:00Z'), now), null,
    'access already over');
  assert.equal(share.pendingReferralBonusNotice({referralBonusNotice: notice}, undefined, now), null);
  assert.equal(share.pendingReferralBonusNotice({referralBonusNotice: notice, referralBonusNoticeSeenId: 'r'},
    t('2026-10-26T23:00:00Z'), now), null);
  assert.equal(share.pendingReferralBonusNotice({}, t('2026-10-26T23:00:00Z'), now), null);
});

test('the e-mail goes once to the inviter, also when triggered twice at once', async () => {
  await acceptedReferral('r1', 'invitee');
  await grant({referralId: 'r1'}, asAdmin);
  const sent = [];
  const send = async (to, subject, text) => { sent.push({to, subject, text}); };
  const results = await Promise.all([1, 2, 3].map(() => processReferralBonusEmail(db, 'r1', {send})));
  assert.equal(results.filter(r => r.status === 'sent').length, 1);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to, 'parrain@example.fr');
  assert.equal(sent[0].subject, '🎉 Bravo, ton parrainage a fonctionné !');
  assert.equal(sent[0].text, kReferralBonusEmailText);
  assert.match(sent[0].text, /jouer à tous les jeux jusqu'à minuit/);
  assert.equal((await processReferralBonusEmail(db, 'r1', {send})).status, 'already_sent');
  assert.equal(sent.length, 1);
  assert.equal((await db.doc('reward_events/r1').get()).data().email_status, 'sent');
});

test('an SMTP failure is recorded, never resent, and leaves the bonus as granted', async () => {
  await acceptedReferral('r1', 'invitee');
  await grant({referralId: 'r1'}, asAdmin);
  const before = (await db.doc('users/inviter').get()).data().allGamesAccessUntil.toMillis();
  const failing = async () => { const e = new Error('Connection timeout'); e.code = 'ETIMEDOUT'; throw e; };
  assert.deepEqual(await processReferralBonusEmail(db, 'r1', {send: failing}), {status: 'failed', reason: 'ETIMEDOUT'});
  const sent = [];
  assert.equal((await processReferralBonusEmail(db, 'r1', {send: async (...a) => sent.push(a)})).status, 'already_failed');
  assert.equal(sent.length, 0);
  const event = (await db.doc('reward_events/r1').get()).data();
  assert.equal(event.email_status, 'failed');
  assert.equal(event.email_reason, 'ETIMEDOUT');
  assert.equal((await db.doc('users/inviter').get()).data().allGamesAccessUntil.toMillis(), before);
  assert.equal((await db.doc('referrals/r1').get()).data().rewardStatus, 'granted');
  assert.equal((await db.collection('reward_events').get()).size, 1);
  // Granting again does nothing either.
  assert.equal((await grant({referralId: 'r1'}, asAdmin)).granted, false);
});

test('recipient guards: no address, excluded or non-player inviter, foreign event', async () => {
  const sent = [];
  const send = async (...a) => sent.push(a);
  for (const [id, patch, reason] of [
    ['a', {email: 'not-an-address'}, 'no_valid_email'],
    ['b', {account_status: 'suspended'}, 'inviter_ineligible'],
    ['c', {user_role: 'commercant'}, 'not_a_player'],
  ]) {
    await db.doc('users/inviter').set({user_role: 'joueur', email: 'parrain@example.fr', ...patch});
    await db.doc(`reward_events/${id}`).set({uid: 'inviter', referralId: id, type: 'all_games_until_midnight'});
    await acceptedReferral(id, 'invitee');
    await db.doc(`referrals/${id}`).update({rewardStatus: 'granted'});
    await db.doc('users/inviter').update({allGamesAccessUntil: t('2030-01-01T00:00:00Z')});
    assert.deepEqual(await processReferralBonusEmail(db, id, {send}), {status: 'skipped', reason}, id);
  }
  // An event that does not match its referral's inviter sends nothing.
  await db.doc('users/inviter').set({user_role: 'joueur', email: 'parrain@example.fr',
    allGamesAccessUntil: t('2030-01-01T00:00:00Z')});
  await db.doc('reward_events/x').set({uid: 'invitee', referralId: 'x', type: 'all_games_until_midnight'});
  await acceptedReferral('x', 'invitee2');
  await db.doc('referrals/x').update({rewardStatus: 'granted'});
  assert.deepEqual(await processReferralBonusEmail(db, 'x', {send}), {status: 'skipped', reason: 'referral_mismatch'});
  await db.doc('reward_events/y').set({uid: 'inviter', referralId: 'y', type: 'play_credit'});
  assert.deepEqual(await processReferralBonusEmail(db, 'y', {send}), {status: 'skipped', reason: 'not_all_games_bonus'});
  assert.equal(sent.length, 0);
});
