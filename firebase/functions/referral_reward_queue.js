const admin=require('firebase-admin');
const functions=require('firebase-functions');
const {excluded}=require('./prize_integrity');
const db=admin.firestore();
const pendingRef=id=>db.doc(`referral_reward_pending/${id}`);
// All reads, no writes: acceptance enqueues this payload in its own transaction.
async function prepareReferralReward(tx, referralId, inviterUid, acceptedAt) {
  const games=await tx.get(db.collection('referral_games').where('status','==','active'));
  const active=games.docs.filter(doc=>{
    const g=doc.data(); return g.start_date?.toMillis()<=acceptedAt.toMillis() && g.end_date?.toMillis()>=acceptedAt.toMillis();
  });
  if(active.length>1) throw new Error('Multiple active referral games');
  return {referral_id:referralId,inviter_uid:inviterUid,accepted_at:acceptedAt,
    game_id:active[0]?.id||null,mode:active.length?'game':'classic',status:'pending'};
}
async function processReferralReward(referralId, grantClassic) {
  const eventRef=pendingRef(referralId);
  const event=await eventRef.get();
  if(!event.exists) return {status:'manual_review_required',reason:'missing_durable_event'};
  if(event.data().status!=='pending') return {status:event.data().status};
  if(event.data().mode==='classic'){
    if(!grantClassic) throw new Error('Classic reward handler required');
    const result=await grantClassic(referralId,'system/referral_reward_retry');
    const status=result.granted||result.reason==='already_granted'?'granted':'manual_review_required';
    await eventRef.update({status,reason:result.reason||null,processed_at:admin.firestore.FieldValue.serverTimestamp()});
    if(status==='manual_review_required') functions.logger.error('REFERRAL_REWARD_MANUAL_REVIEW',{referralId,reason:result.reason});
    return {status};
  }
  return db.runTransaction(async tx=>{
    const current=await tx.get(eventRef);
    const reward=current.data();
    if(reward.status!=='pending') return {status:reward.status};
    const gameRef=db.doc(`referral_games/${reward.game_id}`);
    const entryRef=gameRef.collection('entries').doc(referralId);
    const userRef=db.doc(`users/${reward.inviter_uid}`);
    const [game,entry,referral,user]=await Promise.all([tx.get(gameRef),tx.get(entryRef),tx.get(db.doc(`referrals/${referralId}`)),tx.get(userRef)]);
    let reason='';
    const g=game.data()||{};
    if(!game.exists||!referral.exists||referral.data().status!=='accepted'||referral.data().inviterUid!==reward.inviter_uid) reason='invalid_source';
    else if(entry.exists && entry.data().inviter_uid!==reward.inviter_uid) reason='contradictory_ticket';
    else if(entry.exists) {tx.update(eventRef,{status:'granted'}); return {status:'granted'};}
    else if(g.winner_uid||['completed','no_eligible_entries'].includes(g.draw_status)) reason='draw_already_finalized';
    else if(!g.start_date?.toMillis||!g.end_date?.toMillis||reward.accepted_at.toMillis()<g.start_date.toMillis()||reward.accepted_at.toMillis()>g.end_date.toMillis()) reason='acceptance_outside_period';
    else if(!user.exists||excluded(user.data())) reason='inviter_ineligible';
    if(reason){
      tx.update(eventRef,{status:'manual_review_required',reason});
      functions.logger.error('REFERRAL_REWARD_MANUAL_REVIEW',{referralId,gameId:reward.game_id,reason});
      return {status:'manual_review_required',reason};
    }
    tx.create(entryRef,{inviter_uid:reward.inviter_uid,inviter_ref:userRef,referral_id:referralId,created_at:admin.firestore.FieldValue.serverTimestamp()});
    tx.update(gameRef,{ticket_count:admin.firestore.FieldValue.increment(1)});
    tx.update(eventRef,{status:'granted',processed_at:admin.firestore.FieldValue.serverTimestamp()});
    return {status:'granted'};
  });
}
async function retryPendingReferralRewards(grantClassic) {
  const failed=[];
  let cursor; const deadline=Date.now()+500000;
  do {
    let query=db.collection('referral_reward_pending').where('status','==','pending').orderBy('accepted_at').limit(200);
    if(cursor) query=query.startAfter(cursor);
    const events=await query.get();
    for(const event of events.docs) try { await processReferralReward(event.id,grantClassic); }
    catch(error){failed.push(event.id);functions.logger.error('REFERRAL_REWARD_RETRY_FAILED',{referralId:event.id,code:error.code||null});}
    cursor=events.size===200?events.docs.at(-1):null;
  } while(cursor && Date.now()<deadline);
  if(cursor) functions.logger.warn('REFERRAL_REWARD_RETRY_REMAINING');
  if(failed.length) throw new Error(`Referral rewards failed: ${failed.length}`);
}
module.exports={prepareReferralReward,processReferralReward,retryPendingReferralRewards,pendingRef};
