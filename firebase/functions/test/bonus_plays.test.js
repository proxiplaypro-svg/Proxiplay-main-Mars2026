// Reserve de parties bonus (1.1.4), contre les emulateurs uniquement
// (lifecycle_helpers.cjs). Regles : 3 parties du jour remises a 3 a minuit,
// bonus jamais effaces, parties du jour consommees d'abord, bonus cumulables
// sans plafond ni expiration, eligibilite des jeux inchangee.
const {test, assert, admin, db, ft, functions, time, game, participate, client,
  assertFails, assertSucceeds} = require('./lifecycle_helpers.cjs');
const {planPlayConsumption, normalizeBonusPart} = require('../play_balance');
const {grantBirthdayReward} = require('../lib/notifications/runners/birthday_runner');
const {applyRewardToUser} = require('../lib/share_promo/firestore');

const resetAtMidnight = ft.wrap(functions.resetDailyRemainingParts);

async function setBalance(daily, bonus, extra = {}) {
  await db.doc('users/player').set({remaining_part: daily, bonus_part: bonus, ...extra}, {merge: true});
}

async function balance(uid = 'player') {
  const data = (await db.doc(`users/${uid}`).get()).data();
  return {daily: data.remaining_part, bonus: data.bonus_part};
}

test('ordre de consommation : parties du jour, puis bonus, puis refus', () => {
  const plan = (daily, bonus, extra = {}) => planPlayConsumption({
    dailyRemaining: daily, bonusRemaining: bonus, consumesPlay: true, unlimited: false, ...extra});
  assert.deepEqual(plan(3, 5), {allowed: true, source: 'daily', dailyDelta: -1, bonusDelta: 0});
  assert.deepEqual(plan(0, 5), {allowed: true, source: 'bonus', dailyDelta: 0, bonusDelta: -1});
  assert.deepEqual(plan(0, 0), {allowed: false, source: 'none', dailyDelta: 0, bonusDelta: 0});
  assert.equal(plan(0, 0, {unlimited: true}).source, 'unlimited');
  assert.equal(plan(0, 0, {consumesPlay: false}).source, 'free');
  assert.equal(plan(0, 2, {unlimited: true}).bonusDelta, 0);
  for (const value of [undefined, null, -4, 'x', NaN]) assert.equal(normalizeBonusPart(value), 0);
  assert.equal(normalizeBonusPart(2.9), 2);
});

test('les parties du jour sont consommees avant les bonus', async () => {
  await setBalance(2, 4);
  await game();
  const result = await participate();
  assert.equal(result.playSource, 'daily');
  assert.deepEqual(await balance(), {daily: 1, bonus: 4});
  assert.equal(result.remainingPart, 1);
  assert.equal(result.bonusPart, 4);
});

test('parties du jour epuisees : une partie bonus est utilisee', async () => {
  await setBalance(0, 2);
  await game();
  const result = await participate();
  assert.equal(result.playSource, 'bonus');
  assert.deepEqual(await balance(), {daily: 0, bonus: 1});
});

test('ni partie du jour ni bonus : refus, rien n est ecrit', async () => {
  await setBalance(0, 0);
  await game();
  await assert.rejects(participate(), (error) => error.code === 'failed-precondition' &&
    /plus de parties disponibles/.test(error.message));
  assert.deepEqual(await balance(), {daily: 0, bonus: 0});
  assert.equal((await db.collection('games/game/participants').get()).size, 0);
});

test('acces tous les jeux jusqu a minuit : distinct, ne consomme ni jour ni bonus', async () => {
  await setBalance(0, 2, {allGamesAccessUntil: time('2026-09-09T21:59:59Z')});
  await game();
  const result = await participate();
  assert.equal(result.playSource, 'unlimited');
  assert.deepEqual(await balance(), {daily: 0, bonus: 2});
});

test('passage a minuit : 3 parties du jour, bonus intacts, commercants non touches', async () => {
  await setBalance(0, 7);
  await db.doc('users/second').set({user_role: 'joueur', remaining_part: 2});
  await db.doc('users/rich').set({user_role: 'joueur', remaining_part: 5, bonus_part: 1000});
  await resetAtMidnight({});
  assert.deepEqual(await balance('player'), {daily: 3, bonus: 7});
  assert.deepEqual(await balance('second'), {daily: 3, bonus: undefined});
  assert.deepEqual(await balance('rich'), {daily: 3, bonus: 1000});
  assert.equal((await db.doc('users/merchant').get()).data().remaining_part, 30);
});

