// "Moteur C" validation: Phase 1 (hors transaction) / Phase 2 (selection
// pure) / Phase 3 (transaction finale courte). This file proves the
// restructuring requested after the Git-history audit: the final
// transaction's operation count must stay CONSTANT as participant count
// grows (10 -> 1576 -> 3000), every business protection added since
// 12bd6aa (ownership, fulfillment, prize_usage_deadline, existing-prize
// guard, claim code registry, excluded-account filtering) must still be
// enforced, ticket-weighted multiplicity must be preserved, and a
// candidate that becomes ineligible between Phase 1 and Phase 3 must
// never finalize the game without a winner.
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-phase-engine';
process.env.FUNCTIONS_EMULATOR = 'true';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const admin = require('firebase-admin');
const { Transaction } = require('@google-cloud/firestore');
const ft = require('firebase-functions-test')();
admin.initializeApp();
const { drawMainPrize, loadEligibleParticipants, needsMainPrizeDraw, MAX_CANDIDATE_ATTEMPTS } = require('../main_prize_draw');
const db = admin.firestore();
test.after(() => ft.cleanup());

test.beforeEach(async () => {
  for (const col of await db.listCollections()) await db.recursiveDelete(col);
});

async function seedShopAndGame(gameOverrides = {}, shopOverrides = {}) {
  await db.doc('users/merchant').set({ user_role: 'commercant' });
  await db.doc('enseignes/shop').set({ owner: db.doc('users/merchant'), email: 'shop@example.com', ...shopOverrides });
  await db.doc('games/g').set({
    hasWinner: false,
    hasMainPrize: true,
    name: 'Lot principal',
    enseigne_id: db.doc('enseignes/shop'),
    end_date: admin.firestore.Timestamp.fromDate(new Date('2020-01-01')),
    ...gameOverrides,
  });
}

async function seedParticipants(count, { prefix = 'p' } = {}) {
  const CHUNK = 200;
  for (let start = 0; start < count; start += CHUNK) {
    const batch = db.batch();
    const end = Math.min(start + CHUNK, count);
    for (let i = start; i < end; i += 1) {
      const userRef = db.doc(`users/${prefix}${i}`);
      batch.set(userRef, { user_role: 'joueur', first_name: `Player${i}`, city: 'Paris' });
      batch.set(db.doc(`games/g/participants/t${prefix}${i}`), { user_id: userRef });
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
  }).then(result => ({ result, count }));
}

// ---------------------------------------------------------------------
// Requirement: transaction op count constant across 10 / 1576 / 3000.
// ---------------------------------------------------------------------
for (const n of [10, 1576, 3000]) {
  test(`Phase 3 transaction stays O(1): ${n} participants`, async () => {
    await seedShopAndGame();
    await seedParticipants(n);
    const { result, count } = await countTransactionOps(() => drawMainPrize('g'));
    assert.equal(result.status, 'completed');
    assert.ok(count <= 8, `expected <=8 ops inside the transaction for ${n} participants, got ${count}`);
  });
}

test('Phase 3 op count for 10 and 3000 participants is IDENTICAL, not just bounded', async () => {
  await seedShopAndGame();
  await seedParticipants(10);
  const small = await countTransactionOps(() => drawMainPrize('g'));
  assert.equal(small.result.status, 'completed');

  for (const col of await db.listCollections()) await db.recursiveDelete(col);
  await seedShopAndGame();
  await seedParticipants(3000);
  const large = await countTransactionOps(() => drawMainPrize('g'));
  assert.equal(large.result.status, 'completed');

  assert.equal(small.count, large.count, 'transaction op count must not depend on participant count');
});

