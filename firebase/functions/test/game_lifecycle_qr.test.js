const {test, assert, db, ft, game, instant, participate, verifyPrize, time, client, assertFails} = require('./lifecycle_helpers.cjs');
const {drawMainPrize} = require('../main_prize_draw');
const issue = ft.wrap(require('../game_qr_access').issueGameQrAccess);
const mint = (id = 'game', uid = 'merchant', extra = {}) => issue({gameId: id, ...extra}, {auth: {uid}});
test('server QR completes instant and final lifecycle; concurrent retry awards once', async () => {
  await game('game', {access_mode: 'qr_only'}); await instant();
  const {token} = await mint(); assert.equal((await mint()).token, token);
  const [won, retry] = await Promise.all([1,2].map(() => participate('game', 'player', {qr_token: token})));
  assert.equal(won.isWin, true); assert.equal(retry.prize_id, won.prize_id);
  await verifyPrize(won.prize_id.split('/').at(-1));
  await verifyPrize((await drawMainPrize('game', {now: time('2026-10-01')})).prizeId);
  assert.equal((await db.collection('prizes').get()).size, 2);
});
test('missing QR, forged boolean/token and another game capability are refused', async () => {
  await game('game', {access_mode: 'qr_only'}); await instant(); await game('othergame', {access_mode: 'qr_only'});
  for (const input of [{}, {from_qr: true}, {qr_token: 'a'.repeat(64)}, {qr_token: (await mint('othergame')).token}])
    await assert.rejects(participate('game', 'player', input), {code: 'failed-precondition'});
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 30);
  assert.equal((await db.collection('prizes').get()).size, 0);
});
test('server game configuration alone decides whether a QR participation consumes a chance', async () => {
  // A non-QR game always consumes, even if a client/admin accidentally puts
  // the QR-only flag on it.
  await game('classic_with_part', {qr_consumes_participation: false});
  await db.doc('users/player').update({remaining_part: 3});
  await participate('classic_with_part', 'player', {qr_consumes_participation: false});
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 2);
  await game('classic_without_part');
  await db.doc('users/player').update({remaining_part: 0});
  await assert.rejects(participate('classic_without_part'), {code: 'failed-precondition'});

  // Explicitly-free QR games work at zero credits and leave an existing
  // balance untouched. Client input cannot turn a paid QR game into a free one.
  await game('free_qr_with_part', {access_mode: 'qr_only', qr_consumes_participation: false});
  await db.doc('users/player').update({remaining_part: 3});
  let token = (await mint('free_qr_with_part')).token;
  await participate('free_qr_with_part', 'player', {qr_token: token, qr_consumes_participation: true});
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 3);
  await game('free_qr_without_part', {access_mode: 'qr_only', qr_consumes_participation: false});
  await db.doc('users/player').update({remaining_part: 0});
  token = (await mint('free_qr_without_part')).token;
  await participate('free_qr_without_part', 'player', {qr_token: token});
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 0);

  await game('paid_qr_with_part', {access_mode: 'qr_only', qr_consumes_participation: true});
  await db.doc('users/player').update({remaining_part: 3});
  token = (await mint('paid_qr_with_part')).token;
  await participate('paid_qr_with_part', 'player', {qr_token: token, qr_consumes_participation: false});
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 2);
  await game('paid_qr_without_part', {access_mode: 'qr_only', qr_consumes_participation: true});
  await db.doc('users/player').update({remaining_part: 0});
  token = (await mint('paid_qr_without_part')).token;
  await assert.rejects(participate('paid_qr_without_part', 'player', {qr_token: token}), {code: 'failed-precondition'});

  // Missing field is the historical, paid behavior.
  await game('historic_qr', {access_mode: 'qr_only'});
  await db.doc('users/player').update({remaining_part: 3});
  token = (await mint('historic_qr')).token;
  await participate('historic_qr', 'player', {qr_token: token});
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 2);
});
test('free QR preserves instant prizes and the tenth-play +3 bonus', async () => {
  await game('free_qr_bonus', {
    access_mode: 'qr_only', qr_consumes_participation: false,
    participations: 9,
  });
  await instant('free_qr_bonus');
  await db.doc('users/player').update({remaining_part: 0});
  const token = (await mint('free_qr_bonus')).token;
  const result = await participate('free_qr_bonus', 'player', {qr_token: token});
  assert.equal(result.isWin, true);
  assert.match(result.messageBonus, /3 parties/);
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 3);
  assert.equal((await db.collection('prizes').get()).size, 1);
});
test('unlimited access remains free for a paid QR game at zero credits', async () => {
  await game('paid_qr_unlimited', {access_mode: 'qr_only', qr_consumes_participation: true});
  await db.doc('users/player').update({remaining_part: 0, allGamesAccessUntil: time('2026-10-01')});
  const token = (await mint('paid_qr_unlimited')).token;
  await participate('paid_qr_unlimited', 'player', {qr_token: token});
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 0);
});
test('QR issuance is restricted and private; admin-created game belongs to merchant', async () => {
  await game('game', {access_mode: 'qr_only'});
  for (const uid of ['other','player']) await assert.rejects(mint('game', uid), {code: 'permission-denied'});
  await assert.rejects(issue({gameId: 'game'}, {}), {code: 'unauthenticated'}); await mint();
  await assertFails(client('player').doc('game_qr_access/game').get());
  await assertFails(client('merchant').doc('game_qr_access/game').get());
  await assertFails(client('merchant').doc('game_qr_access/game').set({token: 'forged'}));
});
test('expired, revoked, moved-game QR and suspended player fail without a gain', async () => {
  await game('game', {access_mode: 'qr_only'}); await instant();
  const old = await mint(); const current = await mint('game', 'merchant', {rotate: true});
  await assert.rejects(participate('game', 'player', {qr_token: old.token}), {code: 'failed-precondition'});
  await db.doc('game_qr_access/game').update({expires_at: time('2020-01-01')});
  await assert.rejects(participate('game', 'player', {qr_token: current.token}), {code: 'failed-precondition'});
  const valid = await mint(); await db.doc('users/player').update({account_status: 'suspended'});
  await assert.rejects(participate('game', 'player', {qr_token: valid.token}), {code: 'failed-precondition'});
  await db.doc('users/player').update({account_status: 'active'});
  await db.doc('games/game').update({enseigne_id: db.doc('enseignes/elsewhere')});
  await assert.rejects(participate('game', 'player', {qr_token: valid.token}), {code: 'failed-precondition'});
  await db.doc('games/game').update({enseigne_id: db.doc('enseignes/shop'), end_date: time('2020-01-01')});
  await assert.rejects(participate('game', 'player', {qr_token: valid.token}), {code: 'failed-precondition'});
  assert.equal((await db.collection('prizes').get()).size, 0);
});
