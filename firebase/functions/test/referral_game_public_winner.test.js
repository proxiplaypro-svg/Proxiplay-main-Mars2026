// Gagnant public du jeu du parrainage (1.1.4) : le tirage et sa reparation
// ecrivent public_prize_winners/referral_game_<id> (prenom et ville
// seulement), lu par l'app. Emulateurs uniquement (lifecycle_helpers.cjs).
const {test, assert, db, time} = require('./lifecycle_helpers.cjs');
const {drawReferralGame, repairReferralGameDraw} = require('../referral_game_engine');

const afterEnd = {now: time('2026-10-01')};

async function endedGame(id = 'ref_game') {
  await db.doc(`referral_games/${id}`).set({
    status: 'active', title: 'Jeu du parrainage', prize_description: 'Bon cadeau 50 €',
    start_date: time('2026-09-01'), end_date: time('2026-09-30'),
  });
  await db.doc(`referral_games/${id}/entries/ref1`).set({
    inviter_uid: 'player', referral_id: 'ref1', inviter_ref: db.doc('users/player'),
  });
}

test('le tirage publie le prenom et la ville du gagnant, rien d autre', async () => {
  await db.doc('users/player').update({first_name: 'camille Martin', last_name: 'Martin',
    city: 'Dunkerque', email: 'camille@example.test', phone_number: '0600000000'});
  await endedGame();
  const result = await drawReferralGame('ref_game', afterEnd);
  assert.equal(result.status, 'completed');
  const projection = (await db.doc('public_prize_winners/referral_game_ref_game').get()).data();
  assert.equal(projection.winnerFirstName, 'camille');
  assert.equal(projection.winnerCity, 'Dunkerque');
  assert.equal(projection.name, 'Bon cadeau 50 €');
  const serialized = JSON.stringify(projection);
  for (const secret of ['Martin', 'camille@example.test', '0600000000', 'player']) {
    assert.ok(!serialized.includes(secret), secret);
  }
});

test('un prenom qui ressemble a une adresse n est jamais publie', async () => {
  await db.doc('users/player').update({first_name: 'camille@example.test', city: ''});
  await endedGame();
  await drawReferralGame('ref_game', afterEnd);
  const projection = (await db.doc('public_prize_winners/referral_game_ref_game').get()).data();
  assert.equal(projection.winnerFirstName, 'Un joueur');
  assert.equal(projection.winnerCity, '');
});

test('la reparation publie le gagnant d un jeu tire avant la 1.1.4', async () => {
  await db.doc('users/player').update({first_name: 'Lea', city: 'Lille'});
  await endedGame();
  await drawReferralGame('ref_game', afterEnd);
  await db.doc('public_prize_winners/referral_game_ref_game').delete();
  const repaired = await repairReferralGameDraw('ref_game');
  assert.equal(repaired.status, 'repaired_my_lots');
  const projection = (await db.doc('public_prize_winners/referral_game_ref_game').get()).data();
  assert.equal(projection.winnerFirstName, 'Lea');
  assert.equal(projection.winnerCity, 'Lille');
});

test('aucun participant eligible : aucun gagnant public', async () => {
  await db.doc('referral_games/empty').set({status: 'active', start_date: time('2026-09-01'),
    end_date: time('2026-09-30')});
  const result = await drawReferralGame('empty', afterEnd);
  assert.equal(result.status, 'no_eligible_entries');
  assert.equal((await db.doc('public_prize_winners/referral_game_empty').get()).exists, false);
});
