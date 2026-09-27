const admin=require('firebase-admin');
const functions=require('firebase-functions');
const {emailValid}=require('./prize_fulfillment');
const {loadGameWinners}=require('./game_winner_rows');
const {winnersPdf}=require('./partner_winners_pdf');
const crypto=require('crypto');
const WINDOW=5*60*1000;
const SENDING_REVIEW_AFTER_MS=15*60*1000;

async function queuePartnerPrize(prizeId,{now=Date.now()}={}) {
  const db=admin.firestore();
  return db.runTransaction(async tx=>{
    const prizeRef=db.doc('prizes/'+prizeId), receipt=db.doc('_partner_delivery_receipts/'+prizeId);
    const [snap,existing]=await Promise.all([tx.get(prizeRef),tx.get(receipt)]);
    if(existing.exists) return existing.data().job_id;
    const p=snap.data();
    // Only prizes explicitly stamped by the post-activation award writers may
    // enter this delivery system.  Historic partner prizes are never backfilled
    // into email work merely because this Function is deployed.
    if(!p || p.partner_delivery_eligible!==true || p.fulfillment_type!=='partner' || p.owner_id!=null ||
      !/^games\/[^/]+$/.test(p.game_id?.path||'') ||
      !/^enseignes\/[^/]+$/.test(p.partner_ref?.path||'') ||
      p.partner_ref.path!==p.enseigne_id?.path) return null;
    const shop=await tx.get(p.partner_ref);
    if(!shop.exists || shop.data().managed_by_admin!==true || shop.data().owner_id!=null || shop.data().owner!=null ||
      !emailValid(shop.data().email)) throw Error('Partner recipient requires admin review');
    const bucket=p.prize_type==='principal' ? 'main_'+prizeId : 'instant_'+Math.floor(now/WINDOW);
    const jobId=p.game_id.id+'_'+bucket, jobRef=db.doc('_partner_delivery_jobs/'+jobId);
    const job=await tx.get(jobRef);
    if(job.exists && job.data().status!=='pending') throw Error('Delivery window already closed');
    const email=shop.data().email.trim().toLowerCase();
    if(job.exists && job.data().recipient!==email) throw Error('Partner recipient changed during window');
    if(!job.exists) tx.create(jobRef,{status:'pending',game_ref:p.game_id,shop_ref:p.partner_ref,recipient:email,
      send_after:admin.firestore.Timestamp.fromMillis(p.prize_type==='principal'?now:(Math.floor(now/WINDOW)+1)*WINDOW),
      created_at:admin.firestore.Timestamp.fromMillis(now)});
    tx.create(jobRef.collection('items').doc(prizeId),{prize_id:prizeRef});
    tx.create(receipt,{job_id:jobId});
    return jobId;
  });
}

async function dispatchPartnerJob(jobId,{now=Date.now(),send}={}) {
  // Tests must inject a fake transport. No emulator run can send a real email.
  if(process.env.FIRESTORE_EMULATOR_HOST && !send) throw Error('Emulator mail transport must be simulated');
  const db=admin.firestore(),ref=db.doc('_partner_delivery_jobs/'+jobId);
  const job=(await ref.get()).data();
  if(!job || job.status!=='pending' || job.send_after.toMillis()>now) return {status:'not_due'};
  const [shop,game,items]=await Promise.all([job.shop_ref.get(),job.game_ref.get(),ref.collection('items').get()]);
  if(!game.exists || !shop.exists || shop.data().managed_by_admin!==true || shop.data().owner_id!=null ||
      shop.data().owner!=null || String(shop.data().email||'').trim().toLowerCase()!==job.recipient) {
    await ref.update({status:'review',reason:'recipient_or_shop_changed'}); return {status:'review'};
  }
  const entries=await loadGameWinners(db,job.game_ref,{prizeIds:items.docs.map(d=>d.id),fulfillmentType:'partner'});
  if(entries.length!==items.size || entries.some(e=>e.prize.partner_ref?.path!==job.shop_ref.path ||
      !e.row.code_gagnant || e.prize.owner_id!=null)) {
    await ref.update({status:'review',reason:'award_changed'}); return {status:'review'};
  }
  const attachment=await winnersPdf({gameName:game.data().name,shopName:shop.data().name,entries});
  // Freeze recipient and state in the transaction immediately before SMTP.
  const locked=await db.runTransaction(async tx=>{
    const [fresh,currentShop]=await Promise.all([tx.get(ref),tx.get(job.shop_ref)]);
    if(fresh.data()?.status!=='pending' || currentShop.updateTime.toMillis()!==shop.updateTime.toMillis()) return false;
    tx.update(ref,{status:'sending',started_at:admin.firestore.Timestamp.fromMillis(now),
      send_attempts:admin.firestore.FieldValue.increment(1)}); return true;
  });
  if(!locked) return {status:'already_processing'};
  const messageId=`<partner-${crypto.createHash('sha256').update(jobId).digest('hex')}@proxiplay.fr>`;
  try {
    await (send||require('./lib/notifications/email_sender').sendTextEmail)({to:job.recipient,
      subject:`ProxiPlay - Lots à remettre : ${String(game.data().name||'Jeu').replace(/[\r\n]/g,' ')}`,
      text:'Des joueurs ont gagné un lot à retirer auprès de votre établissement. La liste confidentielle est jointe. Comparez le code exact présenté dans l’application et cochez votre liste après remise. En cas de doute ou pour enregistrer la remise dans ProxiPlay, contactez votre interlocuteur ProxiPlay. Ne transmettez pas cette liste.',
      attachments:[{filename:'proxiplay-lots-a-remettre.pdf',content:attachment,contentType:'application/pdf'}],messageId});
    await ref.update({status:'sent',sent_at:admin.firestore.Timestamp.now(),row_count:entries.length});
    return {status:'sent'};
  } catch(error) {
    // SMTP has no exactly-once guarantee. Never blindly resend after an
    // ambiguous acknowledgement; leave an explicit manual-review record.
    await ref.update({status:'review',reason:'smtp_result_uncertain'});
    throw error;
  }
}

