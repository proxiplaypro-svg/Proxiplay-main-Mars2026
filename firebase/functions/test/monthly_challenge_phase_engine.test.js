// "Moteur C" applique a drawWinnerForMonthlyChallenge(): Phase 1 (hors
// transaction) / Phase 2 (selection pure) / Phase 3 (transaction finale
// courte). Avant cette restructuration, la boucle "for (const entryDoc of
// entriesSnap.docs) { await transaction.get(userRef) }" lisait un
// participant qualifie a la fois A L'INTERIEUR de la transaction -- code
// original du tout premier commit de ce fichier (dc64459, 19/08/2026),
// jamais touche depuis, y compris lors du correctif du tirage principal.
// Ce fichier prouve que l'operation count de la transaction finale reste
// CONSTANTE de 10 a 3000 entrees qualifiees.
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-monthly-challenge-phase-engine';
process.env.FUNCTIONS_EMULATOR = 'true';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const admin = require('firebase-admin');
const { Transaction } = require('@google-cloud/firestore');
const ft = require('firebase-functions-test')();
admin.initializeApp();
const {
  drawWinnerForMonthlyChallenge,
  loadEligibleMonthlyChallengeEntries: _unused, // not exported under this exact name if absent; see below
} = (() => { try { return require('../monthly_challenge'); } catch (e) { throw e; } })();
const mc = require('../monthly_challenge');
const db = admin.firestore();
test.after(() => ft.cleanup());

test.beforeEach(async () => {
  for (const col of await db.listCollections()) await db.recursiveDelete(col);
});

const MONTH = '2026-08';
const CHALLENGE_ID = MONTH; // getChallengeId('attendance', MONTH) === MONTH

function buildConfig(overrides = {}) {
  return {
    enabled: true,
    month: MONTH,
    type: 'attendance',
    target_days: 15,
    title: 'Defi du mois',
    prize_title: "Bon d'achat",
    prize_value: 50,
    draw_date: admin.firestore.Timestamp.fromDate(new Date('2026-09-01')),
    ...overrides,
  };
}

