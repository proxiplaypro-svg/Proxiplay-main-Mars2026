// "Moteur C" applique a drawReferralGame(): Phase 1 (hors transaction) /
// Phase 2 (selection pure) / Phase 3 (transaction finale courte). Avant
// cette restructuration, la boucle "for (const entryDoc of
// entriesSnap.docs) { await transaction.get(userRef) }" lisait un parrain
// a la fois A L'INTERIEUR de la transaction (introduit par b1fdda3,
// 22/08/2026) -- le meme motif que l'incident Kids Troc sur le tirage
// principal. Ce fichier prouve que l'operation count de la transaction
// finale reste CONSTANTE de 10 a 3000 tickets, et que la ponderation par
// ticket (un parrain avec plusieurs filleuls a plus de chances) est
// preservee exactement.
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-referral-phase-engine';
process.env.FUNCTIONS_EMULATOR = 'true';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const admin = require('firebase-admin');
const { Transaction } = require('@google-cloud/firestore');
const ft = require('firebase-functions-test')();
admin.initializeApp();
const {
  drawReferralGame,
  loadEligibleReferralTickets,
  REFERRAL_MAX_CANDIDATE_ATTEMPTS,
} = require('../referral_game_engine');
const db = admin.firestore();
test.after(() => ft.cleanup());

test.beforeEach(async () => {
  for (const col of await db.listCollections()) await db.recursiveDelete(col);
});

async function seedGame(overrides = {}) {
  await db.doc('referral_games/g').set({
    status: 'active', title: 'Jeu de parrainage', prize_value: 20,
    end_date: admin.firestore.Timestamp.fromDate(new Date('2020-01-01')),
    ...overrides,
  });
}

async function seedTickets(count, {prefix = 'u'} = {}) {
  const CHUNK = 200;
  for (let start = 0; start < count; start += CHUNK) {
    const batch = db.batch();
    const end = Math.min(start + CHUNK, count);
    for (let i = start; i < end; i += 1) {
      const uid = `${prefix}${String(i).padStart(4, '0')}`;
      batch.set(db.doc(`users/${uid}`), {user_role: 'joueur', first_name: `Player${i}`});
      batch.set(db.doc(`referral_games/g/entries/t${String(i).padStart(4, '0')}`), {inviter_uid: uid});
    }
    // eslint-disable-next-line no-await-in-loop
    await batch.commit();
  }
}

function countTransactionOps(fn) {
  let count = 0;
  const originalGet = Transaction.prototype.get;
  const originalGetAll = Transaction.prototype.getAll;
  Transaction.prototype.get = function (...args) { count += 1; return originalGet.apply(this, args); };
  Transaction.prototype.getAll = function (...args) { count += 1; return originalGetAll.apply(this, args); };
  return fn().finally(() => {
    Transaction.prototype.get = originalGet;
    Transaction.prototype.getAll = originalGetAll;
  }).then(result => ({result, count}));
}

// ---------------------------------------------------------------------
// Scale: transaction op count constant across 10 / 1500 / 3000 tickets.
// ---------------------------------------------------------------------
for (const n of [10, 1500, 3000]) {
  test(`Phase 3 transaction stays O(1): ${n} tickets`, async () => {
    await seedGame();
    await seedTickets(n);
    const {result, count} = await countTransactionOps(() => drawReferralGame('g'));
    assert.equal(result.status, 'completed');
    assert.ok(count <= 7, `expected <=7 ops inside the transaction for ${n} tickets, got ${count}`);
  });
}

test('Phase 3 op count for 10 and 3000 tickets is IDENTICAL', async () => {
  await seedGame();
  await seedTickets(10);
  const small = await countTransactionOps(() => drawReferralGame('g'));
  assert.equal(small.result.status, 'completed');

  for (const col of await db.listCollections()) await db.recursiveDelete(col);
  await seedGame();
  await seedTickets(3000);
  const large = await countTransactionOps(() => drawReferralGame('g'));
  assert.equal(large.result.status, 'completed');

  assert.equal(small.count, large.count, 'transaction op count must not depend on ticket count');
});

