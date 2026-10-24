const test=require('node:test'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const admin=require('firebase-admin');
if(!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST||!String(process.env.GCLOUD_PROJECT||'').startsWith('demo-')) throw Error('isolated demo emulators required');
if(!admin.apps.length) admin.initializeApp({projectId:process.env.GCLOUD_PROJECT});
const db=admin.firestore(), ft=require('firebase-functions-test')({projectId:process.env.GCLOUD_PROJECT});
const signup=ft.wrap(require('../lib/share_promo').createReferralEmailAccount);
const hash=s=>crypto.createHash('sha256').update(s).digest('hex');
const call=(d,ip='127.0.0.1')=>signup(d,{rawRequest:{ip}});
const password='test-password-123';
const data=(suffix,code='REF')=>({email:suffix+'@example.test',password,inviteCode:code,requestId:crypto.randomUUID()});
// Start from an empty emulator so leftovers from other suites, such as another
// active referral game, cannot change the outcome.
test.before(async()=>{
 for(const c of await db.listCollections()) await db.recursiveDelete(c);
 const res=await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/accounts`,{method:'DELETE'});
 assert.ok(res.ok);
});
test.after(()=>ft.cleanup());
test('new signup, retries, existing account, invalid code, concurrent calls and limits',async()=>{
 await db.doc('users/inviter').set({user_role:'joueur',remaining_part:4});
 await db.doc('app_config/share_promo').set({enabled:true,isDraft:false,maxRewardsPerUser:20,maxRewardsPerInvitee:3});
 await db.doc('referrals/r').set({inviterUid:'inviter',inviteCode:'REF',status:'pending',rewardStatus:'not_earned',metadata:{}});
 const input=data('new');
 await Promise.all([call(input,'10.0.0.1'),call(input,'10.0.0.2')]);
 await call(input,'10.0.0.3');
 assert.equal((await db.doc('referrals/r').get()).data().inviteeUid,'ref_'+hash(input.requestId).slice(0,48));
 assert.equal((await db.collection('reward_events').get()).size,1);
 assert.ok((await db.doc('users/inviter').get()).data().allGamesAccessUntil.toMillis()>Date.now());
 const record=(await db.doc('referrals/r').get()).data();
 const expiry=require('../lib/share_promo/firestore').getNextMidnightTimestamp(record.acceptedAt);
 assert.equal((await db.doc('users/inviter').get()).data().allGamesAccessUntil.toMillis(),expiry.toMillis());
 // The server creates the invitee's player profile (role only): no reward for the invitee.
 const invitee=(await db.doc('users/'+record.inviteeUid).get()).data();
 assert.equal(invitee.user_role,'joueur');
 assert.equal(invitee.allGamesAccessUntil,undefined);
 assert.equal(invitee.remaining_part,undefined);
 await assert.rejects(call(data('used','REF'),'10.0.0.8'),e=>e.code==='failed-precondition'&&e.details?.reason==='referral_unavailable'&&!e.details.accountCreated);
 const op=(await db.doc('_referral_signup_operations/'+hash(input.requestId)).get()).data();
 assert.equal(JSON.stringify(op).includes(password),false);
 const bad=data('bad','INVALID'); await assert.rejects(call(bad,'10.0.0.4'),{code:'not-found'});
 await db.doc('referrals/s').set({inviterUid:'inviter',inviteCode:'SECOND',status:'pending',rewardStatus:'not_earned',metadata:{}});
 const existing=data('existing','SECOND'); const oldIncomplete=await admin.auth().createUser({email:existing.email,password});
 await db.doc('users/'+oldIncomplete.uid).set({user_role:'joueur',profile_completed:false});
 await assert.rejects(call(existing,'10.0.0.5'),e=>e.code==='already-exists'&&e.details?.reason==='email_exists');
 const completed=data('existing-complete','SECOND'); const oldComplete=await admin.auth().createUser({email:completed.email,password});
 await db.doc('users/'+oldComplete.uid).set({user_role:'joueur',profile_completed:true});
 await assert.rejects(call(completed,'10.0.0.10'),e=>e.code==='already-exists'&&e.details?.reason==='email_exists');
 assert.equal((await db.doc('referrals/s').get()).data().status,'pending');
 const interrupted=data('resume','SECOND'), uid='ref_'+hash(interrupted.requestId).slice(0,48);
 await db.doc('_referral_signup_operations/'+hash(interrupted.requestId)).set({uid,emailHash:hash(interrupted.email),referralId:'s',status:'pending'});
 await admin.auth().createUser({uid,email:interrupted.email,password});
 await call(interrupted,'10.0.0.6'); await call(interrupted,'10.0.0.7');
 assert.equal((await db.doc('referrals/s').get()).data().inviteeUid,uid);
 assert.equal((await db.collection('reward_events').get()).size,2);
 for(let i=0;i<5;i++) await assert.rejects(call(data('invalid'+i,'BAD'),'10.0.0.9'),{code:'not-found'});
 await assert.rejects(call(data('limit','BAD'),'10.0.0.9'),{code:'resource-exhausted'});
});

test('a special referral game grants one ticket, which replaces the unlimited access',async()=>{
 const now=Date.now();
 await db.doc('users/special-inviter').set({user_role:'joueur',remaining_part:4});
 await db.doc('referral_games/special').set({status:'active',ticket_count:0,start_date:admin.firestore.Timestamp.fromMillis(now-60000),end_date:admin.firestore.Timestamp.fromMillis(now+60000)});
 await db.doc('referrals/special').set({inviterUid:'special-inviter',inviteCode:'SPECIAL',status:'pending',rewardStatus:'not_earned',metadata:{}});
 const input=data('special','SPECIAL');
 await call(input,'10.0.1.1'); await call(input,'10.0.1.2');
 const entries=await db.collection('referral_games/special/entries').get();
 assert.equal(entries.size,1);
 assert.equal((await db.doc('referral_games/special').get()).data().ticket_count,1);
 assert.equal((await db.doc('users/special-inviter').get()).data().allGamesAccessUntil,undefined);
 assert.equal((await db.collection('reward_events').where('referralId','==','special').get()).size,0);
});

test('two accounts created concurrently with one code keep the losing account',async()=>{
 // Classic path: no referral game may be running.
 for(const g of (await db.collection('referral_games').where('status','==','active').get()).docs) await g.ref.update({status:'ended'});
 await db.doc('users/race-inviter').set({user_role:'joueur',remaining_part:2});
 await db.doc('referrals/race').set({inviterUid:'race-inviter',inviteCode:'RACE',status:'pending',rewardStatus:'not_earned',metadata:{}});
 const inputs=[data('race-a','RACE'),data('race-b','RACE')];
 for(const input of inputs){
  const uid='ref_'+hash(input.requestId).slice(0,48);
  await db.doc('_referral_signup_operations/'+hash(input.requestId)).set({uid,emailHash:hash(input.email),referralId:'race',status:'pending'});
  await admin.auth().createUser({uid,email:input.email,password});
 }
 const results=await Promise.allSettled(inputs.map((input,i)=>call(input,'10.10.0.'+(i+1))));
 assert.equal(results.filter(x=>x.status==='fulfilled').length,1);
 const failure=results.find(x=>x.status==='rejected').reason;
 assert.equal(failure.code,'already-exists');
 assert.deepEqual(failure.details,{reason:'referral_unavailable',accountCreated:true});
 for(const input of inputs) assert.ok(await admin.auth().getUser('ref_'+hash(input.requestId).slice(0,48)));
 assert.equal((await db.doc('reward_events/race').get()).exists,true);
});
test('pending invitations do not expire and Paris midnight respects daylight saving',async()=>{
 // Invitations never expire: no expiry job exists any more.
 assert.equal(require('../lib/share_promo').expireOldReferrals,undefined);
 await db.doc('referrals/pending-old').set({inviterUid:'x',inviteCode:'OLD',status:'pending',createdAt:admin.firestore.Timestamp.fromDate(new Date('2020-01-01T00:00:00Z'))});
 assert.equal((await db.doc('referrals/pending-old').get()).data().status,'pending');
 const midnight=require('../lib/share_promo/firestore').getNextMidnightTimestamp;
 for(const [input,expected] of [['2026-03-28T23:30:00Z','2026-03-29T22:00:00.000Z'],['2026-10-24T22:30:00Z','2026-10-25T23:00:00.000Z']])
  assert.equal(midnight(admin.firestore.Timestamp.fromDate(new Date(input))).toDate().toISOString(),expected);
});

test('per-invitation limit applies across network addresses',async()=>{
 await db.doc('referrals/throttle').set({inviterUid:'inviter',inviteCode:'THROTTLE',status:'pending',rewardStatus:'not_earned',metadata:{}});
 const existingEmail='throttle@example.test';
 await admin.auth().createUser({email:existingEmail,password});
 for(let i=0;i<10;i++) await assert.rejects(call({...data('irrelevant','THROTTLE'),email:existingEmail},'10.20.0.'+(i+1)),{code:'already-exists'});
 await assert.rejects(call({...data('irrelevant','THROTTLE'),email:existingEmail},'10.20.0.11'),{code:'resource-exhausted'});
});

test('over 100 previous rewards do not prevent invitation, signup or special ticket',async()=>{
 const share=require('../lib/share_promo');
 const create=ft.wrap(share.createReferral), inviter='unlimited-inviter';
 await db.doc('users/'+inviter).set({user_role:'joueur',remaining_part:4});
 await db.doc('users/'+inviter+'/private/share_state').set({grantedCount:101});
 const batch=db.batch();
 for(let i=0;i<101;i++) batch.set(db.doc('referrals/old-unlimited-'+i),{inviterUid:inviter,inviteeUid:'past-'+i,status:'accepted',rewardStatus:'granted',createdAt:admin.firestore.Timestamp.now()});
 await batch.commit();
 const previousGame=await db.doc('referral_games/special').get();
 if(previousGame.exists) await previousGame.ref.update({status:'ended'});
 const now=Date.now();
 await db.doc('referral_games/unlimited').set({status:'active',ticket_count:0,start_date:admin.firestore.Timestamp.fromMillis(now-60000),end_date:admin.firestore.Timestamp.fromMillis(now+60000)});
 const invitation=await create({shareChannel:'test'},{auth:{uid:inviter,token:{}}});
 const input=data('unlimited-new',invitation.inviteCode);
 await call(input,'10.50.0.1'); await call(input,'10.50.0.2');
 const referral=(await db.doc('referrals/'+invitation.referralId).get()).data();
 const expected=require('../lib/share_promo/firestore').getNextMidnightTimestamp(referral.acceptedAt);
 const user=(await db.doc('users/'+inviter).get()).data();
 // A referral game is running: the ticket replaces the classic reward.
 assert.ok(expected);
 assert.equal(user.allGamesAccessUntil,undefined);
 assert.equal(user.remaining_part,4);
 assert.equal((await db.doc('reward_events/'+invitation.referralId).get()).exists,false);
 assert.equal((await db.doc('referral_reward_pending/'+invitation.referralId).get()).data().status,'granted');
 assert.equal((await db.doc('referral_games/unlimited/entries/'+invitation.referralId).get()).exists,true);
 assert.equal((await db.doc('referral_games/unlimited').get()).data().ticket_count,1);
 const inviteeProfile=(await db.doc('users/'+referral.inviteeUid).get()).data();
 assert.equal(inviteeProfile.user_role,'joueur');
 assert.equal(inviteeProfile.allGamesAccessUntil,undefined);

 // Simulate interruption before the worker, including an old quota-blocked
 // record, then run the scheduled retry twice.
 const acceptedAt=admin.firestore.Timestamp.now();
 await db.doc('referrals/queued-over-limit').set({inviterUid:inviter,inviteeUid:'queued-new-player',status:'accepted',rewardStatus:'blocked',rewardType:'all_games_until_midnight',rewardValue:1,acceptedAt,metadata:{playerRewardRuleVersion:2,blockReason:'max_rewards_per_user_reached'}});
 await db.doc('referral_reward_pending/queued-over-limit').set({referral_id:'queued-over-limit',inviter_uid:inviter,accepted_at:acceptedAt,game_id:'unlimited',mode:'game',classic_and_game:true,status:'pending'});
 const retry=ft.wrap(share.retryReferralRewards);
 await retry({}); await retry({});
 assert.equal((await db.doc('referrals/queued-over-limit').get()).data().rewardStatus,'granted');
 assert.equal((await db.doc('referral_reward_pending/queued-over-limit').get()).data().status,'granted');
 assert.equal((await db.doc('reward_events/queued-over-limit').get()).exists,true);
 assert.equal((await db.doc('referral_games/unlimited/entries/queued-over-limit').get()).exists,true);
 assert.equal((await db.doc('referral_games/unlimited').get()).data().ticket_count,2);
 // An invitee already rewarded cannot be rewarded again through another referral.
 await db.doc('referrals/duplicate-invitee').set({inviterUid:inviter,inviteeUid:'queued-new-player',status:'accepted',rewardStatus:'available',rewardType:'all_games_until_midnight',rewardValue:1,acceptedAt,metadata:{playerRewardRuleVersion:2}});
 const grant=ft.wrap(share.grantReferralReward);
 const result=await grant({referralId:'duplicate-invitee'},{auth:{uid:'admin',token:{admin:true}}});
 assert.equal(result.reason,'invitee_already_rewarded');
 assert.equal((await db.doc('reward_events/duplicate-invitee').get()).exists,false);
});

test('a failed classic component cannot be hidden by a special-game ticket',async()=>{
 const {processReferralReward}=require('../referral_reward_queue');
 await db.doc('referral_reward_pending/failed-classic').set({status:'pending',mode:'game',classic_and_game:true,game_id:'unlimited',inviter_uid:'unlimited-inviter'});
 const result=await processReferralReward('failed-classic',async()=>({granted:false,reason:'inviter_ineligible'}));
 assert.equal(result.status,'manual_review_required');
 assert.equal((await db.doc('referral_reward_pending/failed-classic').get()).data().reason,'inviter_ineligible');
 assert.equal((await db.doc('referral_games/unlimited/entries/failed-classic').get()).exists,false);
});
