// Deployment gate: exercise real list queries as well as document permissions.
// Both rule files must preserve legitimate merchant operations. Only strict
// rules promise prize read confidentiality during/after coexistence.
const {describe,it,before,after,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');

for(const mode of ['strict','transitional']) describe(`rollout merchant business access: ${mode}`,()=>{
  let env;
  const context=uid=>env.authenticatedContext(uid).firestore();
  before(async()=>{
    env=await initializeTestEnvironment({projectId:`demo-proxiplay-rollout-${mode}`,
      firestore:{host:'127.0.0.1',port:8080,rules:fs.readFileSync(path.resolve(__dirname,
        mode==='strict'?'../../firestore.rules':'../../firestore.legacy-prizes.rules'),'utf8')}});
  });
  after(async()=>env?.cleanup());
  beforeEach(async()=>{
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async ctx=>{
      const db=ctx.firestore();
      for(const uid of ['winner','merchant','other','admin']) await db.doc(`users/${uid}`).set({
        user_role:uid==='admin'?'admin':uid==='winner'?'joueur':'commercant',account_status:'approved'});
      await db.doc('enseignes/shop').set({owner:db.doc('users/merchant')});
      await db.doc('games/admin_game').set({create_by:db.doc('users/admin'),
        owner_id:db.doc('users/merchant'),enseigne_id:db.doc('enseignes/shop'),hasWinner:true});
      const prize={winner_id:db.doc('users/winner'),game_id:db.doc('games/admin_game'),
        owner_id:db.doc('users/merchant'),enseigne_id:db.doc('enseignes/shop'),
        prize_type:'principal',fulfillment_type:'merchant',claim_code:'LOCAL_TEST_CODE',claimed:false};
      await db.doc('prizes/modern').set(prize);
      const {fulfillment_type,owner_id,enseigne_id,...historic}=prize;
      await db.doc('prizes/legacy_both').set({...historic,owner_id,enseigne_id});
      await db.doc('prizes/legacy_shop').set({...historic,enseigne_id});
      await db.doc('prizes/legacy_owner').set({...historic,owner_id});
      await db.doc('prizes/legacy_unrouted').set(historic);
      await db.doc('prizes/platform').set({...prize,prize_type:'animation',fulfillment_type:'platform'});
      await db.doc('prizes/expired').set({...prize,usage_deadline:new Date('2000-01-01')});
      await db.doc('prizes/used').set({...prize,claimed:true});
      await db.doc('users/winner/my_lots/modern').set({prize_id:db.doc('prizes/modern')});
    });
  });
  it('1 winner reads own prize and follows own my_lots link',async()=>{
    const db=context('winner');
    const links=await assertSucceeds(db.collection('users/winner/my_lots').get());
    const prize=await assertSucceeds(links.docs[0].data().prize_id.get());
    assert.equal(prize.id,'modern');
    assert.equal(prize.data().claim_code,'LOCAL_TEST_CODE');
  });
  it('2 actual merchant reads won prize of an admin-created game',async()=>{
    const db=context('merchant');
    const prize=await assertSucceeds(db.doc('prizes/modern').get());
    assert.equal(prize.data().owner_id.path,'users/merchant');
  });
  it('3 detail list uses game_id AND owner_id and keeps won prizes visible',async()=>{
    const db=context('merchant');
    const rows=await assertSucceeds(db.collection('prizes').where('game_id','==',db.doc('games/admin_game'))
      .where('owner_id','==',db.doc('users/merchant')).get());
    const ids=rows.docs.map(d=>d.id);
    for(const id of ['modern','legacy_both','legacy_owner']) assert.ok(ids.includes(id));
    assert.equal(ids.includes('legacy_shop'),false,'old owner-only query is incomplete; merchantPrizesPage tests cover the replacement');
  });
  it('3 historical shop prize remains individually readable; unsafe broad shop query fails closed',async()=>{
    await env.withSecurityRulesDisabled(async ctx=>{
      const db=ctx.firestore();
      await db.doc('prizes/conflicting_owner').set({owner_id:db.doc('users/other'),enseigne_id:db.doc('enseignes/shop')});
    });
    const db=context('merchant');
    await assertSucceeds(db.doc('prizes/legacy_shop').get());
    const query=db.collection('prizes').where('enseigne_id','==',db.doc('enseignes/shop')).get();
    if(mode==='strict') await assertFails(query); else await assertSucceeds(query);
  });
  it('4 merchant can claim an available merchant prize, but cannot claim twice',async()=>{
    const ref=context('merchant').doc('prizes/modern');
    await assertSucceeds(ref.update({claimed:true}));
    assert.equal((await ref.get()).data().claimed,true);
    await assertFails(ref.update({claimed:true}));
  });
  it('5 unrelated merchant cannot claim prize or read player my_lots',async()=>{
    const db=context('other');
    await assertFails(db.doc('prizes/modern').update({claimed:true}));
    await assertFails(db.collection('users/winner/my_lots').get());
    if(mode==='strict') {
      await assertFails(db.doc('prizes/modern').get());
      await assertFails(db.collection('prizes').where('owner_id','==',db.doc('users/merchant')).get());
      await assertFails(db.collection('prizes').where('enseigne_id','==',db.doc('enseignes/shop')).get());
    }
  });
  it('6 game created by admin remains readable and hideable by the real owner',async()=>{
    const db=context('merchant');
    const games=await assertSucceeds(db.collection('games').where('owner_id','==',db.doc('users/merchant')).get());
    assert.deepEqual(games.docs.map(d=>d.id),['admin_game']);
    assert.equal((await assertSucceeds(db.doc('games/admin_game').get())).data().create_by.path,'users/admin');
    await assertSucceeds(db.doc('games/admin_game').update({hidden_from_merchant_stats:true}));
    await assertFails(context('other').doc('games/admin_game').update({hidden_from_merchant_stats:true}));
  });
  it('7 legacy no fulfillment/deadline: either trusted owner OR shop permits claim at rules layer',async()=>{
    const db=context('merchant');
    for(const id of ['legacy_both','legacy_owner','legacy_shop']){
      await assertSucceeds(db.doc(`prizes/${id}`).get());
      await assertSucceeds(db.doc(`prizes/${id}`).update({claimed:true}));
    }
  });
  it('7 missing claimed flag means unclaimed, with ownership still required', async()=>{
    await env.withSecurityRulesDisabled(async ctx=>{
      const db=ctx.firestore();
      await db.doc('prizes/legacy_no_claimed').set({owner_id:db.doc('users/merchant')});
    });
    await assertFails(context('other').doc('prizes/legacy_no_claimed').update({claimed:true}));
    await assertSucceeds(context('merchant').doc('prizes/legacy_no_claimed').update({claimed:true}));
  });
  it('7 no owner AND no shop: winner keeps access, merchant needs manual review',async()=>{
    await assertSucceeds(context('winner').doc('prizes/legacy_unrouted').get());
    await assertFails(context('merchant').doc('prizes/legacy_unrouted').update({claimed:true}));
    if(mode==='strict') await assertFails(context('merchant').doc('prizes/legacy_unrouted').get());
  });
  it('expired, used and platform prizes stay protected; admin can handle platform prize',async()=>{
    for(const id of ['expired','used','platform']) await assertFails(context('merchant').doc(`prizes/${id}`).update({claimed:true}));
    await assertSucceeds(context('admin').doc('prizes/platform').update({claimed:true}));
  });
  it('forged owner/winner changes and fabricated my_lots remain denied',async()=>{
    await assertFails(context('merchant').doc('prizes/modern').update({claimed:true,winner_id:context('merchant').doc('users/other')}));
    await assertFails(context('merchant').doc('games/admin_game').update({owner_id:context('merchant').doc('users/other')}));
    await assertFails(context('winner').doc('users/winner/my_lots/fake').set({prize_id:context('winner').doc('prizes/platform')}));
  });
  it('admin legacy string owner supports trusted enseigne fallback',async()=>{
    await env.withSecurityRulesDisabled(async ctx=>{
      const db=ctx.firestore();
      await db.doc('enseignes/shop').update({owner:'/users/merchant',owner_id:db.doc('users/merchant')});
    });
    const db=context('merchant');
    await assertSucceeds(db.doc('prizes/modern').get()); // explicit prize owner still works
    await assertSucceeds(db.doc('prizes/legacy_shop').update({claimed:true}));
    await assertSucceeds(db.doc('games/admin_game').update({hidden_from_merchant_stats:true}));
    await assertSucceeds(db.doc('prizes/legacy_shop').get());
  });
  it('legacy query and anonymous read are explicitly temporary, never proof of strict compatibility',async()=>{
    const query=context('merchant').collection('prizes').where('game_id','==',context('merchant').doc('games/admin_game'));
    const anonymous=env.unauthenticatedContext().firestore().doc('prizes/modern');
    if(mode==='strict'){await assertFails(query.get());await assertFails(anonymous.get());}
    else {await assertSucceeds(query.get());await assertSucceeds(anonymous.get());}
  });
});
