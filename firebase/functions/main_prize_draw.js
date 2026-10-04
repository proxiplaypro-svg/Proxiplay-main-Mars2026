const {gameOwnership,gamePrizeOwnership}=require('./merchant_ownership');
const admin=require('firebase-admin');
const functions=require('firebase-functions');
const crypto=require('crypto');
const {reserveClaimCode}=require('./claim_code_registry');
const {excluded,review}=require('./prize_integrity');
const {publicPrize}=require('./public_winners');
const {runScheduledDraws}=require('./scheduled_draw_runner');
const db=admin.firestore();

// "Moteur C": drawMainPrize() is split into three phases so the ONLY
// Firestore transaction it opens stays O(1) relative to participant
// count, matching the pre-07520aa5 architecture's cost profile while
// keeping every business protection added since (ownership, fulfillment,
// prize_usage_deadline, existing-prize guard, claim code registry,
// excluded-account filtering). See docs/incident notes: the regression
// that broke large-participant draws (Kids Troc: 1576, the 04/10 games:
// ~3000) was introduced in a single commit (7520aa5, 09/09) that moved
// the full participant/user eligibility scan INSIDE the transaction,
// one sequential tx.get() per participant. Batching (tx.getAll()) later
// reduced the round-trip count but the transaction's cost was still
// proportional to participant count and vulnerable to Firestore
// transaction retries on any contended read. Phase 1 below now does
// that scan OUTSIDE any transaction; Phase 3 only re-reads the single
// candidate chosen in Phase 2, plus the handful of fixed-size documents
// (game, enseigne, existing-prize query, claim code registry) needed to
// keep the final write atomically consistent.
//
// Phase 1 and Phase 3 intentionally duplicate the same non-participant
// checks (already_finalized, not_due, inactive, hasMain, prize_usage_
// deadline, ownership, fulfillment, existing principal prize): Phase 1
// decides whether a draw should be attempted at all and builds the
// eligible pool; Phase 3 re-verifies every one of those conditions
// against freshly re-read documents at commit time, because Phase 1's
// reads are NOT atomic with the final write and anything could have
// changed in between (including a concurrent execution of the very same
// scheduled job on the same game).

const PARTICIPANT_USER_BATCH_SIZE = 300;
// Explicit bound on Phase 3's candidate retry loop (see loadEligibleParticipants
// below for why eligible still has one entry per eligible TICKET, not per
// user): guarantees termination even in the pathological case of a mass
// ban/suspension landing between Phase 1 and Phase 3, without ever
// re-scanning the full participants collection to find a replacement.
const MAX_CANDIDATE_ATTEMPTS = 20;

// Batched user-doc loader. Works with ANY reader exposing getAll(...refs) --
// a plain Firestore instance (used by Phase 1, outside any transaction)
// or a Transaction (kept for backward compatibility / tests). Dedup +
// chunking unchanged from the batching fix: the same user can legitimately
// hold several tickets, so a duplicate ref is fetched once and reused for
// every one of their entries -- eligibility, multiplicity (ticket-weighted
// odds) and the final random draw are unaffected, since `entries` below
// still has one item per TICKET, not per unique user.
async function loadEligibleParticipants(reader, ticketDocs) {
  const entries = ticketDocs
    .map(doc => doc.data().user_id)
    .filter(ref => /^users\/[^/]+$/.test(ref?.path || ''));
  const uniqueRefsByPath = new Map();
  for (const ref of entries) if (!uniqueRefsByPath.has(ref.path)) uniqueRefsByPath.set(ref.path, ref);
  const uniqueRefs = [...uniqueRefsByPath.values()];
  const snapshotByPath = new Map();
  for (let i = 0; i < uniqueRefs.length; i += PARTICIPANT_USER_BATCH_SIZE) {
    const chunk = uniqueRefs.slice(i, i + PARTICIPANT_USER_BATCH_SIZE);
    const snaps = await reader.getAll(...chunk);
    for (const snap of snaps) snapshotByPath.set(snap.ref.path, snap);
  }
  const eligible = [];
  for (const ref of entries) {
    const user = snapshotByPath.get(ref.path);
    if (user && user.exists && !excluded(user.data())) eligible.push({ref, data: user.data()});
  }
  return eligible;
}