// ---------------------------------------------------------------------
// Tirage normal + comparaison champ-par-champ des ecritures.
// ---------------------------------------------------------------------
test('tirage normal: toutes les ecritures metier attendues sont presentes', async () => {
  await seedGame();
  await seedTickets(5);
  const result = await drawReferralGame('g');
  assert.equal(result.status, 'completed');

  const game = (await db.doc('referral_games/g').get()).data();
  assert.equal(game.status, 'ended');
  assert.equal(game.draw_status, 'completed');
  assert.equal(typeof game.winner_uid, 'string');
  assert.ok(game.winner_ref);
  assert.equal(game.total_ticket_count, 5);
  assert.equal(game.eligible_ticket_count, 5);
  assert.ok(game.drawn_at);
  assert.ok(game.prize_ref);

  const prize = (await db.doc('prizes/referral_game_g').get()).data();
  assert.ok(prize);
  assert.equal(prize.prize_type, 'referral_game');
  assert.equal(prize.fulfillment_type, 'platform');
  assert.equal(prize.referral_game_id, 'g');
  assert.equal(prize.winner_id.path, game.winner_ref.path);
  assert.equal(typeof prize.claim_code, 'string');
  assert.equal(prize.claimed, false);
  assert.equal(prize.prize_value, 20);

  const myLots = await db.collection(`users/${game.winner_uid}/my_lots`).get();
  assert.equal(myLots.size, 1);
  assert.equal(myLots.docs[0].id, 'referral_game_g');

  const wonEntries = await db.collection('referral_games/g/entries').where('eligibility_status', '==', 'won').get();
  assert.equal(wonEntries.size, 1);
  assert.equal(wonEntries.docs[0].data().inviter_uid, game.winner_uid);
});

// ---------------------------------------------------------------------
// Zero participant / zero eligible.
// ---------------------------------------------------------------------
test('zero ticket: no_eligible_entries, pas de prize', async () => {
  await seedGame();
  const result = await drawReferralGame('g');
  assert.equal(result.status, 'no_eligible_entries');
  assert.equal(result.winnerUid, '');
  const game = (await db.doc('referral_games/g').get()).data();
  assert.equal(game.draw_status, 'no_eligible_entries');
  assert.equal((await db.collection('prizes').get()).size, 0);
});

test('zero ticket eligible: tous les parrains exclus -> no_eligible_entries', async () => {
  await seedGame();
  await db.doc('users/banned').set({account_status: 'suspended'});
  await db.doc('referral_games/g/entries/t1').set({inviter_uid: 'banned'});
  const result = await drawReferralGame('g');
  assert.equal(result.status, 'no_eligible_entries');
  assert.equal((await db.collection('prizes').get()).size, 0);
  const entry = (await db.doc('referral_games/g/entries/t1').get()).data();
  assert.equal(entry.eligibility_status, 'excluded');
});

// ---------------------------------------------------------------------
// Ponderation par ticket : un parrain avec 3 tickets vs un avec 1 doit
// apparaitre 3x plus souvent dans le pool eligible.
// ---------------------------------------------------------------------
test('loadEligibleReferralTickets preserve la ponderation par ticket (un element par ticket, pas par parrain)', async () => {
  await db.doc('users/heavy').set({user_role: 'joueur'});
  await db.doc('users/light').set({user_role: 'joueur'});
  const entryDocs = [
    {ref: {path: 'referral_games/g/entries/t1'}, data: () => ({inviter_uid: 'heavy'})},
    {ref: {path: 'referral_games/g/entries/t2'}, data: () => ({inviter_uid: 'heavy'})},
    {ref: {path: 'referral_games/g/entries/t3'}, data: () => ({inviter_uid: 'heavy'})},
    {ref: {path: 'referral_games/g/entries/t4'}, data: () => ({inviter_uid: 'light'})},
  ];
  const {eligible} = await loadEligibleReferralTickets(db, entryDocs);
  assert.equal(eligible.length, 4, 'un element par ticket, pas par parrain unique');
  assert.equal(eligible.filter((t) => t.inviter_uid === 'heavy').length, 3);
  assert.equal(eligible.filter((t) => t.inviter_uid === 'light').length, 1);
});

// ---------------------------------------------------------------------
// Candidat (ticket gagnant) devenu inexclu entre Phase 1 et Phase 3.
// ---------------------------------------------------------------------
test('parrain banni entre Phase 1 et Phase 3 est ecarte (avec tous ses tickets); un autre gagne', async () => {
  await seedGame();
  await db.doc('users/a').set({user_role: 'joueur', first_name: 'Alice'});
  await db.doc('users/b').set({user_role: 'joueur', first_name: 'Bob'});
  // 'a' detient 2 tickets, 'b' en detient 1 -- si 'a' est banni, ses DEUX
  // tickets doivent disparaitre du pool local en un coup, pas un par un.
  await db.doc('referral_games/g/entries/t1').set({inviter_uid: 'a'});
  await db.doc('referral_games/g/entries/t2').set({inviter_uid: 'a'});
  await db.doc('referral_games/g/entries/t3').set({inviter_uid: 'b'});

  const originalRandomInt = crypto.randomInt;
  crypto.randomInt = () => 0;
  const originalRunTransaction = db.runTransaction.bind(db);
  let patched = false;
  db.runTransaction = async function (updateFunction) {
    if (!patched) {
      patched = true;
      await db.doc('users/a').update({account_status: 'suspended'});
    }
    return originalRunTransaction(updateFunction);
  };

  let result;
  try {
    result = await drawReferralGame('g');
  } finally {
    crypto.randomInt = originalRandomInt;
    db.runTransaction = originalRunTransaction;
  }

  assert.equal(result.status, 'completed');
  assert.equal(result.winnerUid, 'b', 'le parrain banni ne doit jamais gagner');
});

