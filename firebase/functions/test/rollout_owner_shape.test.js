process.env.FIRESTORE_EMULATOR_HOST='127.0.0.1:8080';
process.env.GCLOUD_PROJECT='demo-proxiplay-rollout-owner-shape';
const test=require('node:test'),assert=require('node:assert/strict'),admin=require('firebase-admin');
if(!admin.apps.length) admin.initializeApp();
const db=admin.firestore();
const {merchantGamesPage}=require('../merchant_games');
const {drawMainPrize}=require('../main_prize_draw');
test('admin legacy string and canonical owner both preserve legitimate pagination',async()=>{
  for(const c of await db.listCollections()) await db.recursiveDelete(c);
  const owner=db.doc('users/merchant');
  const shop=db.doc('enseignes/shop');
  await shop.set({owner:'/users/merchant',owner_id:owner});
  await db.doc('games/admin_game').set({owner_id:owner,create_by:db.doc('users/admin'),enseigne_id:shop});
  assert.deepEqual((await merchantGamesPage('merchant')).ids,['admin_game']);
  await shop.update({owner}); // Local emulator fixture only
  assert.deepEqual((await merchantGamesPage('merchant')).ids,['admin_game']);
  assert.deepEqual((await merchantGamesPage('other')).ids,[]);
});

test('admin string-owner shop produces a canonical merchant prize and player my_lots link', async()=>{
  const shop=db.doc('enseignes/legacy_draw');
  await shop.set({owner:'/users/merchant'});
  await db.doc('users/winner').set({first_name:'Test'});
  await db.doc('games/draw').set({create_by:db.doc('users/admin'),enseigne_id:shop,
    name:'Lot',hasWinner:false,end_date:admin.firestore.Timestamp.fromMillis(1)});
  await db.doc('games/draw/participants/winner').set({user_id:db.doc('users/winner')});
  const result=await drawMainPrize('draw');
  assert.equal(result.status,'completed');
  const prize=await db.doc('prizes/'+result.prizeId).get();
  assert.equal(prize.data().owner_id.path,'users/merchant');
  assert.equal(prize.data().fulfillment_type,'merchant');
  assert.equal((await db.doc('users/winner/my_lots/'+result.prizeId).get()).exists,true);
});

test('contradictory admin ownership requires review without generating a prize', async()=>{
  await db.doc('enseignes/conflict').set({owner:'/users/other',owner_id:db.doc('users/merchant')});
  await db.doc('games/conflict').set({owner_id:db.doc('users/merchant'),enseigne_id:db.doc('enseignes/conflict'),
    name:'Lot',hasWinner:false,end_date:admin.firestore.Timestamp.fromMillis(1)});
  await db.doc('games/conflict/participants/winner').set({user_id:db.doc('users/winner')});
  const result=await drawMainPrize('conflict');
  assert.notEqual(result.status,'completed');
  assert.equal((await db.collection('prizes').where('game_id','==',db.doc('games/conflict')).get()).empty,true);
});