// Pure, no I/O. Mirrors drawMainPrize()'s own already_finalized check.
function isAlreadyFinalized(game) {
  return !!(game.hasWinner || game.main_prize_winner || ['no_eligible_entries','no_main_prize'].includes(game.draw_status));
}
function isNotDue(game, now) {
  return !game.end_date?.toMillis || game.end_date.toMillis() > now.toMillis();
}
function isInactiveStatus(game) {
  return ['draft','cancelled','canceled','disabled'].includes(game.status);
}
function resolveHasMainPrize(game) {
  return typeof game.hasMainPrize==='boolean' ? game.hasMainPrize : !!(
    game.prize_value!=null ||
    (typeof game.main_prize_title==='string'&&game.main_prize_title.trim()) ||
    (typeof game.main_prize_description==='string'&&game.main_prize_description.trim())
  );
}
function isExpiredPrizeDeadline(game, now) {
  return game.prize_usage_deadline != null &&
    (typeof game.prize_usage_deadline.toMillis !== 'function' || game.prize_usage_deadline.toMillis()<=now.toMillis());
}

// Short, O(1) transaction shared by both no-winner terminal outcomes
// (no_main_prize: no prize configured at all; no_eligible_entries:
// nobody left after Phase 1's eligibility scan). Re-reads the game fresh
// so a concurrent execution that already finalized it by ANY path --
// including a real winner -- is detected instead of silently overwritten.
async function finalizeWithoutPrize(gameRef, drawStatus, now) {
  return db.runTransaction(async tx => {
    const snap = await tx.get(gameRef);
    if (!snap.exists) return {status:'not_found'};
    const game = snap.data();
    if (isAlreadyFinalized(game)) return {status:'already_finalized'};
    tx.update(gameRef, {status:'ended', draw_status:drawStatus, drawn_at:now});
    return {status:drawStatus};
  });
}

function pickRandomCandidate(pool) {
  return pool[crypto.randomInt(pool.length)];
}

