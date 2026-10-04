const {gameOwnership,gamePrizeOwnership}=require('./merchant_ownership');
const admin=require('firebase-admin');
const functions=require('firebase-functions');
const crypto=require('crypto');
const {reserveClaimCode}=require('./claim_code_registry');
const {excluded,review}=require('./prize_integrity');
const {publicPrize}=require('./public_winners');
const {runScheduledDraws}=require('./scheduled_draw_runner');
const db=admin.firestore();

// Bounded/batched replacement for a sequential "await tx.get(ref)" per
// participant. A game with hundreds or thousands of tickets (Kids Troc:
// 1576) used to cost one Firestore round-trip per participant, one after
// another, inside the transaction -- the dominant reason pickMainPrizeWinners
// kept exceeding even a 300s timeout. transaction.getAll() reads several
// document references in a single batched call; refs are deduplicated
// (the same user can legitimately hold several tickets, so a duplicate
// ref is fetched once and reused for every one of their entries below --
// eligibility, multiplicity and the final random draw are unaffected).
// Chunking caps how many refs go into any single getAll() call: a bounded,
// predictable number of batched round-trips, never one unbounded burst of
// 1500+ simultaneous reads and never 1500+ sequential ones either.
const PARTICIPANT_USER_BATCH_SIZE = 300;
async function loadEligibleParticipants(tx, ticketDocs) {
  const entries = ticketDocs
    .map(doc => doc.data().user_id)
    .filter(ref => /^users\/[^/]+$/.test(ref?.path || ''));
  const uniqueRefsByPath = new Map();
  for (const ref of entries) if (!uniqueRefsByPath.has(ref.path)) uniqueRefsByPath.set(ref.path, ref);
  const uniqueRefs = [...uniqueRefsByPath.values()];
  const snapshotByPath = new Map();
  for (let i = 0; i < uniqueRefs.length; i += PARTICIPANT_USER_BATCH_SIZE) {
    const chunk = uniqueRefs.slice(i, i + PARTICIPANT_USER_BATCH_SIZE);
    const snaps = await tx.getAll(...chunk);
    for (const snap of snaps) snapshotByPath.set(snap.ref.path, snap);
  }
  const eligible = [];
  for (const ref of entries) {
    const user = snapshotByPath.get(ref.path);
    if (user && user.exists && !excluded(user.data())) eligible.push({ref, data: user.data()});
  }
  return eligible;
}

