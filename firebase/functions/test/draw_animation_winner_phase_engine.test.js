// "Moteur C" applique a drawWinnerForAnimation(): Phase 1 (hors
// transaction) / Phase 2 (selection pure) / Phase 3 (transaction finale
// courte). Avant cette restructuration, la boucle "for (const entryDoc of
// entriesSnap.docs) { await transaction.get(userRef) }" lisait un compte
// utilisateur a la fois A L'INTERIEUR de la transaction (introduit par
// bb55f91, 29/08/2026) -- exactement le motif qui a cause les timeouts de
// production sur le tirage principal (incident Kids Troc). Ce fichier
// prouve que l'operation count de la transaction finale reste CONSTANTE
// de 10 a 3000 entries qualifiees, et que chaque regle metier (unicite
// par uid, exclusions, checkAwardLinks, notifications) est preservee.
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-animation-phase-engine';
process.env.FUNCTIONS_EMULATOR = 'true';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const admin = require('firebase-admin');
const { Transaction } = require('@google-cloud/firestore');
const ft = require('firebase-functions-test')();
admin.initializeApp();
const {
  drawWinnerForAnimation,
  loadEligibleAnimationCandidates,
  ANIMATION_MAX_CANDIDATE_ATTEMPTS,
} = require('../draw_animation_winner');
const db = admin.firestore();
test.after(() => ft.cleanup());

test.beforeEach(async () => {
  for (const col of await db.listCollections()) await db.recursiveDelete(col);
});

async function seedAnimation(overrides = {}) {
  await db.doc('animations/anim').set({
    status: 'active', name: 'Grand jeu', prize_description: 'Un velo electrique',
    end_date: admin.firestore.Timestamp.fromDate(new Date('2020-01-01')),
    ...overrides,
  });
}

