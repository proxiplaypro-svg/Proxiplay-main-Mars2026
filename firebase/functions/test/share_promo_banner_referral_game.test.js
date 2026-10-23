// The Home "invite a friend, play every game until midnight" bar is hidden
// while a referral game runs: a referral then gives a draw ticket instead.
// Isolated demo emulator only.
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST || !String(process.env.GCLOUD_PROJECT || '').startsWith('demo-')) {
  throw Error('Isolated demo emulator required');
}
if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const ft = require('firebase-functions-test')({projectId: process.env.GCLOUD_PROJECT});
const state = ft.wrap(require('../lib/share_promo').getSharePromoState);
test.after(() => ft.cleanup());
const at = ms => admin.firestore.Timestamp.fromMillis(ms);
const hour = 3600000;

async function reset(remainingPart) {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  await db.doc('app_config/share_promo').set({enabled: true, isDraft: false, kind: 'defaultInvite',
    title: 'Inviter un ami', message: 'Jouez à tous les jeux jusqu’à minuit', ctaText: 'Inviter un ami',
    rewardType: 'all_games_until_midnight', rewardValue: 1});
  await db.doc('users/player').set({user_role: 'joueur', remaining_part: remainingPart});
}
const player = {auth: {uid: 'player'}};

test('a player without chances sees the invite bar when no referral game runs', async () => {
  await reset(0);
  const result = await state({}, player);
  assert.equal(result.showBanner, true);
  assert.equal(result.kind, 'lowRemainingPlaysInvite');
});

test('the invite bar is hidden while a referral game runs', async () => {
  await reset(0);
  const now = Date.now();
  await db.doc('referral_games/live').set({status: 'active', start_date: at(now - hour), end_date: at(now + hour)});
  assert.equal((await state({}, player)).showBanner, false);
  await db.doc('users/player').update({remaining_part: 3});
  assert.equal((await state({}, player)).showBanner, false);
});

test('a draft, future, finished or ended referral game does not hide the bar', async () => {
  const now = Date.now();
  for (const game of [
    {status: 'draft', start_date: at(now - hour), end_date: at(now + hour)},
    {status: 'active', start_date: at(now + hour), end_date: at(now + 2 * hour)},
    {status: 'active', start_date: at(now - 2 * hour), end_date: at(now - hour)},
    {status: 'ended', start_date: at(now - hour), end_date: at(now + hour)},
  ]) {
    await reset(0);
    await db.doc('referral_games/g').set(game);
    assert.equal((await state({}, player)).showBanner, true, JSON.stringify(game.status));
  }
});

test('invitations and state carry the ticket wording only while a referral game runs', async () => {
  const create = ft.wrap(require('../lib/share_promo').createReferral);
  await reset(0);
  let invitation = await create({shareChannel: 'test'}, player);
  assert.equal(invitation.referralGameActive, false);
  assert.doesNotMatch(invitation.shareMessage, /ticket/);
  const now = Date.now();
  await db.doc('referral_games/live').set({status: 'active', start_date: at(now - hour), end_date: at(now + hour)});
  invitation = await create({shareChannel: 'test'}, player);
  assert.equal(invitation.referralGameActive, true);
  assert.match(invitation.shareMessage, new RegExp(invitation.inviteCode));
  assert.match(invitation.shareMessage, /c’est moi qui gagne un ticket pour le tirage au sort/);
  assert.doesNotMatch(invitation.shareMessage, /minuit/);
  const current = await state({}, player);
  assert.equal(current.referralGameActive, true);
  assert.equal(current.message, 'Invitez un ami et gagnez un ticket pour le tirage au sort !');
  assert.equal(current.showBanner, false);
});