async function drawMainPrize(gameId,{now=admin.firestore.Timestamp.now()}={}) {
  const gameRef=db.doc(`games/${gameId}`);
  // Diagnostic-only timing (kept from the Oct 3-4 incident response while
  // the restructuring above is validated in production). Pure logging:
  // no business logic, write, or return value depends on it.
  const t0=Date.now();
  const step=(label)=>functions.logger.info('DRAW_STEP_TIMING',{job:'pickMainPrizeWinners',gameId,step:label,elapsedMs:Date.now()-t0});

  // ---------------- Phase 1: outside any transaction ----------------
  // Everything that CAN be decided or read without atomicity. No winner
  // is picked or written here.
  const snap = await gameRef.get();
  step('phase1_game_read');
  if (!snap.exists) return {status:'not_found'};
  const game = snap.data();
  if (isAlreadyFinalized(game)) return {status:'already_finalized'};
  if (isNotDue(game, now)) return {status:'not_due'};
  if (isInactiveStatus(game)) return {status:'inactive'};
  if (!resolveHasMainPrize(game)) {
    const result = await finalizeWithoutPrize(gameRef, 'no_main_prize', now);
    step(`phase1_short_circuit:${result.status}`);
    return result;
  }
  if (isExpiredPrizeDeadline(game, now)) return review(gameId,'invalid_or_expired_prize_deadline');
  const enseigneRef=game.enseigne_id||game.enseigne_ref;
  if(!/^enseignes\/[^/]+$/.test(enseigneRef?.path||'')) return review(gameId,'missing_enseigne');
  const shop = await enseigneRef.get();
  step('phase1_enseigne_read');
  const ownership = gameOwnership(game, shop.data());
  if (!shop.exists || !ownership.valid) return review(gameId,'invalid_merchant_owner');
  try { require('./prize_fulfillment').prizeFulfillment(game, shop.data()); }
  catch (_) { return review(gameId,'invalid_prize_fulfillment'); }
  const existing = await db.collection('prizes').where('game_id','==',gameRef).where('prize_type','==','principal').get();
  step('phase1_existing_prize_query');
  if (!existing.empty) return review(existing.docs[0].id,'prize_exists_without_final_draw');
  const tickets = await gameRef.collection('participants').get();
  step(`phase1_participants_read:count=${tickets.docs.length}`);
  const eligible = await loadEligibleParticipants(db, tickets.docs);
  step(`phase1_eligible_loaded:count=${eligible.length}`);
  if (!eligible.length) {
    const result = await finalizeWithoutPrize(gameRef, 'no_eligible_entries', now);
    step(`phase1_short_circuit:${result.status}`);
    return result;
  }

  // ---------------- Phase 2: pure selection, no I/O ----------------
  // Exactly the same probabilistic semantics as before the split: a
  // uniform pick over the ticket-weighted eligible array (one entry per
  // eligible TICKET, so a user holding several tickets is proportionally
  // more likely to be selected).
  const initialCandidate = pickRandomCandidate(eligible);

  // ---------------- Phase 3: short transaction, O(1) ----------------
  // Re-verifies every condition above against freshly re-read documents,
  // then re-reads ONLY the chosen candidate (retrying within the
  // already-eligible local pool, bounded, if that candidate turns out to
  // have become ineligible since Phase 1) before writing. Never re-reads
  // the participants subcollection or any other participant's user doc.
  const initialPool=[initialCandidate, ...eligible.filter(c=>c!==initialCandidate)];

  return db.runTransaction(async tx => {
    step('phase3_attempt_start');
    const freshSnap = await tx.get(gameRef);
    step('phase3_game_read');
    if (!freshSnap.exists) return {status:'not_found'};
    const freshGame = freshSnap.data();
    if (isAlreadyFinalized(freshGame)) return {status:'already_finalized'};
    if (isNotDue(freshGame, now)) return {status:'not_due'};
    if (isInactiveStatus(freshGame)) return {status:'inactive'};
    if (!resolveHasMainPrize(freshGame)) {
      tx.update(gameRef,{status:'ended',draw_status:'no_main_prize',drawn_at:now});
      return {status:'no_main_prize'};
    }
    if (isExpiredPrizeDeadline(freshGame, now)) return review(gameId,'invalid_or_expired_prize_deadline');

    const freshShop = await tx.get(enseigneRef);
    step('phase3_enseigne_read');
    const freshOwnership = gameOwnership(freshGame, freshShop.data());
    if (!freshShop.exists || !freshOwnership.valid) return review(gameId,'invalid_merchant_owner');
    let fulfillment;
    try { fulfillment=require('./prize_fulfillment').prizeFulfillment(freshGame, freshShop.data()); }
    catch (_) { return review(gameId,'invalid_prize_fulfillment'); }

    const freshExisting = await tx.get(db.collection('prizes').where('game_id','==',gameRef).where('prize_type','==','principal'));
    step('phase3_existing_prize_query');
    if (!freshExisting.empty) return review(freshExisting.docs[0].id,'prize_exists_without_final_draw');

    let winner=null;
    let pool=initialPool;
    let attempt=0;
    for (; attempt<MAX_CANDIDATE_ATTEMPTS && pool.length>0; attempt+=1) {
      const candidate = attempt===0 ? pool[0] : pickRandomCandidate(pool);
      const userSnap = await tx.get(candidate.ref);
      step(`phase3_candidate_read:attempt=${attempt}`);
      if (userSnap.exists && !excluded(userSnap.data())) { winner={ref:candidate.ref, data:userSnap.data()}; break; }
      // The candidate's own account is gone/excluded: every one of their
      // other tickets would fail the exact same check, so drop them all
      // at once rather than wasting further attempts re-reading the same
      // now-invalid user doc.
      pool=pool.filter(c=>c.ref.path!==candidate.ref.path);
    }
    if (!winner) {
      if (pool.length===0) {
        // Every single Phase-1 candidate was actually tried and is now
        // ineligible: a genuinely verified "nobody left". Safe to finalize.
        tx.update(gameRef,{status:'ended',draw_status:'no_eligible_entries',drawn_at:now});
        return {status:'no_eligible_entries'};
      }
      // The retry bound was hit while candidates from Phase 1 remain
      // UNTESTED: we do not know whether any of them is still eligible,
      // so we must never claim there is no one. Writing nothing is the
      // correctness guarantee here -- the game document stays exactly as
      // needsMainPrizeDraw() already saw it, so the next scheduled run
      // (or a fresh manual trigger) picks it up again as an ordinary
      // candidate and runs a brand new Phase 1 against current data,
      // which may well find the untested candidates still eligible.
      functions.logger.warn('DRAW_CANDIDATE_RETRY_BUDGET_EXCEEDED',{job:'pickMainPrizeWinners',gameId,triedCount:attempt,untestedRemaining:pool.length});
      return {status:'retry_needed',reason:'candidate_retry_budget_exceeded'};
    }

    const prizeRef=db.collection('prizes').doc();
    const claimCode=await reserveClaimCode(tx,db);
    step('phase3_claim_code_reserved');
    const first=String(winner.data.first_name||winner.data.firstName||'').split(/\s+/)[0];
    const city=String(winner.data.city||'');
    const prize={prize_type:'principal',...gamePrizeOwnership(db,freshOwnership,enseigneRef,fulfillment),partner_delivery_eligible:fulfillment.type==='partner'&&freshGame.partner_delivery_enabled===true,name:freshGame.name||'Lot principal',description:freshGame.description||'',
      winner_id:winner.ref,game_id:gameRef,enseigne_id:enseigneRef,enseigne_name:freshShop.data().name||freshGame.enseigne_name||'',
      claim_code:claimCode,claimed:false,win_date:now,
      prize_value:Number.isFinite(Number(freshGame.prize_value))?Number(freshGame.prize_value):0,
      winnerFirstName:first,winnerCity:city,winner_first_name:first,winner_city:city,
      ...(freshGame.prize_usage_deadline?{usage_deadline:freshGame.prize_usage_deadline}:{}),};
    tx.update(gameRef,{hasWinner:true,main_prize_winner:winner.ref,status:'ended',draw_status:'completed',drawn_at:now,
      winnerFirstName:first,winnerCity:city,winner_first_name:first,winner_city:city});
    tx.set(prizeRef,prize);
    tx.set(winner.ref.collection('my_lots').doc(prizeRef.id),{prize_id:prizeRef});
    tx.set(db.doc(`public_prize_winners/${prizeRef.id}`),publicPrize(prize,winner.data));
    return {status:'completed',prizeId:prizeRef.id};
  }).then(result=>{ step(`phase3_settled:${result?.status||'unknown'}`); return result; },
    error=>{ step(`phase3_failed:${error?.code||error?.message||'unknown'}`); throw error; });
}
// Pure. Mirrors EVERY one of drawMainPrize()'s own early-return branches
// that writes nothing to Firestore -- already_finalized (no_main_prize,
// no_eligible_entries: there is no winner to record, so hasWinner never
// becomes true) AND inactive (draft/cancelled/canceled/disabled: that
// branch returns {status:'inactive'} with no write at all, confirmed by
// reading drawMainPrize() itself). Both kinds permanently never resolve
// themselves in the data, so without this filter they accumulate forever
// and get re-opened every single night just to immediately bail out
// again. Filtering here, on data already in hand from the list query,
// skips all of them before Phase 1 even runs. The only remaining
// no-write branch, not_due, is structurally excluded by the query's own
// end_date<=now bound and needs no filter here.
function needsMainPrizeDraw(data) {
  if (data.hasWinner === true || data.main_prize_winner != null) return false;
  if (['no_eligible_entries', 'no_main_prize'].includes(data.draw_status)) return false;
  if (['draft', 'cancelled', 'canceled', 'disabled'].includes(data.status)) return false;
  return true;
}