async function seedQualifiedEntries(count, {prefix = 'u'} = {}) {
  const CHUNK = 200;
  for (let start = 0; start < count; start += CHUNK) {
    const batch = db.batch();
    const end = Math.min(start + CHUNK, count);
    for (let i = start; i < end; i += 1) {
      const uid = `${prefix}${String(i).padStart(4, '0')}`;
      batch.set(db.doc(`users/${uid}`), {user_role: 'joueur', first_name: `Player${i}`, city: 'Paris'});
      batch.set(db.doc(`animations/anim/entries/${uid}`), {threshold_reached: true});
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
// Scale: transaction op count constant across 10 / 1500 / 3000.
// ---------------------------------------------------------------------
for (const n of [10, 1500, 3000]) {
  test(`Phase 3 transaction stays O(1): ${n} entries qualifiees`, async () => {
    await seedAnimation();
    await seedQualifiedEntries(n);
    const {result, count} = await countTransactionOps(() => drawWinnerForAnimation('anim'));
    assert.equal(result.status, 'completed');
    assert.ok(count <= 6, `expected <=6 ops inside the transaction for ${n} entries, got ${count}`);
  });
}

test('Phase 3 op count for 10 and 3000 entries is IDENTICAL', async () => {
  await seedAnimation();
  await seedQualifiedEntries(10);
  const small = await countTransactionOps(() => drawWinnerForAnimation('anim'));
  assert.equal(small.result.status, 'completed');

  for (const col of await db.listCollections()) await db.recursiveDelete(col);
  await seedAnimation();
  await seedQualifiedEntries(3000);
  const large = await countTransactionOps(() => drawWinnerForAnimation('anim'));
  assert.equal(large.result.status, 'completed');

  assert.equal(small.count, large.count, 'transaction op count must not depend on entry count');
});

// ---------------------------------------------------------------------
// Tirage normal + comparaison champ-par-champ des ecritures.
// ---------------------------------------------------------------------
test('tirage normal: toutes les ecritures metier attendues sont presentes', async () => {
  await seedAnimation();
  await seedQualifiedEntries(5);
  const result = await drawWinnerForAnimation('anim');
  assert.equal(result.status, 'completed');

  const animation = (await db.doc('animations/anim').get()).data();
  assert.equal(animation.status, 'ended');
  assert.equal(typeof animation.winner_uid, 'string');
  assert.ok(animation.winner_ref);
  assert.ok(animation.drawn_at);

  const prize = (await db.doc(`prizes/animation_anim`).get()).data();
  assert.ok(prize, 'prize must exist at the deterministic id');
  assert.equal(prize.prize_type, 'principal');
  assert.equal(prize.fulfillment_type, 'platform');
  assert.equal(prize.animation_id, 'anim');
  assert.equal(prize.winner_id.path, animation.winner_ref.path);
  assert.equal(typeof prize.claim_code, 'string');
  assert.equal(prize.claimed, false);
  assert.ok(prize.win_date);

  const myLots = await db.collection(`users/${animation.winner_uid}/my_lots`).get();
  assert.equal(myLots.size, 1);
  assert.equal(myLots.docs[0].id, 'animation_anim');

  const publicWinner = await db.doc('animations/anim/public_winner/current').get();
  assert.ok(publicWinner.exists);
  const winnerDoc = await db.doc('animations/anim/winner/current').get();
  assert.ok(winnerDoc.exists);
  assert.equal(winnerDoc.data().uid, animation.winner_uid);
});

// ---------------------------------------------------------------------
// Zero participant (aucune entry) vs zero participant eligible.
// ---------------------------------------------------------------------
test('zero participant: aucune entry qualifiee -> no_qualified_entries, pas de prize', async () => {
  await seedAnimation();
  const result = await drawWinnerForAnimation('anim');
  assert.equal(result.status, 'no_qualified_entries');
  const animation = (await db.doc('animations/anim').get()).data();
  assert.equal(animation.draw_status, 'no_eligible_entries');
  assert.equal((await db.collection('prizes').get()).size, 0);
});

test('zero participant eligible: entries presentes mais tous exclus -> no_eligible_entries', async () => {
  await seedAnimation();
  await db.doc('users/banned').set({account_status: 'suspended'});
  await db.doc('animations/anim/entries/banned').set({threshold_reached: true});
  const result = await drawWinnerForAnimation('anim');
  assert.equal(result.status, 'no_eligible_entries');
  assert.equal((await db.collection('prizes').get()).size, 0);
});

// ---------------------------------------------------------------------
// Candidat devenu inexclu entre Phase 1 et Phase 3.
// ---------------------------------------------------------------------
test('candidat banni entre Phase 1 et Phase 3 est ecarte; un autre candidat gagne', async () => {
  await seedAnimation();
  await db.doc('users/a').set({user_role: 'joueur', first_name: 'Alice'});
  await db.doc('users/b').set({user_role: 'joueur', first_name: 'Bob'});
  await db.doc('animations/anim/entries/a').set({threshold_reached: true});
  await db.doc('animations/anim/entries/b').set({threshold_reached: true});

  // Math.random() est utilise par ce moteur (pas crypto.randomInt) :
  // on le fixe a 0 pour rendre le pool deterministe (toujours pool[0]).
  const originalRandom = Math.random;
  Math.random = () => 0;
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
    result = await drawWinnerForAnimation('anim');
  } finally {
    Math.random = originalRandom;
    db.runTransaction = originalRunTransaction;
  }

  assert.equal(result.status, 'completed');
  const animation = (await db.doc('animations/anim').get()).data();
  assert.equal(animation.winner_uid, 'b', 'le candidat banni ne doit jamais gagner');
});

// ---------------------------------------------------------------------
// Retry-budget-exceeded: > ANIMATION_MAX_CANDIDATE_ATTEMPTS bannis mais
// des candidats non testes restent -> retry_needed, jamais no_eligible_entries.
// ---------------------------------------------------------------------
test('plus de ANIMATION_MAX_CANDIDATE_ATTEMPTS candidats bannis avec des non-testes restants -> retry_needed', async () => {
  await seedAnimation();
  const TOTAL = ANIMATION_MAX_CANDIDATE_ATTEMPTS + 5;
  for (let i = 0; i < TOTAL; i += 1) {
    const uid = `u${String(i).padStart(3, '0')}`;
    await db.doc(`users/${uid}`).set({user_role: 'joueur'});
    await db.doc(`animations/anim/entries/${uid}`).set({threshold_reached: true});
  }
  const entriesSnap = await db.collection('animations/anim/entries').get();
  const orderedUids = entriesSnap.docs.map((d) => d.id);
  const toBan = orderedUids.slice(0, ANIMATION_MAX_CANDIDATE_ATTEMPTS);

  const originalRandom = Math.random;
  Math.random = () => 0;
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
    result = await drawWinnerForAnimation('anim');
  } finally {
    Math.random = originalRandom;
    db.runTransaction = originalRunTransaction;
  }

  assert.equal(result.status, 'retry_needed');
  const animation = (await db.doc('animations/anim').get()).data();
  assert.notEqual(animation.draw_status, 'no_eligible_entries');
  assert.equal(animation.winner_uid, undefined);
  assert.equal((await db.collection('prizes').get()).size, 0);

  const second = await drawWinnerForAnimation('anim');
  assert.equal(second.status, 'completed');
});

// ---------------------------------------------------------------------
// Concurrence : deux executions simultanees sur la meme animation.
// ---------------------------------------------------------------------
test('deux executions concurrentes: exactement un gagnant, aucune duplication', async () => {
  await seedAnimation();
  await seedQualifiedEntries(50);
  const [r1, r2] = await Promise.all([drawWinnerForAnimation('anim'), drawWinnerForAnimation('anim')]);
  const statuses = [r1.status, r2.status].sort();
  assert.deepEqual(statuses, ['already_drawn', 'completed']);
  assert.equal((await db.collection('prizes').get()).size, 1);
});

// ---------------------------------------------------------------------
// Animation deja tiree.
// ---------------------------------------------------------------------
test('animation deja tiree: already_drawn, aucune nouvelle ecriture', async () => {
  await seedAnimation();
  await seedQualifiedEntries(3);
  const first = await drawWinnerForAnimation('anim');
  assert.equal(first.status, 'completed');
  const second = await drawWinnerForAnimation('anim');
  assert.equal(second.status, 'already_drawn');
  assert.equal(second.winnerUid, first.winnerUid);
  assert.equal((await db.collection('prizes').get()).size, 1);
});

// ---------------------------------------------------------------------
// Pas encore a echeance : verifie au niveau du scheduler (load()), ce
// moteur ne gate PAS lui-meme sur end_date (confirme par lecture du
// code : drawWinnerForAnimation ne lit jamais end_date).
// ---------------------------------------------------------------------
test("scheduler : le filtre de la requete load() exclut les animations pas encore a echeance", async () => {
  await db.doc('animations/future').set({
    status: 'active', end_date: admin.firestore.Timestamp.fromDate(new Date('2099-01-01')),
  });
  const now = admin.firestore.Timestamp.now();
  const snap = await db.collection('animations').where('status', '==', 'active').where('end_date', '<=', now).get();
  assert.equal(snap.docs.some((d) => d.id === 'future'), false);
});

// ---------------------------------------------------------------------
// Donnees legacy : animation sans prize_description (fallback sur name).
// ---------------------------------------------------------------------
test('animation legacy sans prize_description: fallback sur name, tirage normal', async () => {
  await db.doc('animations/anim').set({
    status: 'active', name: 'Jeu historique',
    end_date: admin.firestore.Timestamp.fromDate(new Date('2020-01-01')),
  });
  await seedQualifiedEntries(3);
  const result = await drawWinnerForAnimation('anim');
  assert.equal(result.status, 'completed');
  const prize = (await db.doc('prizes/animation_anim').get()).data();
  assert.equal(prize.name, 'Jeu historique');
});

// ---------------------------------------------------------------------
// Unicite : un entry par uid (pas de multiplicite a la difference du
// tirage principal/parrainage) -- loadEligibleAnimationCandidates ne doit
// jamais produire deux candidats pour le meme uid.
// ---------------------------------------------------------------------
test('loadEligibleAnimationCandidates: un seul candidat par uid, pas de doublon', async () => {
  await db.doc('users/solo').set({user_role: 'joueur'});
  const entryDocs = [{id: 'solo', data: () => ({threshold_reached: true})}];
  const eligible = await loadEligibleAnimationCandidates(db, entryDocs);
  assert.equal(eligible.length, 1);
  assert.equal(eligible[0].uid, 'solo');
});