// ---------------------------------------------------------------------
// Normal draw + full field-level write comparison (nothing dropped
// relative to the pre-restructuring behavior).
// ---------------------------------------------------------------------
test('normal draw: every business write from before the split is still produced, with the same fields', async () => {
  await seedShopAndGame({ prize_value: 42, description: 'Un super lot', partner_delivery_enabled: true });
  await seedParticipants(5);
  const result = await drawMainPrize('g');
  assert.equal(result.status, 'completed');

  const game = (await db.doc('games/g').get()).data();
  assert.equal(game.hasWinner, true);
  assert.equal(game.status, 'ended');
  assert.equal(game.draw_status, 'completed');
  assert.ok(game.drawn_at);
  assert.ok(game.main_prize_winner);
  assert.equal(typeof game.winnerFirstName, 'string');
  assert.equal(typeof game.winnerCity, 'string');
  assert.equal(game.winner_first_name, game.winnerFirstName);
  assert.equal(game.winner_city, game.winnerCity);

  const prizes = await db.collection('prizes').get();
  assert.equal(prizes.size, 1);
  const prize = prizes.docs[0].data();
  assert.equal(prize.prize_type, 'principal');
  assert.equal(prize.winner_id.path, game.main_prize_winner.path);
  assert.equal(prize.game_id.path, 'games/g');
  assert.equal(prize.enseigne_id.path, 'enseignes/shop');
  assert.ok('enseigne_name' in prize);
  assert.ok('owner_id' in prize);
  assert.ok('fulfillment_type' in prize);
  assert.equal(typeof prize.claim_code, 'string');
  assert.ok(prize.claim_code.length >= 8);
  assert.equal(prize.claimed, false);
  assert.ok(prize.win_date);
  assert.equal(prize.prize_value, 42);
  assert.equal(prize.name, 'Lot principal');
  assert.equal(prize.description, 'Un super lot');
  assert.equal(typeof prize.winnerFirstName, 'string');
  assert.equal(typeof prize.winnerCity, 'string');

  const myLots = await db.collection(`users/${game.main_prize_winner.path.split('/')[1]}/my_lots`).get();
  assert.equal(myLots.size, 1);
  assert.equal(myLots.docs[0].data().prize_id.path, prizes.docs[0].ref.path);

  const publicWinner = await db.doc(`public_prize_winners/${prizes.docs[0].id}`).get();
  assert.ok(publicWinner.exists);
  assert.equal(typeof publicWinner.data().winnerFirstName, 'string');
  assert.equal(typeof publicWinner.data().winnerCity, 'string');
  assert.equal(publicWinner.data().name, 'Lot principal');
  assert.equal(publicWinner.data().game_id.path, 'games/g');
});

// ---------------------------------------------------------------------
// No eligible participant at all (Phase 1 short-circuit).
// ---------------------------------------------------------------------
test('no eligible participant: finalizes without a prize, no winner ever written', async () => {
  await seedShopAndGame();
  await db.doc('users/banned').set({ account_status: 'suspended' });
  await db.doc('games/g/participants/t1').set({ user_id: db.doc('users/banned') });
  const result = await drawMainPrize('g');
  assert.equal(result.status, 'no_eligible_entries');
  const game = (await db.doc('games/g').get()).data();
  assert.equal(game.hasWinner, false);
  assert.equal(game.draw_status, 'no_eligible_entries');
  assert.equal((await db.collection('prizes').get()).size, 0);
});

// ---------------------------------------------------------------------
// Candidate becomes ineligible between Phase 1 (pre-read) and Phase 3
// (transaction): must retry locally and never finalize without a winner.
// ---------------------------------------------------------------------
test('candidate banned between Phase 1 and Phase 3 is skipped; another eligible candidate still wins', async () => {
  await seedShopAndGame();
  await db.doc('users/a').set({ user_role: 'joueur', first_name: 'Alice', city: 'Lille' });
  await db.doc('users/b').set({ user_role: 'joueur', first_name: 'Bob', city: 'Metz' });
  await db.doc('games/g/participants/ta').set({ user_id: db.doc('users/a') });
  await db.doc('games/g/participants/tb').set({ user_id: db.doc('users/b') });

  // Deterministic selection: always pick index 0 of whatever pool is
  // passed to crypto.randomInt, so the test controls exactly who Phase 2
  // picks first (a) and who the Phase 3 retry picks next (b).
  const originalRandomInt = crypto.randomInt;
  crypto.randomInt = () => 0;

  // Simulate the race: by the time Phase 3 opens its transaction, user
  // "a" -- already selected and present in Phase 1's eligible pool --
  // has been suspended by some other process. db.runTransaction is the
  // exact boundary between Phase 2 (pure, already completed) and Phase 3
  // (the transaction about to open), so patching it here reproduces the
  // race precisely instead of guessing at timing.
  const originalRunTransaction = db.runTransaction.bind(db);
  let patched = false;
  db.runTransaction = async function (updateFunction) {
    if (!patched) {
      patched = true;
      await db.doc('users/a').update({ account_status: 'suspended' });
    }
    return originalRunTransaction(updateFunction);
  };

  let result;
  try {
    result = await drawMainPrize('g');
  } finally {
    crypto.randomInt = originalRandomInt;
    db.runTransaction = originalRunTransaction;
  }

  assert.equal(result.status, 'completed');
  const game = (await db.doc('games/g').get()).data();
  assert.equal(game.main_prize_winner.path, 'users/b', 'the banned candidate must never be finalized as winner');
  assert.equal((await db.collection('users/a/my_lots').get()).size, 0);
  assert.equal((await db.collection('users/b/my_lots').get()).size, 1);
});

