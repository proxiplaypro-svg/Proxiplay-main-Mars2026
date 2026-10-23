process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ||= '127.0.0.1:9099';
process.env.GCLOUD_PROJECT='demo-proxiplay-acceptance-outage';
const test=require('node:test'),assert=require('node:assert/strict'),crypto=require('node:crypto'),admin=require('firebase-admin');
if(!admin.apps.length) admin.initializeApp();
const db=admin.firestore();
const queue=require('../referral_reward_queue');
queue.processReferralReward=async()=>{throw Error('simulated worker outage after commit');};
const ft=require('firebase-functions-test')();
const share=require('../lib/share_promo');
const signup=ft.wrap(share.createReferralEmailAccount), retry=ft.wrap(share.retryReferralRewards);
test.after(()=>ft.cleanup());
test('secure signup commits durable event despite worker outage and is idempotent',async()=>{
 for(const c of await db.listCollections()) await db.recursiveDelete(c);
 await db.doc('users/inviter').set({user_role:'joueur'});
 const now=Date.now();
 await db.doc('referral_games/game').set({status:'active',start_date:admin.firestore.Timestamp.fromMillis(now-60000),end_date:admin.firestore.Timestamp.fromMillis(now+60000)});
 await db.doc('referrals/r').set({status:'pending',inviterUid:'inviter',inviteCode:'code',rewardType:'all_games_until_midnight',rewardValue:1});
 const input={email:crypto.randomUUID()+'@example.test',password:'test-password-123',inviteCode:'code',requestId:crypto.randomUUID()};
 assert.equal((await signup(input,{rawRequest:{ip:'10.30.0.1'}})).success,true);
 assert.equal((await db.doc('referrals/r').get()).data().status,'accepted');
 assert.equal((await db.doc('referral_reward_pending/r').get()).data().status,'pending');
 assert.equal((await db.doc('referral_games/game/entries/r').get()).exists,false);
 assert.equal((await db.doc('reward_events/r').get()).exists,false);
 assert.equal((await signup(input,{rawRequest:{ip:'10.30.0.2'}})).success,true);
 // The scheduled retry uses the real worker; running it twice stays idempotent.
 await retry({}); await retry({});
 assert.equal((await db.doc('referral_reward_pending/r').get()).data().status,'granted');
 assert.equal((await db.doc('referral_games/game').get()).data().ticket_count,1);
 // A referral game is running: the ticket replaces the classic reward.
 assert.equal((await db.doc('reward_events/r').get()).exists,false);
 assert.ok((await db.doc('referrals/r').get()).data().acceptedAt);
 assert.equal((await db.doc('users/inviter').get()).data().allGamesAccessUntil,undefined);
});
