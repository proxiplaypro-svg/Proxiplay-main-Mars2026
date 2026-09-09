const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
let env;
test.before(async () => {
  env = await initializeTestEnvironment({projectId:'demo-proxiplay-public-security', firestore:{host:'127.0.0.1',port:8080,rules:fs.readFileSync(require('path').resolve(__dirname,'../../firestore.rules'),'utf8')}});
  await env.withSecurityRulesDisabled(async ctx => {
    const db=ctx.firestore();
    await db.doc('users/owner').set({user_role:'commercant'});
    await db.doc('merchants/shop').set({owner_id:db.doc('users/owner'),email:'owner@example.test',name:'Shop'});
    await db.doc('jeux/game').set({merchant_id:'shop'});
    await db.doc('animations/a/winner/current').set({email:'private@example.test',uid:'owner'});
    await db.doc('animations/a/public_winner/current').set({label:'Alice',city:'Paris'});
    await db.doc('public_prize_winners/p').set({winnerFirstName:'Alice'});
  });
});
test.after(async()=>env?.cleanup());

test('platform prizes cannot be claimed by a merchant even with legacy owner fields',async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await db.doc('prizes/platform').set({winner_id:db.doc('users/player'),owner_id:db.doc('users/owner'),
      prize_type:'animation',fulfillment_type:'platform',claimed:false});
    await db.doc('games/admin_created').set({create_by:db.doc('users/admin'),enseigne_id:db.doc('enseignes/shop'),owner_id:db.doc('users/owner')});
    await db.doc('enseignes/shop').set({owner:db.doc('users/owner')});
  });
  await assertFails(env.authenticatedContext('owner').firestore().doc('prizes/platform').update({claimed:true}));
  await assertSucceeds(env.authenticatedContext('owner').firestore().doc('games/admin_created').update({hidden_from_merchant_stats:true}));
  await assertFails(env.authenticatedContext('attacker').firestore().doc('games/admin_created').update({hidden_from_merchant_stats:true}));
});
test('public can read projections, never private winner; player cannot write either projection', async()=>{
  const db=env.unauthenticatedContext().firestore();
  await assertSucceeds(db.doc('animations/a/public_winner/current').get());
  await assertSucceeds(db.doc('public_prize_winners/p').get());
  await assertFails(db.doc('animations/a/winner/current').get());
  const player=env.authenticatedContext('attacker').firestore();
  await assertFails(player.doc('animations/a/public_winner/current').set({label:'Fake'}));
  await assertFails(player.doc('public_prize_winners/p').set({winnerFirstName:'Fake'}));
});
test('player cannot forge ownership with an email or a merchant document',async()=>{
  const db=env.authenticatedContext('attacker',{email:'owner@example.test'}).firestore();
  await assertFails(db.doc('merchants/fake').set({owner_uid:'attacker'}));
  await assertFails(db.doc('merchants/shop').update({owner_uid:'attacker'}));
  await assertFails(db.doc('jeux/game').update({active:true}));
  await assertFails(db.doc('jeux/game').update({merchant_id:'fake'}));
});
test('provisioned owner can edit allowed merchant fields but not ownership',async()=>{
  const db=env.authenticatedContext('owner').firestore();
  await assertSucceeds(db.doc('merchants/shop').update({name:'Updated'}));
  await assertFails(db.doc('merchants/shop').update({owner_id:db.doc('users/attacker')}));
  await assertSucceeds(db.doc('jeux/game').update({active:true}));
});
