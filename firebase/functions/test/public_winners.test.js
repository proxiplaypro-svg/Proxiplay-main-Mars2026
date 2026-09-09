process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
process.env.GCLOUD_PROJECT='demo-proxiplay-public-winners';
const test=require('node:test'),assert=require('node:assert/strict'),admin=require('firebase-admin');
if(!admin.apps.length) admin.initializeApp();
const db=admin.firestore();
const {publicWinner,publicPrize,syncPublicPrize,backfillAnimationWinner}=require('../public_winners');
test.beforeEach(async()=>{for(const c of await db.listCollections()) await db.recursiveDelete(c);});
test('public projections whitelist fields and reject contact strings',()=>{
 const user={first_name:'Alice Dupont',city:'Paris',email:'private@example.test',uid:'secret',phone:'0612345678'};
 assert.deepEqual(publicWinner(user),{label:'Alice',city:'Paris',selected_at:null});
 const p=publicPrize({name:'Cadeau',claim_code:'SECRET',winner_id:db.doc('users/u')},user);
 assert.equal(JSON.stringify(p).includes('SECRET'),false);
 assert.equal(publicWinner({first_name:user.email,city:user.phone}).label,'Un joueur');
 assert.equal(publicWinner({city:user.phone}).city,'');
});
test('historic animation backfill dry run, create only, no private data',async()=>{
 await db.doc('users/u').set({first_name:'Alice',email:'secret@example.test'});
 await db.doc('animations/a').set({winner_uid:'u'});
 assert.equal((await backfillAnimationWinner('a')).status,'would_publish');
 const ref=db.doc('animations/a/public_winner/current');
 assert.equal((await ref.get()).exists,false);
 await backfillAnimationWinner('a',{apply:true});
 assert.deepEqual(Object.keys((await ref.get()).data()).sort(),['city','label','selected_at']);
 assert.equal((await backfillAnimationWinner('a',{apply:true})).status,'already_exists');
});
test('prize projection rereads current winner and removes deleted prize',async()=>{
 await db.doc('users/u').set({first_name:'Alice'});
 await db.doc('prizes/p').set({winner_id:db.doc('users/u'),claim_code:'SECRET'});
 await syncPublicPrize('p');
 assert.equal((await db.doc('public_prize_winners/p').get()).data().winnerFirstName,'Alice');
 await db.doc('prizes/p').delete(); await syncPublicPrize('p');
 assert.equal((await db.doc('public_prize_winners/p').get()).exists,false);
});