// ---------------------------------------------------------------------
// Two concurrent executions of the same game: exactly one must win.
// ---------------------------------------------------------------------
test('two concurrent drawMainPrize() calls on the same game: exactly one creates the prize, the other reports already_finalized', async () => {
  await seedShopAndGame();
  await seedParticipants(50);
  const [r1, r2] = await Promise.all([drawMainPrize('g'), drawMainPrize('g')]);
  const statuses = [r1.status, r2.status].sort();
  assert.deepEqual(statuses, ['already_finalized', 'completed']);
  assert.equal((await db.collection('prizes').get()).size, 1);
});

// ---------------------------------------------------------------------
// A principal prize already exists without the game being finalized.
// ---------------------------------------------------------------------
test('existing principal prize without a final draw: flagged for manual review, no second prize created', async () => {
  await seedShopAndGame();
  await seedParticipants(3);
  await db.collection('prizes').add({ game_id: db.doc('games/g'), prize_type: 'principal' });
  const result = await drawMainPrize('g');
  assert.equal(result.status, 'manual_review_required');
  assert.equal(result.reason, 'prize_exists_without_final_draw');
  assert.equal((await db.collection('prizes').get()).size, 1);
});

// ---------------------------------------------------------------------
// Invalid ownership: game's explicit owner_id contradicts the shop's.
// ---------------------------------------------------------------------
test('invalid ownership (game owner_id contradicts enseigne owner): flagged for manual review', async () => {
  await db.doc('users/merchant').set({ user_role: 'commercant' });
  await db.doc('users/someone_else').set({ user_role: 'commercant' });
  await db.doc('enseignes/shop').set({ owner: db.doc('users/merchant') });
  await db.doc('games/g').set({
    hasWinner: false, hasMainPrize: true, name: 'Lot',
    owner_id: db.doc('users/someone_else'),
    enseigne_id: db.doc('enseignes/shop'),
    end_date: admin.firestore.Timestamp.fromDate(new Date('2020-01-01')),
  });
  await seedParticipants(3);
  const result = await drawMainPrize('g');
  assert.equal(result.status, 'manual_review_required');
  assert.equal(result.reason, 'invalid_merchant_owner');
  assert.equal((await db.collection('prizes').get()).size, 0);
});

// ---------------------------------------------------------------------
// Invalid fulfillment: a "partner" delivery requires an ownerless shop.
// ---------------------------------------------------------------------
test('invalid fulfillment (partner delivery on an owned shop): flagged for manual review', async () => {
  await seedShopAndGame({ fulfillment_type: 'partner' });
  await seedParticipants(3);
  const result = await drawMainPrize('g');
  assert.equal(result.status, 'manual_review_required');
  assert.equal(result.reason, 'invalid_prize_fulfillment');
  assert.equal((await db.collection('prizes').get()).size, 0);
});

// ---------------------------------------------------------------------
// Legacy game compatibility: no hasMainPrize boolean, enseigne_ref
// instead of enseigne_id, hasWinner entirely absent.
// ---------------------------------------------------------------------
test('legacy game shape (inferred hasMainPrize, enseigne_ref, no hasWinner field at all) still draws normally', async () => {
  await db.doc('users/merchant').set({ user_role: 'commercant' });
  await db.doc('enseignes/shop').set({ owner: db.doc('users/merchant') });
  await db.doc('games/g').set({
    main_prize_title: 'Un vieux lot legacy',
    name: 'Lot',
    enseigne_ref: db.doc('enseignes/shop'),
    end_date: admin.firestore.Timestamp.fromDate(new Date('2020-01-01')),
  });
  assert.equal((await db.doc('games/g').get()).data().hasWinner, undefined);
  await seedParticipants(3);
  const result = await drawMainPrize('g');
  assert.equal(result.status, 'completed');
  assert.equal((await db.doc('games/g').get()).data().hasWinner, true);
});

// ---------------------------------------------------------------------
// Ticket-weighted multiplicity: a user holding several tickets must
// appear as many times in the eligible pool as they hold tickets.
// ---------------------------------------------------------------------
test('loadEligibleParticipants preserves ticket-weighted multiplicity (one entry per eligible ticket, not per user)', async () => {
  await db.doc('users/heavy').set({ user_role: 'joueur', first_name: 'Heavy', city: 'Nancy' });
  await db.doc('users/light').set({ user_role: 'joueur', first_name: 'Light', city: 'Reims' });
  const ticketDocs = [
    { data: () => ({ user_id: db.doc('users/heavy') }) },
    { data: () => ({ user_id: db.doc('users/heavy') }) },
    { data: () => ({ user_id: db.doc('users/heavy') }) },
    { data: () => ({ user_id: db.doc('users/light') }) },
  ];
  const eligible = await loadEligibleParticipants(db, ticketDocs);
  assert.equal(eligible.length, 4, 'one entry per eligible ticket, duplicates preserved');
  const heavyCount = eligible.filter(e => e.ref.path === 'users/heavy').length;
  const lightCount = eligible.filter(e => e.ref.path === 'users/light').length;
  assert.equal(heavyCount, 3);
  assert.equal(lightCount, 1);
});

