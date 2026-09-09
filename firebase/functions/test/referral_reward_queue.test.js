process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
process.env.GCLOUD_PROJECT='demo-proxiplay-outbox';
const test=require('node:test');
const assert=require('node:assert/strict');
const admin=require('firebase-admin');
if(!admin.apps.length) admin.initializeApp();
const db=admin.firestore();
const {prepareReferralReward,processReferralReward,retryPendingReferralRewards,pendingRef}=require('../referral_reward_queue');
const {drawReferralGame}=require('../referral_game_engine');
const time=n=>admin.firestore.Timestamp.fromMillis(n);
test.beforeEach(async()=>{for(const c of await db.listCollections()) await db.recursiveDelete(c);});
async function accept(){
 await db.doc('users/inviter').set({first_name:'Alice'});
 await db.doc('referral_games/game').set({status:'active',start_date:time(1),end_date:time(10000),ticket_count:0});
 await db.doc('referrals/ref').set({status:'pending',inviterUid:'inviter'});
 await db.runTransaction(async tx=>{
  const event=await prepareReferralReward(tx,'ref','inviter',time(5000));
  tx.update(db.doc('referrals/ref'),{status:'accepted',acceptedAt:time(5000)});
  tx.create(pendingRef('ref'),event);
 });
}
test('acceptance survives failure before worker; retry and concurrent retry grant exactly one ticket',async()=>{
 await accept();
 assert.equal((await pendingRef('ref').get()).data().status,'pending');
 assert.equal((await db.doc('referral_games/game/entries/ref').get()).exists,false);
 assert.equal((await drawReferralGame('game',{now:time(20000)})).status,'manual_review_required');
 await Promise.all([processReferralReward('ref'),processReferralReward('ref')]);
 await retryPendingReferralRewards();
 assert.equal((await db.doc('referral_games/game').get()).data().ticket_count,1);
 assert.equal((await pendingRef('ref').get()).data().status,'granted');
 assert.equal((await drawReferralGame('game',{now:time(20000)})).status,'completed');
});
test('game ending after acceptance preserves ticket before final draw',async()=>{
 await accept(); await db.doc('referral_games/game').update({status:'ended'});
 assert.equal((await processReferralReward('ref')).status,'granted');
});
test('already drawn game requires manual review and cannot change historical odds',async()=>{
 await accept(); await db.doc('referral_games/game').update({draw_status:'completed',winner_uid:'other'});
 assert.equal((await processReferralReward('ref')).status,'manual_review_required');
 assert.equal((await db.doc('referral_games/game/entries/ref').get()).exists,false);
});
test('existing valid ticket marks event granted without increment; conflicting ticket blocks',async()=>{
 await accept(); await db.doc('referral_games/game/entries/ref').set({inviter_uid:'other'});
 assert.equal((await processReferralReward('ref')).status,'manual_review_required');
 await pendingRef('ref').update({status:'pending'});
 await db.doc('referral_games/game/entries/ref').set({inviter_uid:'inviter'});
 assert.equal((await processReferralReward('ref')).status,'granted');
 assert.equal((await db.doc('referral_games/game').get()).data().ticket_count,0);
});
test('acceptance transaction failure leaves neither accepted referral nor outbox',async()=>{
 await accept(); await db.doc('referrals/ref').update({status:'pending'}); await pendingRef('ref').delete();
 await assert.rejects(db.runTransaction(async tx=>{
  const event=await prepareReferralReward(tx,'ref','inviter',time(5000));
  tx.update(db.doc('referrals/ref'),{status:'accepted'}); tx.create(pendingRef('ref'),event);
  throw Error('failure before commit');
 }));
 assert.equal((await pendingRef('ref').get()).exists,false);
 assert.equal((await db.doc('referrals/ref').get()).data().status,'pending');
});
