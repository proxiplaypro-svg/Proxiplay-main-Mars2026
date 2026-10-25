// Shop QR play of a public game (1.1.2, decided 25/10/2026): one classic
// play (costs a chance) plus at most one free QR play per player, game and
// day, in either order; each is one final-draw ticket. QR-only games keep a
// single daily play. Emulator only.
const {test, assert, db, ft, game, instant, participate, time} = require('./lifecycle_helpers.cjs');
const {drawMainPrize} = require('../main_prize_draw');
const issue = ft.wrap(require('../game_qr_access').issueGameQrAccess);
const mint = async (id = 'game', extra = {}) => (await issue({gameId: id, ...extra}, {auth: {uid: 'merchant'}})).token;
const balance = async () => (await db.doc('users/player').get()).data().remaining_part;
const tickets = async (id = 'game') =>
  (await db.collection(`games/${id}/participants`).get()).docs.map(d => ({id: d.id, ...d.data()}));
const counters = async (id = 'game') => {
  const g = (await db.doc('games/' + id).get()).data();
  return {participations: g.participations, qr: g.qr_participations || 0};
};
let attempts = 0;
const attempt = () => 'attempt_' + (++attempts);
const classic = (id = 'game', extra = {}) =>
  participate(id, 'player', {participation_mode: 'classic', attemptId: attempt(), ...extra});
const shop = (token, id = 'game', extra = {}) =>
  participate(id, 'player', {participation_mode: 'qr', from_qr: true, qr_token: token, attemptId: attempt(), ...extra});

test('classic then shop: two plays, one chance, two tickets; a rescan gives nothing more', async () => {
  await game(); const token = await mint();
  await db.doc('users/player').update({remaining_part: 3});
  assert.equal((await classic()).alreadyParticipatedToday, false);
  assert.equal(await balance(), 2);
  const free = await shop(token);
  assert.equal(free.alreadyParticipatedToday, false);
  assert.equal(free.shopPlay, true);
  assert.equal(await balance(), 2, 'the shop play is free');
  assert.deepEqual((await tickets()).map(t => t.source).sort(), ['classic', 'qr']);
  assert.deepEqual(await counters(), {participations: 2, qr: 1});
  // A second scan: refused as a shop play, and never a paid classic play.
  const rescan = await shop(token);
  assert.equal(rescan.alreadyParticipatedToday, true);
  assert.equal(rescan.shopPlayAlreadyUsed, true);
  // The classic play is used too.
  assert.equal((await classic()).alreadyParticipatedToday, true);
  assert.equal(await balance(), 2);
  assert.equal((await tickets()).length, 2);
  assert.deepEqual(await counters(), {participations: 2, qr: 1});
});

test('shop then classic: the classic play stays available and still costs its chance', async () => {
  await game(); const token = await mint();
  await db.doc('users/player').update({remaining_part: 0});
  await shop(token);
  assert.equal(await balance(), 0, 'free even at zero chances');
  await assert.rejects(classic(), {code: 'failed-precondition', message: /plus de parties/});
  await db.doc('users/player').update({remaining_part: 1});
  assert.equal((await classic()).alreadyParticipatedToday, false);
  assert.equal(await balance(), 0);
  assert.equal((await tickets()).length, 2);
  const detail = (await db.doc('games/game/participants_details/player').get()).data();
  assert.ok(detail.last_shop_play && detail.last_classic_play && detail.last_play);
});

test('the next day both plays are available again', async () => {
  await game(); const token = await mint();
  await classic(); await shop(token);
  process.env.LIFECYCLE_TEST_NOW = '2026-09-10T10:00:00Z';
  assert.equal((await shop(token)).alreadyParticipatedToday, false);
  assert.equal((await classic()).alreadyParticipatedToday, false);
  assert.equal((await tickets()).length, 4);
});

test('concurrent scans give one shop play, one ticket, at most one prize, no debit', async () => {
  await game(); await instant(); const token = await mint();
  await db.doc('users/player').update({remaining_part: 0});
  const results = await Promise.all([1, 2, 3, 4].map(() => shop(token)));
  assert.equal(results.filter(r => r.alreadyParticipatedToday === false).length, 1);
  assert.equal((await tickets()).length, 1);
  assert.ok(new Set(results.filter(r => r.isWin).map(r => r.prize_id)).size <= 1);
  assert.ok((await db.collection('prizes').get()).size <= 1);
  assert.deepEqual(await counters(), {participations: 1, qr: 1});
  assert.equal(await balance(), 0);
});

test('a shop play and a classic play sent together both count once', async () => {
  await game(); const token = await mint();
  await db.doc('users/player').update({remaining_part: 3});
  await Promise.all([shop(token), classic(), shop(token), classic()]);
  assert.deepEqual((await tickets()).map(t => t.source).sort(), ['classic', 'qr']);
  assert.equal(await balance(), 2);
  assert.deepEqual(await counters(), {participations: 2, qr: 1});
});