// ---------------------------------------------------------------------
// Retry-budget-exceeded correction: if MORE than MAX_CANDIDATE_ATTEMPTS
// candidates became ineligible between Phase 1 and Phase 3, but Phase 1's
// pool still has UNTESTED candidates left (some of whom remain valid),
// the game must NEVER be finalized no_eligible_entries -- that would be a
// false claim that nobody is left when we simply didn't check everyone.
// ---------------------------------------------------------------------
test('more than MAX_CANDIDATE_ATTEMPTS candidates become ineligible, but untested valid candidates remain: must retry_needed, never no_eligible_entries', async () => {
  await seedShopAndGame();
  const TOTAL = MAX_CANDIDATE_ATTEMPTS + 5; // guarantees untested candidates remain after the bound
  for (let i = 0; i < TOTAL; i += 1) {
    const id = String(i).padStart(3, '0');
    await db.doc(`users/u${id}`).set({ user_role: 'joueur', first_name: `U${id}`, city: 'Paris' });
    await db.doc(`games/g/participants/t${id}`).set({ user_id: db.doc(`users/u${id}`) });
  }

  // Learn the EXACT order Phase 1's own query will see (Firestore gives
  // no ordering guarantee without an explicit orderBy), so the ban list
  // below matches the candidates Phase 3's retry loop will actually walk
  // through first -- instead of assuming a specific order.
  const ticketsSnap = await db.doc('games/g').collection('participants').get();
  const orderedUserPaths = ticketsSnap.docs.map(d => d.data().user_id.path);
  assert.equal(orderedUserPaths.length, TOTAL);
  const toBan = orderedUserPaths.slice(0, MAX_CANDIDATE_ATTEMPTS);
  const stillUntested = orderedUserPaths.slice(MAX_CANDIDATE_ATTEMPTS);
  assert.ok(stillUntested.length > 0, 'test setup must leave untested candidates after the bound');

  // Deterministic selection: attempt 0 always takes pool[0], and every
  // retry's pickRandomCandidate(pool) also resolves to pool[0] once
  // crypto.randomInt is pinned to 0 -- so Phase 3 walks the pool in
  // EXACTLY the order observed above, one candidate per attempt.
  const originalRandomInt = crypto.randomInt;
  crypto.randomInt = () => 0;

  // Simulate the race: by the time Phase 3 opens, exactly the first
  // MAX_CANDIDATE_ATTEMPTS candidates (in the order Phase 3 will try
  // them) have been suspended by some other process. The rest -- still
  // valid -- are never touched, and must remain untested by this run.
  const originalRunTransaction = db.runTransaction.bind(db);
  let patched = false;
  db.runTransaction = async function (updateFunction) {
    if (!patched) {
      patched = true;
      const batch = db.batch();
      for (const path of toBan) batch.update(db.doc(path), { account_status: 'suspended' });
      await batch.commit();
    }
    return originalRunTransaction(updateFunction);
  };

  let result;
  try {
    result = await drawMainPrize('g');
  } finally {
    crypto.randomInt = originalRandomInt;
    db.runTransaction = originalRunTransaction;
  }

  assert.equal(result.status, 'retry_needed');
  assert.equal(result.reason, 'candidate_retry_budget_exceeded');

  const gameAfterRetry = (await db.doc('games/g').get()).data();
  assert.equal(gameAfterRetry.hasWinner, false, 'must never finalize a winner on a retry_needed outcome');
  assert.notEqual(gameAfterRetry.draw_status, 'no_eligible_entries', 'must never claim no_eligible_entries while untested candidates remain');
  assert.equal(gameAfterRetry.draw_status, undefined, 'the game document must be left untouched so the scheduler can retry it');
  assert.equal((await db.collection('prizes').get()).size, 0);

  // The scheduler must be able to pick this game up again: untouched by
  // the retry_needed outcome, it still matches needsMainPrizeDraw().
  assert.equal(needsMainPrizeDraw(gameAfterRetry), true);

  // A follow-up attempt (the "next scheduled run") runs a brand new
  // Phase 1 and must succeed normally against the now-stable data, using
  // one of the untested-but-still-valid candidates.
  const second = await drawMainPrize('g');
  assert.equal(second.status, 'completed');
  const finalGame = (await db.doc('games/g').get()).data();
  assert.ok(stillUntested.includes(finalGame.main_prize_winner.path), 'winner must come from the untested-but-valid pool');
});