// ---------------------------------------------------------------------
// Retry-budget-exceeded.
// ---------------------------------------------------------------------
test('plus de REFERRAL_MAX_CANDIDATE_ATTEMPTS parrains bannis avec des non-testes restants -> retry_needed', async () => {
  await seedGame();
  const TOTAL = REFERRAL_MAX_CANDIDATE_ATTEMPTS + 5;
  for (let i = 0; i < TOTAL; i += 1) {
    const uid = `u${String(i).padStart(3, '0')}`;
    await db.doc(`users/${uid}`).set({user_role: 'joueur'});
    await db.doc(`referral_games/g/entries/t${String(i).padStart(3, '0')}`).set({inviter_uid: uid});
  }
  const entriesSnap = await db.collection('referral_games/g/entries').get();
  const orderedUids = entriesSnap.docs.map((d) => d.data().inviter_uid);
  const toBan = orderedUids.slice(0, REFERRAL_MAX_CANDIDATE_ATTEMPTS);

  const originalRandomInt = crypto.randomInt;
  crypto.randomInt = () => 0;
  const originalRunTransaction = db.runTransaction.bind(db);
  let patched = false;
  db.runTransaction = async function (updateFunction) {
    if (!patched) {
      patched = true;
      const batch = db.batch();
      for (const uid of toBan) batch.update(db.doc(`users/${uid}`), {account_status: 'suspended'});
      await batch.commit();
    }
    return originalRunTransaction(updateFunction);
  };

  let result;
  try {
    result = await drawReferralGame('g');
  } finally {
    crypto.randomInt = originalRandomInt;
    db.runTransaction = originalRunTransaction;
  }

  assert.equal(result.status, 'retry_needed');
  const game = (await db.doc('referral_games/g').get()).data();
  assert.notEqual(game.draw_status, 'no_eligible_entries');
  assert.equal((await db.collection('prizes').get()).size, 0);

  const second = await drawReferralGame('g');
  assert.equal(second.status, 'completed');
});

// ---------------------------------------------------------------------
// Concurrence.
// ---------------------------------------------------------------------
test('deux executions concurrentes: exactement un gagnant, aucune duplication', async () => {
  await seedGame();
  await seedTickets(50);
  const [r1, r2] = await Promise.all([drawReferralGame('g'), drawReferralGame('g')]);
  const statuses = [r1.status, r2.status].sort();
  assert.deepEqual(statuses, ['already_finalized', 'completed']);
  assert.equal((await db.collection('prizes').get()).size, 1);
});

// ---------------------------------------------------------------------
// Jeu deja tire.
// ---------------------------------------------------------------------
test('jeu deja finalise: already_finalized, aucune nouvelle ecriture', async () => {
  await seedGame();
  await seedTickets(3);
  const first = await drawReferralGame('g');
  assert.equal(first.status, 'completed');
  const second = await drawReferralGame('g');
  assert.equal(second.status, 'already_finalized');
  assert.equal(second.winnerUid, first.winnerUid);
  assert.equal((await db.collection('prizes').get()).size, 1);
});

// ---------------------------------------------------------------------
// Pas encore a echeance : ce moteur VERIFIE lui-meme end_date (a la
// difference des animations) -- throw attendu.
// ---------------------------------------------------------------------
test('jeu pas encore a echeance: rejette (throw), sauf avec allowEarly', async () => {
  await seedGame({end_date: admin.firestore.Timestamp.fromDate(new Date('2099-01-01'))});
  await assert.rejects(() => drawReferralGame('g'), /has not ended yet/);
  await seedTickets(2);
  const result = await drawReferralGame('g', {allowEarly: true});
  assert.equal(result.status, 'completed');
});

// ---------------------------------------------------------------------
// Donnees legacy : status 'ended' (pas 'active') reste valide.
// ---------------------------------------------------------------------
test("jeu avec status 'ended' (legacy, deja cloture cote inscriptions) reste tirable", async () => {
  await seedGame({status: 'ended'});
  await seedTickets(3);
  const result = await drawReferralGame('g');
  assert.equal(result.status, 'completed');
});

// ---------------------------------------------------------------------
// Regle propre au parrainage : recompenses en attente bloquent le tirage.
// ---------------------------------------------------------------------
test('recompenses de parrainage non resolues: manual_review_required, aucune ecriture', async () => {
  await seedGame();
  await seedTickets(3);
  await db.collection('referral_reward_pending').add({game_id: 'g', status: 'pending'});
  const result = await drawReferralGame('g');
  assert.equal(result.status, 'manual_review_required');
  assert.equal(result.reason, 'unresolved_referral_rewards');
  assert.equal((await db.collection('prizes').get()).size, 0);
  const game = (await db.doc('referral_games/g').get()).data();
  assert.notEqual(game.draw_status, 'completed');
});