async function drawMainPrize(gameId,{now=admin.firestore.Timestamp.now()}={}) {
  const gameRef=db.doc(`games/${gameId}`);
  // Diagnostic-only timing, added to find out WHERE inside a single draw
  // the time goes for large-participant games (OukffvTfzHyvxYRzNN3F: 3078,
  // RQ8EIKYXMnJbHpz2pmbW: 2984) that kept exceeding even a 300s/1GB
  // pickMainPrizeWinners run without ever producing a DRAW_SUCCESS/
  // DRAW_FAILED log line for them -- i.e. the function hard-timed-out
  // while still awaiting this single draw's transaction, with the memory
  // bump alone not fixing it. t0 is captured once per drawMainPrize()
  // call, outside db.runTransaction(); Firestore retries the whole
  // callback on contention (a concurrent write invalidating a document
  // this transaction already read), so if 'game_read' is logged more than
  // once with growing elapsedMs, that is itself evidence of transaction
  // retries -- a candidate explanation distinct from raw CPU/memory.
  // Pure logging: no business logic, write, or return value is changed.
  const t0=Date.now();
  let attempt=0;
  const step=(label)=>functions.logger.info('DRAW_STEP_TIMING',{job:'pickMainPrizeWinners',gameId,attempt,step:label,elapsedMs:Date.now()-t0});
  return db.runTransaction(async tx=>{
    attempt+=1;
    step('attempt_start');
    const snap=await tx.get(gameRef);
    step('game_read');
    if(!snap.exists) return {status:'not_found'};
    const game=snap.data();
    if(game.hasWinner || game.main_prize_winner || ['no_eligible_entries','no_main_prize'].includes(game.draw_status)) return {status:'already_finalized'};
    if(!game.end_date?.toMillis || game.end_date.toMillis()>now.toMillis()) return {status:'not_due'};
    const hasMain=typeof game.hasMainPrize==='boolean'?game.hasMainPrize:!!(
      game.prize_value!=null ||
      (typeof game.main_prize_title==='string'&&game.main_prize_title.trim()) ||
      (typeof game.main_prize_description==='string'&&game.main_prize_description.trim())
    );
    if(['draft','cancelled','canceled','disabled'].includes(game.status)) return {status:'inactive'};
    if(!hasMain) {
      tx.update(gameRef,{status:'ended',draw_status:'no_main_prize',drawn_at:now});
      return {status:'no_main_prize'};
    }
    // Cheap, single-document/single-query checks moved before the
    // participants scan: a game permanently stuck on deadline, enseigne,
    // ownership or fulfillment now fails fast without ever touching its
    // participants subcollection at all -- same outcome, same reasons,
    // just reached without paying for a scan nothing downstream needed.
    if(game.prize_usage_deadline != null &&
      (typeof game.prize_usage_deadline.toMillis !== 'function' || game.prize_usage_deadline.toMillis()<=now.toMillis())) {
      return review(gameId,'invalid_or_expired_prize_deadline');
    }
    const enseigneRef=game.enseigne_id||game.enseigne_ref;
    if(!/^enseignes\/[^/]+$/.test(enseigneRef?.path||'')) return review(gameId,'missing_enseigne');
    const shop=await tx.get(enseigneRef);
    step('enseigne_read');
    const ownership=gameOwnership(game,shop.data());
    if(!shop.exists||!ownership.valid) return review(gameId,'invalid_merchant_owner');
    let fulfillment;
    try { fulfillment=require('./prize_fulfillment').prizeFulfillment(game,shop.data()); }
    catch (_) { return review(gameId,'invalid_prize_fulfillment'); }
    const existing=await tx.get(db.collection('prizes').where('game_id','==',gameRef).where('prize_type','==','principal'));
    step('existing_prize_query');
    if(!existing.empty) return review(existing.docs[0].id,'prize_exists_without_final_draw');
    const tickets=await tx.get(gameRef.collection('participants'));
    step(`participants_read:count=${tickets.docs.length}`);
    const eligible=await loadEligibleParticipants(tx,tickets.docs);
    step(`eligible_loaded:count=${eligible.length}`);
    if(!eligible.length){
      tx.update(gameRef,{status:'ended',draw_status:'no_eligible_entries',drawn_at:now});
      return {status:'no_eligible_entries'};
    }
    const winner=eligible[crypto.randomInt(eligible.length)];
    const prizeRef=db.collection('prizes').doc();
    const claimCode=await reserveClaimCode(tx,db);
    step('claim_code_reserved');
    const first=String(winner.data.first_name||winner.data.firstName||'').split(/\s+/)[0];
    const city=String(winner.data.city||'');
    const prize={prize_type:'principal',...gamePrizeOwnership(db,ownership,enseigneRef,fulfillment),partner_delivery_eligible:fulfillment.type==='partner'&&game.partner_delivery_enabled===true,name:game.name||'Lot principal',description:game.description||'',
      winner_id:winner.ref,game_id:gameRef,enseigne_id:enseigneRef,enseigne_name:shop.data().name||game.enseigne_name||'',
      claim_code:claimCode,claimed:false,win_date:now,
      prize_value:Number.isFinite(Number(game.prize_value))?Number(game.prize_value):0,
      winnerFirstName:first,winnerCity:city,winner_first_name:first,winner_city:city,
      ...(game.prize_usage_deadline?{usage_deadline:game.prize_usage_deadline}:{}),};
    tx.update(gameRef,{hasWinner:true,main_prize_winner:winner.ref,status:'ended',draw_status:'completed',drawn_at:now,
      winnerFirstName:first,winnerCity:city,winner_first_name:first,winner_city:city});
    tx.set(prizeRef,prize);
    tx.set(winner.ref.collection('my_lots').doc(prizeRef.id),{prize_id:prizeRef});
    tx.set(db.doc(`public_prize_winners/${prizeRef.id}`),publicPrize(prize,winner.data));
    return {status:'completed',prizeId:prizeRef.id};
  }).then(result=>{ step(`transaction_settled:${result?.status||'unknown'}`); return result; },
    error=>{ step(`transaction_failed:${error?.code||error?.message||'unknown'}`); throw error; });
}
// Pure. Mirrors EVERY one of drawMainPrize()'s own early-return branches
// that writes nothing to Firestore -- already_finalized (no_main_prize,
// no_eligible_entries: there is no winner to record, so hasWinner never
// becomes true) AND inactive (draft/cancelled/canceled/disabled: that
// branch returns {status:'inactive'} with no tx.update at all, confirmed
// by reading drawMainPrize() itself). Both kinds permanently never
// resolve themselves in the data, so without this filter they accumulate
// forever and get re-opened in a transaction every single night just to
// immediately bail out again. That ever-growing graveyard is what pushed
// pickMainPrizeWinners past its Gen1 timeout and starved genuinely
// pending games (Kids Troc, Char a voile, support smartphone) that never
// got reached. The first fix for this only covered the draw_status pair
// and missed the status/inactive branch -- still a real, demonstrated
// gap, since a stale draft/cancelled/disabled game with hasWinner:false
// and a past end_date keeps matching the query exactly like the others.
// Filtering here, on data already in hand from the list query, skips all
// of them before they ever cost a transaction. The only remaining
// no-write branch, not_due, is structurally excluded by the query's own
// end_date<=now bound and needs no filter here.
function needsMainPrizeDraw(data) {
  if (data.hasWinner === true || data.main_prize_winner != null) return false;
  if (['no_eligible_entries', 'no_main_prize'].includes(data.draw_status)) return false;
  if (['draft', 'cancelled', 'canceled', 'disabled'].includes(data.status)) return false;
  return true;
}

// Gen1 Cloud Functions allocate CPU proportionally to configured memory;
// at the 256MB default this function barely gets a sliver of vCPU.
// Production logs show single, uncontended draws (no duplicate trigger)
// still taking 1.5-3 minutes per large-participant game even with
// batched reads -- a gap never reproduced locally, where the host has
// full CPU. Deserializing/filtering thousands of Firestore documents for
// several concurrent large draws (concurrency:8) is CPU-bound work that
// a CPU-starved instance does far slower, and plausibly serializes
// draws that should run in parallel. Bumping memory (hence CPU) is a
// configuration change, not a logic change: nothing about eligibility,
// the random draw, or the final writes is touched.
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
module.exports={drawMainPrize,pickMainPrizeWinners,needsMainPrizeDraw,loadEligibleParticipants,PARTICIPANT_USER_BATCH_SIZE};