test('a retried attempt replays its result and never debits a chance', async () => {
  await game(); await instant(); const token = await mint();
  await db.doc('users/player').update({remaining_part: 1});
  const first = await shop(token, 'game', {attemptId: 'lost_answer'});
  assert.equal(first.isWin, true);
  // Same attempt again, even sent as a classic play (the app saw the shop
  // play as used meanwhile): the shop result comes back, nothing is played.
  for (const mode of ['qr', 'classic']) {
    const again = await participate('game', 'player',
      {participation_mode: mode, qr_token: token, attemptId: 'lost_answer'});
    assert.equal(again.alreadyParticipatedToday, true, mode);
    assert.equal(again.prize_id, first.prize_id, mode);
    assert.equal(again.shopPlay, true, mode);
  }
  assert.equal(await balance(), 1);
  assert.equal((await tickets()).length, 1);
  // A retried classic attempt replays the classic result.
  const paid = await classic('game', {attemptId: 'lost_classic'});
  const paidAgain = await classic('game', {attemptId: 'lost_classic'});
  assert.equal(paidAgain.alreadyParticipatedToday, true);
  assert.equal(paidAgain.message, paid.message);
  assert.equal(await balance(), 0);
  assert.equal((await db.collection('prizes').get()).size, 1);
});

test('an invalid, expired, revoked or missing token never gives the free play nor debits', async () => {
  await game(); await game('othergame');
  const other = await mint('othergame');
  const revoked = await mint(); const current = await mint('game', {rotate: true});
  await db.doc('users/player').update({remaining_part: 3});
  for (const token of [undefined, null, 'a'.repeat(64), 'not-a-token', other, revoked]) {
    await assert.rejects(shop(token), (error) =>
      error.code === 'failed-precondition' && error.details?.reason === 'invalid_shop_qr');
  }
  await db.doc('game_qr_access/game').update({expires_at: time('2020-01-01')});
  await assert.rejects(shop(current), {code: 'failed-precondition'});
  assert.equal(await balance(), 3);
  assert.equal((await tickets()).length, 0);
  // A classic play ignores any token: paid, classic ticket.
  await db.doc('game_qr_access/game').update({expires_at: time('2030-01-01')});
  await classic('game', {qr_token: current});
  assert.equal(await balance(), 2);
  assert.deepEqual((await tickets()).map(t => t.source), ['classic']);
});

test('apps before 1.1.2 (no mode): a valid scan is the shop play, an invalid one a paid play', async () => {
  await game(); const token = await mint();
  await db.doc('users/player').update({remaining_part: 3});
  await participate('game', 'player', {from_qr: true});
  await participate('game', 'player', {from_qr: true, qr_token: token});
  assert.equal(await balance(), 2);
  assert.deepEqual((await tickets()).map(t => t.source).sort(), ['classic', 'qr']);
  await game('public_invalid');
  await participate('public_invalid', 'player', {from_qr: true, qr_token: 'a'.repeat(64)});
  assert.equal(await balance(), 1);
});

test('an older record with only last_play today still counts as the classic play', async () => {
  await game(); const token = await mint();
  await db.doc('games/game/participants_details/player').set({
    last_play: time('2026-09-09T08:00:00Z'), game_bonus: 0, user_id: db.doc('users/player')});
  await db.doc('users/player').update({remaining_part: 3});
  assert.equal((await classic()).alreadyParticipatedToday, true);
  assert.equal((await shop(token)).alreadyParticipatedToday, false);
  assert.equal((await classic()).alreadyParticipatedToday, true, 'still the same day');
  assert.equal(await balance(), 3);
});

test('QR-only games keep a single daily play', async () => {
  await game('qr_game', {access_mode: 'qr_only'}); const token = await mint('qr_game');
  await db.doc('users/player').update({remaining_part: 0});
  assert.equal((await shop(token, 'qr_game')).alreadyParticipatedToday, false);
  assert.equal((await shop(token, 'qr_game')).alreadyParticipatedToday, true);
  await assert.rejects(classic('qr_game'), {code: 'failed-precondition'});
  const all = await tickets('qr_game');
  assert.equal(all.length, 1);
  assert.equal(all[0].source, 'qr');
  assert.deepEqual(await counters('qr_game'), {participations: 1, qr: 1});
});

test('the shop play keeps instant prizes and the tenth-play +3 bonus', async () => {
  await game('game', {participations: 9}); await instant(); const token = await mint();
  await db.doc('users/player').update({remaining_part: 0});
  const result = await shop(token);
  assert.equal(result.isWin, true);
  assert.match(result.messageBonus, /3 parties/);
  assert.equal(await balance(), 3);
});

test('a shop ticket takes part in the final draw like a classic one', async () => {
  await game(); const token = await mint();
  await shop(token);
  const draw = await drawMainPrize('game', {now: time('2026-10-01')});
  const prize = (await db.doc('prizes/' + draw.prizeId).get()).data();
  assert.equal(prize.winner_id.path, 'users/player');
});

test('tickets never carry the shop token', async () => {
  await game(); const token = await mint();
  await shop(token); await classic();
  for (const t of await tickets()) assert.ok(!JSON.stringify(t).includes(token));
  const detail = (await db.doc('games/game/participants_details/player').get()).data();
  assert.ok(!JSON.stringify(detail).includes(token));
});