// timeoutSeconds/memory kept at the Oct 3-4 incident values while the
// Phase 1/2/3 restructuring is validated against production traffic;
// revisit once a transaction-cost-independent-of-participant-count is
// confirmed live.
const pickMainPrizeWinners=functions.runWith({timeoutSeconds:300,memory:'1GB'}).pubsub.schedule('0 0 * * *').timeZone('Europe/Paris').onRun(async()=>{
  const now=admin.firestore.Timestamp.now();
  return runScheduledDraws({name:'pickMainPrizeWinners',logger:functions.logger,
    concurrency:8,
    timeBudgetMs:270000,
    load:async()=>{
      // end_date<=now alone -- no hasWinner equality filter -- also
      // catches legacy games where hasWinner was never written at all:
      // a plain equality filter excludes documents missing that field
      // entirely, which silently hid exactly this kind of game.
      const snap=await db.collection('games').where('end_date','<=',now).get();
      const candidates=snap.docs.filter(doc=>needsMainPrizeDraw(doc.data()||{}));
      functions.logger.info('DRAW_CANDIDATES_FILTERED',{job:'pickMainPrizeWinners',scanned:snap.docs.length,candidates:candidates.length});
      return candidates;
    },
    draw:doc=>drawMainPrize(doc.id,{now})});
});
module.exports={drawMainPrize,pickMainPrizeWinners,needsMainPrizeDraw,loadEligibleParticipants,PARTICIPANT_USER_BATCH_SIZE,MAX_CANDIDATE_ATTEMPTS};