async function seedQualifiedEntries(count, {prefix = 'u'} = {}) {
  const CHUNK = 200;
  for (let start = 0; start < count; start += CHUNK) {
    const batch = db.batch();
    const end = Math.min(start + CHUNK, count);
    for (let i = start; i < end; i += 1) {
      const uid = `${prefix}${String(i).padStart(4, '0')}`;
      batch.set(db.doc(`users/${uid}`), {user_role: 'joueur', first_name: `Player${i}`, city: 'Paris'});
      batch.set(db.doc(`monthly_challenge_entries/${CHALLENGE_ID}_${uid}`), {
        uid, month: MONTH, challenge_id: CHALLENGE_ID, type: 'attendance',
        user_ref: db.doc(`users/${uid}`), status: 'qualified',
      });
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
  test(`Phase 3 transaction stays O(1): ${n} entrees qualifiees`, async () => {
    await seedQualifiedEntries(n);
    const {result, count} = await countTransactionOps(() => mc.drawWinnerForMonthlyChallenge(buildConfig(), 'test'));
    assert.equal(result.status, 'completed');
    assert.ok(count <= 10, `expected <=10 ops inside the transaction for ${n} entries, got ${count}`);
  });
}

test('Phase 3 op count for 10 and 3000 entrees is IDENTICAL', async () => {
  await seedQualifiedEntries(10);
  const small = await countTransactionOps(() => mc.drawWinnerForMonthlyChallenge(buildConfig(), 'test'));
  assert.equal(small.result.status, 'completed');

  for (const col of await db.listCollections()) await db.recursiveDelete(col);
  await seedQualifiedEntries(3000);
  const large = await countTransactionOps(() => mc.drawWinnerForMonthlyChallenge(buildConfig(), 'test'));
  assert.equal(large.result.status, 'completed');

  assert.equal(small.count, large.count, 'transaction op count must not depend on entry count');
});

// ---------------------------------------------------------------------
// Tirage normal + comparaison champ-par-champ des ecritures.
// ---------------------------------------------------------------------
test('tirage normal: toutes les ecritures metier attendues sont presentes', async () => {
  await seedQualifiedEntries(5);
  const result = await mc.drawWinnerForMonthlyChallenge(buildConfig(), 'test');
  assert.equal(result.status, 'completed');

  const draw = (await db.doc(`monthly_challenge_draws/${CHALLENGE_ID}`).get()).data();
  assert.equal(draw.status, 'completed');
  assert.equal(typeof draw.winner_uid, 'string');
  assert.ok(draw.winner_ref);
  assert.equal(draw.eligible_count, 5);
  assert.ok(draw.drawn_at);
  assert.ok(draw.prize_ref);

  const prize = (await db.doc(`prizes/monthly_challenge_${CHALLENGE_ID}`).get()).data();
  assert.ok(prize);
  assert.equal(prize.prize_type, 'monthly_challenge');
  assert.equal(prize.fulfillment_type, 'platform');
  assert.equal(prize.winner_id.path, draw.winner_ref.path);
  assert.equal(typeof prize.claim_code, 'string');
  assert.equal(prize.claimed, false);
  assert.equal(prize.prize_value, 50);
  assert.equal(prize.monthly_challenge_month, MONTH);
  assert.equal(prize.monthly_challenge_id, CHALLENGE_ID);

  const myLots = await db.collection(`users/${draw.winner_uid}/my_lots`).get();
  assert.equal(myLots.size, 1);
  assert.equal(myLots.docs[0].id, `monthly_challenge_${CHALLENGE_ID}`);

  const wonEntry = (await db.doc(`monthly_challenge_entries/${CHALLENGE_ID}_${draw.winner_uid}`).get()).data();
  assert.equal(wonEntry.status, 'won');

  const winnerState = (await db.doc(`users/${draw.winner_uid}/monthly_challenges/${CHALLENGE_ID}`).get()).data();
  assert.equal(winnerState.winner, true);
});

// ---------------------------------------------------------------------
// Zero participant / zero eligible.
// ---------------------------------------------------------------------
test('zero entree qualifiee: no_eligible_users, pas de prize', async () => {
  const result = await mc.drawWinnerForMonthlyChallenge(buildConfig(), 'test');
  assert.equal(result.status, 'no_eligible_users');
  assert.equal((await db.collection('prizes').get()).size, 0);
});

test('entrees qualifiees mais tous exclus: no_eligible_users, entrees marquees', async () => {
  await db.doc('users/banned').set({account_status: 'suspended'});
  await db.doc(`monthly_challenge_entries/${CHALLENGE_ID}_banned`).set({
    uid: 'banned', month: MONTH, challenge_id: CHALLENGE_ID, user_ref: db.doc('users/banned'), status: 'qualified',
  });
  const result = await mc.drawWinnerForMonthlyChallenge(buildConfig(), 'test');
  assert.equal(result.status, 'no_eligible_users');
  const entry = (await db.doc(`monthly_challenge_entries/${CHALLENGE_ID}_banned`).get()).data();
  assert.equal(entry.status, 'excluded_account_status');
  assert.equal((await db.collection('prizes').get()).size, 0);
});

// ---------------------------------------------------------------------
// Unicite : un entry par uid (pas de ponderation dans ce moteur).
// ---------------------------------------------------------------------
test('loadEligibleMonthlyChallengeEntries: un seul candidat par utilisateur qualifie', async () => {
  await db.doc('users/solo').set({user_role: 'joueur'});
  const entryDoc = {
    ref: {path: `monthly_challenge_entries/${CHALLENGE_ID}_solo`},
    data: () => ({challenge_id: CHALLENGE_ID, month: MONTH, user_ref: db.doc('users/solo')}),
  };
  const evaluated = await mc.loadEligibleMonthlyChallengeEntries(db, [entryDoc], CHALLENGE_ID);
  assert.equal(evaluated.length, 1);
  assert.equal(evaluated[0].exclusionStatus, undefined);
});

// ---------------------------------------------------------------------
// Candidat devenu inexclu entre Phase 1 et Phase 3.
// ---------------------------------------------------------------------
test('candidat banni entre Phase 1 et Phase 3 est ecarte; un autre candidat gagne', async () => {
  await db.doc('users/a').set({user_role: 'joueur', first_name: 'Alice'});
  await db.doc('users/b').set({user_role: 'joueur', first_name: 'Bob'});
  await db.doc(`monthly_challenge_entries/${CHALLENGE_ID}_a`).set({
    uid: 'a', month: MONTH, challenge_id: CHALLENGE_ID, user_ref: db.doc('users/a'), status: 'qualified',
  });
  await db.doc(`monthly_challenge_entries/${CHALLENGE_ID}_b`).set({
    uid: 'b', month: MONTH, challenge_id: CHALLENGE_ID, user_ref: db.doc('users/b'), status: 'qualified',
  });

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
    result = await mc.drawWinnerForMonthlyChallenge(buildConfig(), 'test');
  } finally {
    crypto.randomInt = originalRandomInt;
    db.runTransaction = originalRunTransaction;
  }

  assert.equal(result.status, 'completed');
  assert.equal(result.winnerUid, 'b', 'le candidat banni ne doit jamais gagner');
});

// ---------------------------------------------------------------------
// Retry-budget-exceeded.
// ---------------------------------------------------------------------
test('plus de MONTHLY_CHALLENGE_MAX_CANDIDATE_ATTEMPTS bannis avec des non-testes restants -> retry_needed', async () => {
  const TOTAL = mc.MONTHLY_CHALLENGE_MAX_CANDIDATE_ATTEMPTS + 5;
  for (let i = 0; i < TOTAL; i += 1) {
    const uid = `u${String(i).padStart(3, '0')}`;
    await db.doc(`users/${uid}`).set({user_role: 'joueur'});
    await db.doc(`monthly_challenge_entries/${CHALLENGE_ID}_${uid}`).set({
      uid, month: MONTH, challenge_id: CHALLENGE_ID, user_ref: db.doc(`users/${uid}`), status: 'qualified',
    });
  }
  const entriesSnap = await db.collection('monthly_challenge_entries').get();
  const orderedUids = entriesSnap.docs.map((d) => d.data().uid);
  const toBan = orderedUids.slice(0, mc.MONTHLY_CHALLENGE_MAX_CANDIDATE_ATTEMPTS);

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
    result = await mc.drawWinnerForMonthlyChallenge(buildConfig(), 'test');
  } finally {
    crypto.randomInt = originalRandomInt;
    db.runTransaction = originalRunTransaction;
  }

  assert.equal(result.status, 'retry_needed');
  assert.equal((await db.collection('prizes').get()).size, 0);
  const draw = await db.doc(`monthly_challenge_draws/${CHALLENGE_ID}`).get();
  assert.equal(draw.exists, false, 'no draw doc must be written on retry_needed');

  const second = await mc.drawWinnerForMonthlyChallenge(buildConfig(), 'test');
  assert.equal(second.status, 'completed');
});

