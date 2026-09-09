const admin=require('firebase-admin');
const functions=require('firebase-functions');
const crypto=require('crypto');
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
    if(game.hasWinner || game.main_prize_winner || game.draw_status==='no_eligible_entries') return {status:'already_finalized'};
    if(!game.end_date?.toMillis || game.end_date.toMillis()>now.toMillis()) return {status:'not_due'};
    const hasMain=typeof game.hasMainPrize==='boolean'?game.hasMainPrize:!!(game.name||game.description||game.prize_value!=null);
    if(!hasMain) return {status:'no_main_prize'};
    if(['draft','cancelled','canceled','disabled'].includes(game.status)) return {status:'inactive'};
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
    const enseigneRef=game.enseigne_id||game.enseigne_ref;
    if(!/^enseignes\/[^/]+$/.test(enseigneRef?.path||'')) return review(gameId,'missing_enseigne');
    const shop=await tx.get(enseigneRef);
    const ownerRef=game.owner_id?.path?game.owner_id:shop.data()?.owner;
    if(!shop.exists||!/^users\/[^/]+$/.test(ownerRef?.path||'') || (shop.data().owner?.path && shop.data().owner.path!==ownerRef.path)) return review(gameId,'invalid_merchant_owner');
    const winner=eligible[crypto.randomInt(eligible.length)];
    const prizeRef=db.collection('prizes').doc();
    const first=String(winner.data.first_name||winner.data.firstName||'').split(/\s+/)[0];
    const city=String(winner.data.city||'');
    const prize={prize_type:'principal',fulfillment_type:'merchant',name:game.name||'Lot principal',description:game.description||'',
      winner_id:winner.ref,game_id:gameRef,enseigne_id:enseigneRef,owner_id:ownerRef,enseigne_name:shop.data().name||game.enseigne_name||'',
      claim_code:crypto.randomBytes(10).toString('hex').toUpperCase(),claimed:false,win_date:now,
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
const pickMainPrizeWinners=functions.pubsub.schedule('0 0 * * *').timeZone('Europe/Paris').onRun(async()=>{
  const now=admin.firestore.Timestamp.now();
  return runScheduledDraws({name:'pickMainPrizeWinners',logger:functions.logger,
    load:async()=>(await db.collection('games').where('hasWinner','==',false).where('end_date','<=',now).get()).docs,
    draw:doc=>drawMainPrize(doc.id,{now})});
});
module.exports={drawMainPrize,pickMainPrizeWinners};