test('bonus de la 10e participation : verse dans la reserve et cumulable', async () => {
  await setBalance(3, 5);
  await game('game', {participations: 9, hasMainPrize: false});
  const result = await participate();
  assert.match(result.messageBonus, /3 parties bonus/);
  assert.match(result.messageBonus, /conservées/);
  assert.deepEqual(await balance(), {daily: 2, bonus: 8});
});

test('bonus de la 10e participation obtenu avec une partie bonus : -1 puis +3', async () => {
  await setBalance(0, 1);
  await game('game', {participations: 19, hasMainPrize: false});
  const result = await participate();
  assert.equal(result.playSource, 'bonus');
  assert.deepEqual(await balance(), {daily: 0, bonus: 3});
});

test('cumul sans plafond : anniversaire, participation et parrainage s additionnent', async () => {
  await setBalance(3, 1000);
  await grantBirthdayReward({firestore: db, admin, automationId: 'birthday', userId: 'player',
    userRef: db.doc('users/player'), birthdayDateKey: '2026-09-09',
    rewardConfig: {type: 'birthday_play_credit', value: 3, grantedBy: 'birthday'}});
  assert.deepEqual(await balance(), {daily: 3, bonus: 1003});
  await db.runTransaction((tx) => applyRewardToUser(tx, 'player', 'play_credit', 2));
  assert.deepEqual(await balance(), {daily: 3, bonus: 1005});
  // Referral "all games until midnight" stays an access window, never bonus plays.
  await db.runTransaction((tx) => applyRewardToUser(tx, 'player', 'all_games_until_midnight', 1));
  const user = (await db.doc('users/player').get()).data();
  assert.equal(user.bonus_part, 1005);
  assert.ok(user.allGamesAccessUntil);
  await resetAtMidnight({});
  assert.deepEqual(await balance(), {daily: 3, bonus: 1005});
});

test('participations simultanees : une seule partie bonus disponible, un seul jeu passe', async () => {
  await setBalance(0, 1);
  await game('g1');
  await game('g2');
  await game('g3');
  const results = await Promise.allSettled(['g1', 'g2', 'g3'].map((id) => participate(id)));
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  for (const rejected of results.filter((r) => r.status === 'rejected')) {
    assert.equal(rejected.reason.code, 'failed-precondition');
  }
  assert.deepEqual(await balance(), {daily: 0, bonus: 0});
});

test('participations simultanees : 1 partie du jour + 1 bonus pour 3 jeux, jamais negatif', async () => {
  await setBalance(1, 1);
  for (const id of ['g1', 'g2', 'g3']) await game(id);
  const results = await Promise.allSettled(['g1', 'g2', 'g3'].map((id) => participate(id)));
  const sources = results.filter((r) => r.status === 'fulfilled').map((r) => r.value.playSource).sort();
  assert.deepEqual(sources, ['bonus', 'daily']);
  assert.deepEqual(await balance(), {daily: 0, bonus: 0});
});

test('eligibilite inchangee : deja joue aujourd hui, le bonus n ouvre pas une 2e partie', async () => {
  await setBalance(1, 5);
  await game();
  await participate();
  const again = await participate();
  assert.equal(again.alreadyParticipatedToday, true);
  assert.deepEqual(await balance(), {daily: 0, bonus: 5});
});

test('regles : le joueur ne peut jamais ecrire sa reserve bonus', async () => {
  await setBalance(3, 2);
  const db1 = client('player');
  await assertFails(db1.doc('users/player').update({bonus_part: 50}));
  await assertFails(db1.doc('users/player').update({bonus_part_updated_at: new Date()}));
  await assertSucceeds(db1.doc('users/player').update({city: 'Lille'}));
  await assertFails(client('newbie').doc('users/newbie').set({uid: 'newbie', user_role: 'joueur', bonus_part: 9}));
  await assertSucceeds(client('newbie2').doc('users/newbie2').set({uid: 'newbie2', user_role: 'joueur'}));
});
