process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
process.env.GCLOUD_PROJECT='demo-proxiplay-merchant-page';
const test=require('node:test'),assert=require('node:assert/strict'),admin=require('firebase-admin');
if(!admin.apps.length) admin.initializeApp();
const db=admin.firestore(); const {merchantGamesPage}=require('../merchant_games');
test.beforeEach(async()=>{for(const c of await db.listCollections()) await db.recursiveDelete(c);});
test('admin-created, own and legacy enseigne games paginate beyond 15 with no other merchant leakage',async()=>{
 const owner=db.doc('users/m'),shop=db.doc('enseignes/s'); await shop.set({owner});
 await db.doc('enseignes/s2').set({owner});
 for(let i=0;i<37;i++) await db.doc('games/g'+String(i).padStart(2,'0')).set({
  create_by:db.doc(i%2?'users/admin':'users/m'),enseigne_id:i%2?shop:db.doc('enseignes/s2'),
  ...(i%3?{owner_id:owner}:{}), status:['active','scheduled','ended'][i%3]});
 await db.doc('games/x').set({owner_id:db.doc('users/other'),enseigne_id:shop});
 const a=await merchantGamesPage('m'),b=await merchantGamesPage('m',{cursor:a.cursor});
 assert.equal(a.ids.length,20); assert.equal(a.hasMore,true);
 assert.equal(b.ids.length,17); assert.equal(b.hasMore,false);
 assert.equal(new Set([...a.ids,...b.ids]).size,37);
 assert.deepEqual((await merchantGamesPage('other')).ids,[]);
});