exports.queuePartnerPrize=queuePartnerPrize;
exports.dispatchPartnerJob=dispatchPartnerJob;
async function recoverUnqueuedPartnerPrizes({limit=100}={}) {
  const db=admin.firestore();
  const stateRef=db.doc('_partner_delivery_recovery/state');
  const state=await stateRef.get();
  const cursor=state.exists ? state.get('cursor') : null;
  const baseQuery=db.collection('prizes').where('partner_delivery_eligible','==',true)
    .orderBy(admin.firestore.FieldPath.documentId()).limit(limit);
  // Rotate through the collection: otherwise a completed first page would
  // permanently hide a later prize whose onCreate trigger failed early.
  let prizes=cursor ? await baseQuery.startAfter(cursor).get() : await baseQuery.get();
  if(prizes.empty && cursor) prizes=await baseQuery.get();
  const results=await Promise.allSettled(prizes.docs.map(async prize=>{
    const receipt=await db.doc('_partner_delivery_receipts/'+prize.id).get();
    if(!receipt.exists) return queuePartnerPrize(prize.id);
    return null;
  }));
  if(results.some(result=>result.status==='rejected')) throw Error('Partner delivery recovery requires retry');
  await stateRef.set({
    cursor:prizes.empty ? '' : prizes.docs[prizes.docs.length-1].id,
    updated_at:admin.firestore.FieldValue.serverTimestamp(),
  },{merge:true});
}

exports.notifyPartnerPrize=functions.runWith({failurePolicy:true}).firestore.document('prizes/{prizeId}').onCreate(async(_,ctx)=>{
  const id=await queuePartnerPrize(ctx.params.prizeId);
  if(id && id.includes('_main_')) await dispatchPartnerJob(id);
});
async function reviewStaleSendingPartnerJobs({now=Date.now(),limit=100}={}) {
  const db=admin.firestore();
  const cutoff=admin.firestore.Timestamp.fromMillis(now-SENDING_REVIEW_AFTER_MS);
  const stale=await db.collection('_partner_delivery_jobs').where('status','==','sending')
    .where('started_at','<=',cutoff).orderBy('started_at').limit(limit).get();
  await Promise.all(stale.docs.map(async job=>{
    await job.ref.update({status:'review',reason:'sending_timeout_smtp_unknown',
      review_at:admin.firestore.Timestamp.fromMillis(now)});
    functions.logger.error('PARTNER_DELIVERY_REVIEW',{jobId:job.id,reason:'sending_timeout_smtp_unknown'});
  }));
  return stale.size;
}
exports.deliverPartnerPrizeDigests=functions.pubsub.schedule('every 5 minutes').onRun(async()=>{
  const now=Date.now();
  await recoverUnqueuedPartnerPrizes();
  await reviewStaleSendingPartnerJobs({now});
  const jobs=await admin.firestore().collection('_partner_delivery_jobs').where('status','==','pending')
    .where('send_after','<=',admin.firestore.Timestamp.fromMillis(now)).orderBy('send_after').limit(100).get();
  const results=await Promise.allSettled(jobs.docs.map(d=>dispatchPartnerJob(d.id,{now})));
  if(results.some(r=>r.status==='rejected')) throw Error('Partner delivery requires review');
});
exports.recoverUnqueuedPartnerPrizes=recoverUnqueuedPartnerPrizes;
exports.reviewStaleSendingPartnerJobs=reviewStaleSendingPartnerJobs;
