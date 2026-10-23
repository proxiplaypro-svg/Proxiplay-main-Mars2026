// Publication rule shared by participation, the app and the Admin: stale
// draft flags must not stop a launched game, while real drafts, cancelled
// and admin-hidden games stay unplayable. Isolated emulator only.
const {test, assert, db, time, game, participate, instant} = require('./lifecycle_helpers.cjs');
const {gamePublicationState} = require('../game_publication');

const draftFlags = {visible_public: false, status: 'brouillon'};
const launched = {...draftFlags, unique_players_count: 262, participations: 1198};
const participations = async id => (await db.doc('games/' + id).get()).data().participations;

// The same table drives the Dart and Admin tests: the three implementations
// must agree on every case.
test('rule matches the shared case table used by the app and the Admin', () => {
  const cases = require('../../../test/fixtures/game_publication_cases.json');
  for (const c of cases) assert.equal(gamePublicationState(c.game).state, c.state, c.name);
});

test('rule: published, legacy, draft, launched, disabled and hidden states', () => {
  assert.equal(gamePublicationState({visible_public: true, status: 'actif'}).state, 'published');
  assert.equal(gamePublicationState({}).state, 'published');
  assert.equal(gamePublicationState({...draftFlags, participations: 0}).state, 'draft');
  assert.equal(gamePublicationState({visible_public: true, status: 'brouillon'}).state, 'draft');
  assert.equal(gamePublicationState({visible_public: false, unique_players_count: 3, participations: 9}).state, 'draft');
  assert.equal(gamePublicationState({visible_public: false, participations: 19}).state, 'draft');
  assert.equal(gamePublicationState(launched).state, 'published_inconsistent');
  assert.equal(gamePublicationState({visible_public: false, participations: 20}).state, 'published_inconsistent');
  for (const status of ['cancelled', 'canceled', 'disabled', 'desactive', 'annulé', 'supprime']) {
    assert.equal(gamePublicationState({visible_public: true, status, unique_players_count: 500}).state, 'disabled', status);
  }
  assert.equal(gamePublicationState({deleted: true}).state, 'disabled');
  assert.equal(gamePublicationState({visible_public: false, visible_public_auto_published: true,
    unique_players_count: 500}).state, 'hidden');
});

test('a published game and a legacy game without visibility fields are playable', async () => {
  await game('published', {visible_public: true, status: 'actif'});
  await participate('published');
  assert.equal(await participations('published'), 1);
  await game('legacy');
  await db.doc('games/legacy').update({status: require('firebase-admin').firestore.FieldValue.delete()});
  await participate('legacy');
  assert.equal(await participations('legacy'), 1);
});

test('a real draft never launched, or with a few test plays, is not playable', async () => {
  await game('draft', {...draftFlags, participations: 0});
  await assert.rejects(participate('draft'), e => e.code === 'failed-precondition' && /pas encore disponible/.test(e.message));
  assert.equal(await participations('draft'), 0);
  await game('tested', {visible_public: false, unique_players_count: 3, participations: 9});
  await assert.rejects(participate('tested'), {code: 'failed-precondition'});
  assert.equal(await participations('tested'), 9);
});

test('a launched game with stale draft flags keeps running and keeps its won lots', async () => {
  await game('croquettes', launched);
  // A lot already won before: its instant winner and prize must not change.
  await instant('croquettes', 'won', '2026-09-02T10:00:00Z');
  await db.doc('games/croquettes/instant_winners/won').update({hasWinner: true, player_id: db.doc('users/other')});
  await db.doc('prizes/already_won').set({game_id: db.doc('games/croquettes'), prize_type: 'secondaire',
    winner_id: db.doc('users/other'), claimed: true, claim_code: 'KEEPME12'});
  await participate('croquettes');
  assert.equal(await participations('croquettes'), 1199);
  const game_ = (await db.doc('games/croquettes').get()).data();
  assert.equal(game_.status, 'brouillon', 'no silent status change');
  assert.equal(game_.visible_public, false, 'no silent publication');
  assert.equal((await db.doc('games/croquettes/instant_winners/won').get()).data().player_id.path, 'users/other');
  assert.deepEqual((await db.doc('prizes/already_won').get()).data().claim_code, 'KEEPME12');
});

test('deactivated, cancelled and admin-hidden games are not playable despite their players', async () => {
  for (const [id, fields] of Object.entries({
    deactivated: {visible_public: false, status: 'desactive', unique_players_count: 300},
    cancelled: {visible_public: true, status: 'cancelled', unique_players_count: 300},
    hidden: {visible_public: false, visible_public_auto_published: true, unique_players_count: 300},
  })) {
    await game(id, {...fields, participations: 500});
    await assert.rejects(participate(id), {code: 'failed-precondition'}, id);
    assert.equal(await participations(id), 500, id);
  }
});

test('an ended game, even launched, accepts no new participation', async () => {
  await game('ended', {...launched, end_date: time('2026-09-05T10:00:00Z')});
  await assert.rejects(participate('ended'));
  assert.equal(await participations('ended'), 1198);
});