// ---------------------------------------------------------------------
// Concurrence.
// ---------------------------------------------------------------------
test('deux executions concurrentes: exactement un gagnant, aucune duplication', async () => {
  await seedQualifiedEntries(50);
  const [r1, r2] = await Promise.all([
    mc.drawWinnerForMonthlyChallenge(buildConfig(), 'test'),
    mc.drawWinnerForMonthlyChallenge(buildConfig(), 'test'),
  ]);
  const statuses = [r1.status, r2.status].sort();
  assert.deepEqual(statuses, ['already_completed', 'completed']);
  assert.equal((await db.collection('prizes').get()).size, 1);
});

// ---------------------------------------------------------------------
// Deja tire.
// ---------------------------------------------------------------------
test('defi deja tire: already_completed, aucune nouvelle ecriture', async () => {
  await seedQualifiedEntries(3);
  const first = await mc.drawWinnerForMonthlyChallenge(buildConfig(), 'test');
  assert.equal(first.status, 'completed');
  const second = await mc.drawWinnerForMonthlyChallenge(buildConfig(), 'test');
  assert.equal(second.status, 'already_completed');
  assert.equal(second.winnerUid, first.winnerUid);
  assert.equal((await db.collection('prizes').get()).size, 1);
});

// ---------------------------------------------------------------------
// Prize deja existant sans tirage finalise.
// ---------------------------------------------------------------------
test('prize deja existant sans draw finalise: manual_review_required, aucune duplication', async () => {
  await seedQualifiedEntries(3);
  await db.doc(`prizes/monthly_challenge_${CHALLENGE_ID}`).set({prize_type: 'monthly_challenge'});
  const result = await mc.drawWinnerForMonthlyChallenge(buildConfig(), 'test');
  assert.equal(result.status, 'manual_review_required');
  assert.equal(result.reason, 'prize_exists_without_final_draw');
  assert.equal((await db.collection('prizes').get()).size, 1);
});

// ---------------------------------------------------------------------
// Pas encore a echeance : validateDrawExecutionOrThrow rejette (throw).
// ---------------------------------------------------------------------
test("tirage avant draw_date: rejette (HttpsError failed-precondition)", async () => {
  await seedQualifiedEntries(2);
  await assert.rejects(
    () => mc.drawWinnerForMonthlyChallenge(buildConfig({draw_date: admin.firestore.Timestamp.fromDate(new Date('2099-01-01'))}), 'test'),
    (error) => error.code === 'failed-precondition',
  );
});

// ---------------------------------------------------------------------
// Donnees legacy : type 'restaurant' (alias historique de 'merchant').
// ---------------------------------------------------------------------
test("type legacy 'restaurant' se normalise en 'merchant' et tire normalement", async () => {
  const merchantChallengeId = `merchant_${MONTH}`;
  await db.doc('users/u1').set({user_role: 'joueur'});
  await db.doc(`monthly_challenge_entries/${merchantChallengeId}_u1`).set({
    uid: 'u1', month: MONTH, challenge_id: merchantChallengeId, type: 'merchant',
    user_ref: db.doc('users/u1'), status: 'qualified',
  });
  const result = await mc.drawWinnerForMonthlyChallenge(buildConfig({
    type: 'restaurant', title: 'Commercant du mois', prize_title: 'Panier garni',
  }), 'test');
  assert.equal(result.status, 'completed');
  assert.equal(result.challengeId, merchantChallengeId);
});
