const test=require('node:test'); const assert=require('node:assert/strict'); const admin=require('firebase-admin');
if(!process.env.FIRESTORE_EMULATOR_HOST || !String(process.env.GCLOUD_PROJECT||'').startsWith('demo-')) throw Error('demo emulator required');
if(!admin.apps.length) admin.initializeApp({projectId:process.env.GCLOUD_PROJECT});
const db=admin.firestore(); const {searchMerchantPrizeCodesCore,searchMerchantPrizeCodes,syncPrizeSearchCodeCore,getMerchantPrizes}=require('../merchant_prizes');
test('scoped prefix suggestions, historical owners and rate limiting',async()=>{
 const merchant=db.doc('users/merchant'), other=db.doc('users/other'), shop=db.doc('enseignes/shop');
 await shop.set({owner:'merchant'});
 await Promise.all([
 db.doc('prizes/a').set({owner_id:merchant,claim_code:'ABC001',fulfillment_type:'merchant'}),
 db.doc('prizes/b').set({owner_id:'users/merchant',claim_code:'ABC002'}),
 db.doc('prizes/c').set({enseigne_id:shop,claim_code:'ABC003'}),
 db.doc('prizes/d').set({owner_id:other,enseigne_id:shop,claim_code:'ABC004'}),
 db.doc('prizes/e').set({owner_id:merchant,claim_code:'ABC005',claimed:true})]);
 await db.doc('games/game').set({owner_id:merchant,enseigne_id:shop});
 await db.doc('prizes/gameprize').set({owner_id:merchant,game_id:db.doc('games/game'),claim_code:'GAME1'});
 const gamePage=await getMerchantPrizes.run({gameId:'game'}, {auth:{uid:'merchant'}});
 assert.deepEqual(gamePage.ids,['gameprize']);
 await assert.rejects(getMerchantPrizes.run({gameId:'game'}, {auth:{uid:'other'}}),{code:'permission-denied'});
 await assert.rejects(searchMerchantPrizeCodes.run({prefix:'ABC'},{}),{code:'unauthenticated'});
 await assert.rejects(searchMerchantPrizeCodesCore('merchant','AB'),{code:'invalid-argument'});
 await Promise.all(Array.from({length:8},(_,i)=>db.doc('prizes/cap'+i).set({owner_id:merchant,claim_code:'ZZZ00'+i})));
 await Promise.all(Array.from({length:55},(_,i)=>db.doc('prizes/invalid'+i).set({owner_id:merchant,claim_code:'LONG'+String(i).padStart(3,'0'),claimed:true})));
 await db.doc('prizes/after').set({owner_id:merchant,claim_code:'LONG999'});
 for(const doc of (await db.collection('prizes').get()).docs) await syncPrizeSearchCodeCore(doc.ref);
 const result=await searchMerchantPrizeCodesCore('merchant','abc');
 assert.deepEqual(new Set(result.ids),new Set(['a','b','c','e'])); // e is claimed: listed last, flagged by the app
 assert.equal((await searchMerchantPrizeCodesCore('merchant','ZZZ')).ids.length,5);
 // Pagination still reaches the only unclaimed code behind 55 claimed ones; claimed codes follow it.
 const long=(await searchMerchantPrizeCodesCore('merchant','LONG')).ids;
 assert.equal(long[0],'after');
 assert.ok(long.slice(1).every(id=>id.startsWith('invalid')));
 await db.doc('prizes/historical').set({owner_id:merchant,claim_code:'q-r 123'});
 await syncPrizeSearchCodeCore(db.doc('prizes/historical'));
 assert.deepEqual((await searchMerchantPrizeCodesCore('merchant','q-r 1')).ids,['historical']);
 assert.equal((await searchMerchantPrizeCodesCore('other','ABC')).ids.includes('a'),false);
 const {kMerchantPrizeRateLimits}=require('../merchant_prizes');
 // Budget already used within the current minute (independent of how fast
 // the emulator answers).
 await db.doc('_merchant_prize_search_rate/merchant').set({start:Date.now(),count:kMerchantPrizeRateLimits.search});
 await assert.rejects(searchMerchantPrizeCodesCore('merchant','ABC'),{code:'resource-exhausted'});
 // Searching has its own budget: verifying a code ("Vérifier") is not blocked.
 await getMerchantPrizes.run({}, {auth:{uid:'merchant'}});
});
