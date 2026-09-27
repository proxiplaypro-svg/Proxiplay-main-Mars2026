const {test,assert,db,ft,functions,game,instant,participate,time,client,assertFails,assertSucceeds}=require('./lifecycle_helpers.cjs');
const {drawMainPrize}=require('../main_prize_draw');
const {queuePartnerPrize,dispatchPartnerJob,recoverUnqueuedPartnerPrizes,reviewStaleSendingPartnerJobs}=require('../partner_prize_delivery');
const {reserveClaimCode}=require('../claim_code_registry');
const {partnerRows,winnersPdf}=require('../partner_winners_pdf');
const {loadGameWinners}=require('../game_winner_rows');
const {merchantPrizesPage}=require('../merchant_prizes');
const issue=ft.wrap(require('../game_qr_access').issueGameQrAccess);
const claim=ft.wrap(require('../operator_prize_claim').claimOperatorPrize);
const exportWinners=ft.wrap(require('../export_game_participants').exportGameParticipantsCallable);
const cases=[
  {id:'A merchant',owner:true,creator:'merchant',type:'merchant'},
  {id:'A admin',owner:true,creator:'operator',type:'merchant'},
  {id:'B partner',owner:false,creator:'operator',type:'partner'},
  {id:'C ProxiPlay',owner:false,creator:'operator',type:'platform'},
];
async function scenario(c,extra={}) {
  await db.doc('enseignes/shop').set({name:'Club',email:'remise@example.test',
    ...(c.owner?{owner_id:db.doc('users/merchant'),owner:db.doc('users/merchant')}:{managed_by_admin:true})});
  await game('game',{owner_id:c.owner?db.doc('users/merchant'):null,create_by:db.doc('users/'+c.creator),
    fulfillment_type:c.type,...(c.type==='partner'?{partner_delivery_enabled:true}:{}),...extra});
}
async function verify(id,c){
  const p=(await db.doc('prizes/'+id).get()).data();
  assert.equal(p.fulfillment_type,c.type);assert.equal(p.owner_id?.path||null,c.owner?'users/merchant':null);
  assert.equal((await db.doc('users/player/my_lots/'+id).get()).data().prize_id.path,'prizes/'+id);
  await assertSucceeds(client('player').doc('prizes/'+id).get());
  assert.equal((await merchantPrizesPage('merchant')).ids.includes(id),c.owner);
  if(c.owner) await assertSucceeds(client('merchant').doc('prizes/'+id).update({claimed:true}));
  else {
    await assertFails(client('merchant').doc('prizes/'+id).get());
    await assertFails(client('merchant').doc('prizes/'+id).update({claimed:true}));
    const input={prizeId:id,winnerId:'player',code:p.claim_code,requestId:'managed_delivery_retry'};
    await assert.rejects(claim(input,{auth:{uid:'merchant'}}),{code:'permission-denied'});
    await assert.rejects(claim({...input,code:'wrong'},{auth:{uid:'operator'}}),{code:'failed-precondition'});
    assert.deepEqual((await Promise.all([claim(input,{auth:{uid:'operator'}}),claim(input,{auth:{uid:'operator'}})]))
      .map(r=>r.status).sort(),['already_claimed','claimed']);
    assert.ok((await db.doc('prizes/'+id).get()).data().claimed_at);
  }
}
for(const c of cases){
  test(c.id+' instant award, replay and legitimate withdrawal',async()=>{
    await scenario(c);await instant();const result=await participate();assert.equal(result.isWin,true);
    assert.equal((await participate()).prize_id,result.prize_id);
    assert.equal((await db.collection('prizes').get()).size,1);
    await verify(result.prize_id.split('/').at(-1),c);
  });
  test(c.id+' main draw preserves owner/creator/delivery',async()=>{
    await scenario(c);await participate();const result=await drawMainPrize('game',{now:time('2026-10-01')});
    assert.equal(result.status,'completed');await verify(result.prizeId,c);
    assert.equal((await drawMainPrize('game',{now:time('2026-10-01')})).status,'already_finalized');
    assert.equal((await db.doc('games/game').get()).data().create_by.path,'users/'+c.creator);
  });
}
test('normal missing owner, contradictions and fake admin owner never bypass checks',async()=>{
  for(const shop of [{},{managed_by_admin:true,owner:'merchant',owner_id:'other'}]){
    await game('game',{owner_id:null,fulfillment_type:'platform'});await db.doc('enseignes/shop').set(shop);
    await assert.rejects(participate(),{code:'failed-precondition'});
  }
  await scenario(cases[2],{owner_id:db.doc('users/operator')});await assert.rejects(participate(),{code:'failed-precondition'});
  assert.equal((await db.collection('prizes').get()).size,0);
});
test('ownerless requires explicit delivery and partner email',async()=>{
  await scenario(cases[2],{fulfillment_type:null});await assert.rejects(participate(),{code:'failed-precondition'});
  await scenario(cases[2]);await db.doc('enseignes/shop').update({email:'invalid'});
  await assert.rejects(participate(),{code:'failed-precondition'});
});
test('per-lot override distinguishes instant partner from principal platform',async()=>{
  await scenario(cases[3],{secondary_prizes:[{name:'Lot',count:1,fulfillment_type:'partner'}]});await instant();
  await db.doc('games/game/instant_winners/instant').update({secondary_prize_index:0});
  const r=await participate();assert.equal((await db.doc(r.prize_id).get()).data().fulfillment_type,'partner');
  const main=await drawMainPrize('game',{now:time('2026-10-01')});
  assert.equal((await db.doc('prizes/'+main.prizeId).get()).data().fulfillment_type,'platform');
});
test('partner main email uses shop contact, minimum PII and PDF, is idempotent',async()=>{
  await scenario(cases[2]);await db.doc('users/player').update({first_name:'Alice',last_name:'Dupont',email:'private@example.test',phone_number:'SECRET'});
  await participate();const r=await drawMainPrize('game',{now:time('2026-10-01')});
  const id=await queuePartnerPrize(r.prizeId,{now:0});assert.equal(await queuePartnerPrize(r.prizeId,{now:0}),id);
  const entries=await loadGameWinners(db,db.doc('games/game'));
  assert.deepEqual(Object.keys(partnerRows(entries)[0]).sort(),['code','prize','status','winner']);
  assert.equal(partnerRows(entries)[0].winner,'Alice D.');assert.equal(partnerRows(entries)[0].status,'À remettre');
  const emails=[];const send=async mail=>emails.push(mail);
  assert.equal((await dispatchPartnerJob(id,{now:0,send})).status,'sent');await dispatchPartnerJob(id,{now:0,send});
  assert.equal(emails.length,1);assert.equal(emails[0].to,'remise@example.test');
  assert.equal(emails[0].attachments[0].content.subarray(0,5).toString(),'%PDF-');
  assert.ok(!emails[0].text.includes('private@example.test'));
  const exported=await exportWinners({gameId:'game'},{auth:{uid:'operator'}});assert.equal(exported.rowCount,1);
  await assert.rejects(exportWinners({gameId:'game'},{auth:{uid:'merchant'}}),{code:'permission-denied'});
});
test('instant emails are grouped, platform emits no partner job, wrong recipient blocks',async()=>{
  await scenario(cases[2]);await instant('game','one');await instant('game','two');
  const one=await participate(),two=await participate('game','other');
  const id=await queuePartnerPrize(one.prize_id.split('/').at(-1),{now:1});
  assert.equal(await queuePartnerPrize(two.prize_id.split('/').at(-1),{now:2}),id);
  const emails=[];const send=async m=>emails.push(m);
  assert.equal((await dispatchPartnerJob(id,{now:2,send})).status,'not_due');
  await dispatchPartnerJob(id,{now:300001,send});assert.equal(emails.length,1);
  assert.equal((await db.doc('_partner_delivery_jobs/'+id).get()).data().row_count,2);
  await db.doc(two.prize_id).update({fulfillment_type:'platform'});
  await db.doc('_partner_delivery_receipts/'+two.prize_id.split('/').at(-1)).delete();
  assert.equal(await queuePartnerPrize(two.prize_id.split('/').at(-1)),null);
});
test('email address change and uncertain SMTP result never cause blind resend',async()=>{
  await scenario(cases[2]);await instant();const r=await participate();const id=await queuePartnerPrize(r.prize_id.split('/').at(-1),{now:0});
  await db.doc('enseignes/shop').update({email:'different@example.test'});
  assert.equal((await dispatchPartnerJob(id,{now:300001,send:async()=>assert.fail('wrong recipient')})).status,'review');
  await db.doc('enseignes/shop').update({email:'remise@example.test'});await db.doc('_partner_delivery_jobs/'+id).update({status:'pending'});
  await assert.rejects(dispatchPartnerJob(id,{now:300001,send:async()=>{throw Error('ambiguous SMTP');}}));
  assert.equal((await dispatchPartnerJob(id,{now:300001,send:async()=>assert.fail('duplicate send')})).status,'not_due');
});
test('stale sending partner jobs enter review and are never resent',async()=>{
  await scenario(cases[2]);await instant();const r=await participate();const id=await queuePartnerPrize(r.prize_id.split('/').at(-1),{now:0});
  await db.doc('_partner_delivery_jobs/'+id).update({status:'sending',started_at:time('2026-09-01')});
  assert.equal(await reviewStaleSendingPartnerJobs({now:time('2026-09-02').toMillis()}),1);
  const job=(await db.doc('_partner_delivery_jobs/'+id).get()).data();
  assert.equal(job.status,'review');assert.equal(job.reason,'sending_timeout_smtp_unknown');assert.ok(job.review_at);
  assert.equal((await dispatchPartnerJob(id,{now:time('2026-09-02').toMillis(),send:async()=>assert.fail('duplicate send')})).status,'not_due');
});
test('PDF paginates a printable minimal roster',async()=>{
  const entries=Array.from({length:50},(_,i)=>({row:{prenom:'Élodie',nom:'Martin',lot_gagne:'Deux billets pour une rencontre sportive',code_gagnant:'CODE'+String(i).padStart(16,'0'),statut:'À retirer'},prize:{claimed:false}}));
  const pdf=await winnersPdf({gameName:'USDK - exemple fictif',shopName:'Club partenaire',entries});
  assert.ok(pdf.length>3000);assert.ok(pdf.toString('latin1').includes('/Type /Page'));
  if(process.env.PDF_QA_OUTPUT) require('fs').writeFileSync(process.env.PDF_QA_OUTPUT,pdf);
});
test('ownerless QR/VIP preserve daily idempotence and require trusted QR',async()=>{
  await scenario(cases[3],{access_mode:'qr_only'});await db.doc('users/player').update({remaining_part:0,allGamesAccessUntil:time('2026-10-01')});
  await assert.rejects(issue({gameId:'game'},{auth:{uid:'merchant'}}),{code:'permission-denied'});
  await assert.rejects(participate(),{code:'failed-precondition'});
  const {token}=await issue({gameId:'game'},{auth:{uid:'operator'}});
  assert.equal((await participate('game','player',{qr_token:token})).alreadyParticipatedToday,false);
  assert.equal((await participate('game','player',{qr_token:token})).alreadyParticipatedToday,true);
  assert.equal((await db.doc('users/player').get()).data().remaining_part,0);
});
test('deleting creator admin preserves enseigne game and merchant access',async()=>{
  await scenario(cases[1]);await ft.wrap(functions.onUserDeleted)({uid:'operator'});
  assert.equal((await db.doc('games/game').get()).exists,true);
  assert.equal((await db.doc('enseignes/shop').get()).exists,true);
  await participate();
});
test('claim code registry rejects forced historical collision and reserves 80-bit codes',async()=>{
  await db.doc('prizes/old').set({claim_code:'COLLIDE1',winner_id:db.doc('users/player')});
  let calls=0;
  const code=await db.runTransaction(tx=>reserveClaimCode(tx,db,{generate:()=>++calls===1?'COLLIDE1':'A'.repeat(20)}));
  assert.equal(code,'A'.repeat(20));assert.equal((await db.doc('_claim_code_registry/'+code).get()).exists,true);
  const codes=[];
  for(let i=0;i<40;i++) codes.push(await db.runTransaction(tx=>reserveClaimCode(tx,db)));
  assert.equal(new Set(codes).size,40);assert.ok(codes.every(code=>/^[A-Z0-9]{20}$/.test(code)));
});
test('legacy participants_details replay reserves no orphan claim code',async()=>{
  await scenario(cases[2]);await instant();
  await db.doc('games/game/participants_details/player').set({last_play:time('2026-09-09'),game_bonus:0,user_id:db.doc('users/player')});
  await participate();
  assert.equal((await db.collection('_claim_code_registry').get()).size,0);
  assert.equal((await db.collection('prizes').get()).size,0);
});
test('recovering an unqueued partner award creates one recoverable delivery job',async()=>{
  await scenario(cases[2]);await instant();const result=await participate();const id=result.prize_id.split('/').at(-1);
  await recoverUnqueuedPartnerPrizes();const receipt=await db.doc('_partner_delivery_receipts/'+id).get();
  assert.ok(receipt.exists);await recoverUnqueuedPartnerPrizes();
  assert.equal((await db.collection('_partner_delivery_jobs').get()).size,1);
});
test('deleting a canonical owner_id shop removes its games even when an Admin created them',async()=>{
  await db.doc('users/merchant').set({user_role:'commercant'});
  await db.doc('enseignes/canonical').set({owner_id:db.doc('users/merchant')});
  await db.doc('games/canonical').set({enseigne_id:db.doc('enseignes/canonical'),owner_id:db.doc('users/merchant'),create_by:db.doc('users/operator')});
  await ft.wrap(functions.onUserDeleted)({uid:'merchant'});
  assert.equal((await db.doc('enseignes/canonical').get()).exists,false);
  assert.equal((await db.doc('games/canonical').get()).exists,false);
});
test('managed shop and its games survive deletion of an unrelated creator merchant',async()=>{
  await db.doc('users/merchant').set({user_role:'commercant'});
  await db.doc('enseignes/managed-survives').set({managed_by_admin:true,email:'remise@example.test'});
  await db.doc('games/managed-survives').set({enseigne_id:db.doc('enseignes/managed-survives'),owner_id:null,create_by:db.doc('users/merchant'),fulfillment_type:'platform'});
  await ft.wrap(functions.onUserDeleted)({uid:'merchant'});
  assert.equal((await db.doc('enseignes/managed-survives').get()).exists,true);
  assert.equal((await db.doc('games/managed-survives').get()).exists,true);
});
