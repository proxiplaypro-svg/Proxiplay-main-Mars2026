// End-to-end coverage for behavior #4 asked in review: a merchant-created
// game is born visible_public:false (draft), is neither visible nor
// playable, then becomes playable only once generateInstantWinnersForGame
// publishes it server-side (publishOnSuccess:true, the same call the real
// app makes in add_game_commercant_page_widget.dart). The existing
// game_lifecycle_instant.test.js suite only exercises generateInstantWinnersForGame
// directly and uses the shared `game()` fixture, which never sets
// visible_public at all (legacy shape) -- it never asserts the actual
// draft -> published transition a player experiences.
const {test, assert, db, game, participate, ft, functions} = require('./lifecycle_helpers.cjs');
const admin = require('firebase-admin');

// generateInstantWinnersForGame's publish-eligibility check compares
// end_date against real wall-clock Date.now(), not the mocked
// clock.getEmulatorNowDate() the rest of this suite uses -- so this fixture
// needs a genuinely future end_date, not the helper's fixed 2026-09 default.
const farFutureEnd = admin.firestore.Timestamp.fromDate(
  new Date(Date.now() + 365 * 86400000),
);

test('draft game (visible_public:false) cannot be played, then becomes playable once published server-side', async () => {
  await game('draft_game', {
    visible_public: false,
    hasMainPrize: false,
    end_date: farFutureEnd,
  });

  // Behavior #2 (already covered by participate_visible_public_gate.test.js,
  // reconfirmed here in the exact lifecycle context): unplayable while draft.
  await assert.rejects(
    () => participate('draft_game'),
    (error) => {
      assert.equal(error.code, 'failed-precondition');
      return true;
    },
  );
  assert.equal((await db.doc('games/draft_game').get()).data().visible_public, false);

  const provision = ft.wrap(functions.generateInstantWinnersForGame);
  const result = await provision(
    { gameId: 'draft_game', publishOnSuccess: true },
    { auth: { uid: 'merchant' } },
  );
  assert.equal(result.published, true);

  // Behavior #4: the server flipped it, not the client.
  const published = (await db.doc('games/draft_game').get()).data();
  assert.equal(published.visible_public, true);

  // Now playable with the exact same call that was refused above (the
  // earlier rejected attempt never recorded a participation, so the same
  // player can legitimately try again here).
  const outcome = await participate('draft_game', 'player');
  assert.equal(outcome.alreadyParticipatedToday, false);
});

test('a game that never sets visible_public (legacy shape) is playable immediately, ' +
  'confirming the draft gate only triggers on an explicit false', async () => {
  await game('legacy_game');
  const outcome = await participate('legacy_game');
  assert.equal(outcome.alreadyParticipatedToday, false);
});
