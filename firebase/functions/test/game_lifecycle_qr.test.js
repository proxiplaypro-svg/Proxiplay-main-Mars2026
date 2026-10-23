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
test('a verified shop scan never consumes a chance, for QR-only and public games', async () => {
  const balance = async () => (await db.doc('users/player').get()).data().remaining_part;
  // QR-only games are free whatever the former per-game setting says.
  for (const [id, extra] of [['qr_historic', {}], ['qr_paid_setting', {qr_consumes_participation: true}],
    ['qr_free_setting', {qr_consumes_participation: false}]]) {
    await game(id, {access_mode: 'qr_only', ...extra});
    await db.doc('users/player').update({remaining_part: 3});
    await participate(id, 'player', {qr_token: (await mint(id)).token});
    assert.equal(await balance(), 3, id);
  }
  // A public game scanned in the shop is free, even at zero credits.
  await game('public_scanned', {access_mode: 'public'});
  await db.doc('users/player').update({remaining_part: 0});
  await participate('public_scanned', 'player', {from_qr: true, qr_token: (await mint('public_scanned')).token});
  assert.equal(await balance(), 0);
  // Historical public games (no access_mode) behave the same.
  await game('legacy_scanned');
  await db.doc('users/player').update({remaining_part: 3});
  await participate('legacy_scanned', 'player', {qr_token: (await mint('legacy_scanned')).token});
  assert.equal(await balance(), 3);
});
test('a public game without a verified scan is a normal, paid play', async () => {
  const balance = async () => (await db.doc('users/player').get()).data().remaining_part;
  await game('other_public');
  const otherToken = (await mint('other_public')).token;
  // No token, the client flag alone, a forged token, another game's token,
  // or a client-sent setting: all consume exactly one chance.
  const inputs = [{}, {from_qr: true}, {from_qr: true, qr_token: 'a'.repeat(64)},
    {from_qr: true, qr_token: otherToken}, {qr_token: 'not-a-token'}, {qr_consumes_participation: false}];
  for (const [i, input] of inputs.entries()) {
    await game('public_' + i);
    await db.doc('users/player').update({remaining_part: 3});
    await participate('public_' + i, 'player', input);
    assert.equal(await balance(), 2, JSON.stringify(input));
  }
  // Without a verified scan, zero credits still blocks a public game.
  await game('public_empty');
  await db.doc('users/player').update({remaining_part: 0});
  await assert.rejects(participate('public_empty', 'player', {from_qr: true}), {code: 'failed-precondition'});
  // A rotated (revoked) poster token is no longer a free scan.
  await game('public_rotated');
  const old = (await mint('public_rotated')).token;
  await mint('public_rotated', 'merchant', {rotate: true});
  await db.doc('users/player').update({remaining_part: 3});
  await participate('public_rotated', 'player', {qr_token: old});
  assert.equal(await balance(), 2);
});
test('repeated or concurrent free scans give one play per game and day, never extra chances or prizes', async () => {
  for (const [id, mode] of [['scan_public', 'public'], ['scan_qr_only', 'qr_only']]) {
    await game(id, {access_mode: mode}); await instant(id);
    await db.doc('users/player').update({remaining_part: 0});
    const token = (await mint(id)).token;
    // Three parallel scans plus two late retries, same player, same day.
    const results = await Promise.all([1, 2, 3].map(() => participate(id, 'player', {from_qr: true, qr_token: token})));
    for (let i = 0; i < 2; i++) results.push(await participate(id, 'player', {from_qr: true, qr_token: token}));
    const wins = new Set(results.filter(r => r.isWin).map(r => r.prize_id));
    assert.ok(wins.size <= 1, id + ': at most one prize');
    assert.equal((await db.doc('games/' + id).get()).data().participations, 1, id + ': one participation');
    assert.equal((await db.collection('prizes').where('game_id', '==', db.doc('games/' + id)).get()).size, wins.size, id);
    assert.equal((await db.doc('users/player').get()).data().remaining_part, 0, id + ': no chance credited or debited');
  }
});
test('a shop token opens nothing but its own game participation', async () => {
  await game('game'); await game('othergame');
  const {token} = await mint();
  // Not readable or writable by the player, nor by the merchant from a client.
  await assertFails(client('player').doc('game_qr_access/game').get());
  await assertFails(client('player').collection('game_qr_access').get());
  // A token holder cannot mint, rotate or read a token for any game.
  for (const input of [{gameId: 'game', qr_token: token}, {gameId: 'game', rotate: true, qr_token: token}, {gameId: 'othergame', qr_token: token}])
    await assert.rejects(issue(input, {auth: {uid: 'player'}}), {code: 'permission-denied'});
  // On another game it is ignored: a normal, paid play.
  await db.doc('users/player').update({remaining_part: 3});
  await participate('othergame', 'player', {from_qr: true, qr_token: token});
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 2);
  // The token is never copied into documents the player or others can read.
  const leaked = [];
  for (const col of ['games', 'users', 'prizes']) {
    for (const d of (await db.collection(col).get()).docs) if (JSON.stringify(d.data()).includes(token)) leaked.push(d.ref.path);
  }
  for (const d of (await db.collectionGroup('participants').get()).docs) if (JSON.stringify(d.data()).includes(token)) leaked.push(d.ref.path);
  assert.deepEqual(leaked, []);
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
