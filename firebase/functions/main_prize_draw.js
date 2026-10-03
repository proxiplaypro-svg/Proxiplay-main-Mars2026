const {gameOwnership,gamePrizeOwnership}=require('./merchant_ownership');
const admin=require('firebase-admin');
const functions=require('firebase-functions');
const crypto=require('crypto');
const {reserveClaimCode}=require('./claim_code_registry');
const {excluded,review}=require('./prize_integrity');
const {publicPrize}=require('./public_winners');
const {runScheduledDraws}=require('./scheduled_draw_runner');
const db=admin.firestore();
async function drawMainPrize(gameId,{now=admin.firestore.Timestamp.now()}={}) {
  const gameRef=db.doc(`games/${gameId}`);
  return db.runTransaction(async tx=>{
    const snap=await tx.get(gameRef);
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
    const tickets=await tx.get(gameRef.collection('participants'));
    const eligible=[];
    for(const doc of tickets.docs){
      const ref=doc.data().user_id;
      if(!/^users\/[^/]+$/.test(ref?.path||'')) continue;
      const user=await tx.get(ref);
      if(user.exists&&!excluded(user.data())) eligible.push({ref,data:user.data()});
    }
    const existing=await tx.get(db.collection('prizes').where('game_id','==',gameRef).where('prize_type','==','principal'));
    if(!existing.empty) return review(existing.docs[0].id,'prize_exists_without_final_draw');
    if(!eligible.length){
      tx.update(gameRef,{status:'ended',draw_status:'no_eligible_entries',drawn_at:now});
      return {status:'no_eligible_entries'};
    }
    if(game.prize_usage_deadline != null &&
      (typeof game.prize_usage_deadline.toMillis !== 'function' || game.prize_usage_deadline.toMillis()<=now.toMillis())) {
      return review(gameId,'invalid_or_expired_prize_deadline');
    }
    const enseigneRef=game.enseigne_id||game.enseigne_ref;
    if(!/^enseignes\/[^/]+$/.test(enseigneRef?.path||'')) return review(gameId,'missing_enseigne');
    const shop=await tx.get(enseigneRef);
    const ownership=gameOwnership(game,shop.data());
    if(!shop.exists||!ownership.valid) return review(gameId,'invalid_merchant_owner');
    let fulfillment;
    try { fulfillment=require('./prize_fulfillment').prizeFulfillment(game,shop.data()); }
    catch (_) { return review(gameId,'invalid_prize_fulfillment'); }
    const winner=eligible[crypto.randomInt(eligible.length)];
    const prizeRef=db.collection('prizes').doc();
    const claimCode=await reserveClaimCode(tx,db);
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
  });
}
// Pure. Mirrors drawMainPrize()'s own already_finalized check for the two
// no-winner terminal paths (no_main_prize, no_eligible_entries) -- which
// never set hasWinner to true, since there is no winner to record. The
// old query (hasWinner=='false' AND end_date<=now) kept matching every
// game ever finalized that way, forever: the set only grows as more
// games end without a main prize or without eligible entries, and each
// one still had to be re-opened in a transaction every single night just
// to immediately bail out. That ever-growing graveyard is what pushed
// pickMainPrizeWinners past its Gen1 timeout and starved genuinely
// pending games (Kids Troc, Char a voile, support smartphone) that never
// got reached. Filtering here, on data already in hand from the list
// query, skips them before they ever cost a transaction.
function needsMainPrizeDraw(data) {
  if (data.hasWinner === true) return false;
  if (['no_eligible_entries', 'no_main_prize'].includes(data.draw_status)) return false;
  return true;
}

const pickMainPrizeWinners=functions.runWith({timeoutSeconds:300}).pubsub.schedule('0 0 * * *').timeZone('Europe/Paris').onRun(async()=>{
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
module.exports={drawMainPrize,pickMainPrizeWinners,needsMainPrizeDraw};
