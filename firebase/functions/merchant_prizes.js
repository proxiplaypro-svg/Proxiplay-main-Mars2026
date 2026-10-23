const admin=require('firebase-admin');
const functions=require('firebase-functions');
const {ownedShops,ownsPrize,userPath}=require('./merchant_ownership');
const db=admin.firestore();
// Per-merchant budgets, each in its own one-minute window:
// - search: one call per keystroke of the winning-code autocomplete;
// - listing: one per started prize listing ("Vérifier", a game's lots),
//   whatever its number of pages, so a merchant with many lots can verify
//   codes in a row;
// - pages: every page of every listing, a ceiling against bulk scraping.
const kMerchantPrizeRateLimits = {search: 60, listing: 30, pages: 600};
async function enforceMerchantPrizeRate(uid, kind) {
  const limit = kMerchantPrizeRateLimits[kind];
  const collection = kind === 'search' ? '_merchant_prize_search_rate' : `_merchant_prize_${kind}_rate`;
  const now=Date.now(), ref=db.collection(collection).doc(uid);
  await db.runTransaction(async tx=>{
    const previous=(await tx.get(ref)).data()||{};
    const start=Number(previous.start)||0;
    const count=now>=start&&now-start<60000?Number(previous.count)||0:0;
    if(count>=limit) throw new functions.https.HttpsError('resource-exhausted','Too many prize requests');
    tx.set(ref,{start:count?start:now,count:count+1});
  });
}
exports.kMerchantPrizeRateLimits = kMerchantPrizeRateLimits;

// Server pagination is necessary: a client enseigne query cannot prove the
// absence of owner_id on historical documents while denying conflicting owners.
async function merchantPrizesPage(uid,{gameId='',cursor='',pageSize=40}={}) {
  if([gameId,cursor].some(v=>typeof v!=='string'||v.includes('/'))) throw new functions.https.HttpsError('invalid-argument','Invalid cursor or game');
  const shops=await ownedShops(db,uid), paths=new Set(shops.map(s=>s.ref.path));
  const owner=db.doc('users/'+uid);
  if(gameId){
    const game=await db.doc('games/'+gameId).get(); const g=game.data()||{};
    const shop=(g.enseigne_id||g.enseigne_ref)?.path;
    if(!game.exists || (g.owner_id!=null
      ? userPath(g.owner_id)!==owner.path || (shop && !paths.has(shop))
      : !paths.has(shop)))
      throw new functions.https.HttpsError('permission-denied','Game does not belong to merchant');
  }
  const size=Math.max(1,Math.min(40,Math.floor(Number(pageSize)||40)));
  // For a game, its bounded query avoids any cross-game private data response.
  const queries=gameId?[db.collection('prizes').where('game_id','==',db.doc('games/'+gameId))]:[
    ...[owner,uid,'users/'+uid,'/users/'+uid].map(v=>db.collection('prizes').where('owner_id','==',v)),
    ...shops.map(s=>db.collection('prizes').where('enseigne_id','==',s.ref))];
  const pages=await Promise.all(queries.map(q=>{
    q=q.orderBy(admin.firestore.FieldPath.documentId()).limit(size+1);
    return (cursor?q.startAfter(cursor):q).get();
  }));
  const all=[...new Map(pages.flatMap(p=>p.docs).map(d=>[d.id,d])).values()].sort((a,b)=>a.id<b.id?-1:a.id>b.id?1:0);
  const examined=all.slice(0,size);
  return {ids:examined.filter(d=>ownsPrize(d.data(),uid,paths)).map(d=>d.id),
    cursor:examined.at(-1)?.id||cursor,hasMore:all.length>size};
}
exports.merchantPrizesPage=merchantPrizesPage;
exports.getMerchantPrizes=functions.region('europe-west1').https.onCall(async (data,context)=>{
  if(!context.auth) throw new functions.https.HttpsError('unauthenticated','Authentication required');
  const input=data||{};
  // Only the first page starts a listing; later pages of the same listing
  // only count against the page ceiling.
  if(!input.cursor) await enforceMerchantPrizeRate(context.auth.uid,'listing');
  await enforceMerchantPrizeRate(context.auth.uid,'pages');
  return merchantPrizesPage(context.auth.uid,input);
});

// A prize a merchant can find by its code: delivered by the merchant (never
// platform or partner lots), not expired, attached to an account or a shop.
// Claimed prizes are included so the merchant sees them flagged as already
// collected; they are listed after unclaimed ones. Shared with the backfill
// so exactly these prizes get claim_code_search.
function isSuggestiblePrize(d, now = Date.now()) {
  const kind = d.fulfillment_type;
  // These prize types are ProxiPlay lots unless explicitly collected at a
  // partner shop (e.g. a monthly challenge with a partner merchant).
  const platform = ['animation','referral_game','monthly_challenge'].includes(d.prize_type) &&
    kind !== 'merchant';
  const deadline = d.usage_deadline?.toMillis?.();
  return !platform && (kind == null || kind === 'merchant') &&
    (deadline == null || deadline >= now) && (d.owner_id != null || d.enseigne_id != null);
}
exports.isSuggestiblePrize = isSuggestiblePrize;

// Search is bounded and scoped before any prize data is returned.
async function searchMerchantPrizeCodes(uid, input) {
  const prefix = typeof input === 'string' ? input.trim().toUpperCase().replace(/[^A-Z0-9]/g, '') : '';
  if (!/^[A-Z0-9]{3,32}$/.test(prefix))
    throw new functions.https.HttpsError('invalid-argument', 'Invalid prefix');
  const now = Date.now();
  await enforceMerchantPrizeRate(uid, 'search');
  const shops = await ownedShops(db, uid);
  const paths = new Set(shops.map(s => s.ref.path));
  const owner = db.doc('users/' + uid);
  const filters = [
    ...[owner,uid,'users/'+uid,'/users/'+uid].map(value => ['owner_id',value]),
    ...shops.map(shop => ['enseigne_id',shop.ref]),
  ];
  // Unclaimed prizes come first so a claimed one never hides a prize the
  // merchant can still hand over.
  const unclaimed = [], claimed = [];
  const result = () => ({ids: [...unclaimed, ...claimed].slice(0, 5)});
  const add = (doc) => {
    const d = doc.data();
    if (!normalizePrizeSearchCode(d.claim_code).startsWith(prefix) || !ownsPrize(d,uid,paths) ||
        !isSuggestiblePrize(d, now)) return;
    const list = d.claimed === true ? claimed : unclaimed;
    if (!unclaimed.includes(doc.id) && !claimed.includes(doc.id)) list.push(doc.id);
  };
  // Exact code first: works for historical prizes that do not have
  // claim_code_search yet (stored codes are already uppercase alphanumeric),
  // using equality filters only, so no composite index is required.
  for (const [field,value] of filters) {
    const docs = (await db.collection('prizes').where(field,'==',value)
      .where('claim_code','==',prefix).limit(5).get()).docs;
    docs.forEach(add);
    if (unclaimed.length >= 5) return result();
  }
  let scanned = 0;
  for (const [field,value] of filters) {
    let cursor;
    do {
      let query = db.collection('prizes').where(field,'==',value)
        .where('claim_code_search','>=',prefix).where('claim_code_search','<=',prefix+'\uf8ff')
        .orderBy('claim_code_search').orderBy(admin.firestore.FieldPath.documentId()).limit(50);
      if(cursor) query=query.startAfter(cursor);
      let docs;
      try {
        docs = (await query.get()).docs;
      } catch (error) {
        // Prefix index missing or still building: keep exact matches, and
        // report the service as unavailable only when there is nothing.
        if (error?.code !== 9) throw error;
        if (unclaimed.length || claimed.length) return result();
        throw new functions.https.HttpsError('failed-precondition','Prefix search not ready');
      }
      scanned += docs.length;
      docs.forEach(add);
      if (unclaimed.length >= 5) return result();
      if(scanned >= 1000 && docs.length === 50)
        throw new functions.https.HttpsError('resource-exhausted','Search requires a longer prefix');
      cursor=docs.length===50?docs[docs.length-1]:null;
    } while(cursor);
  }
  return result();
}
exports.searchMerchantPrizeCodesCore=searchMerchantPrizeCodes;
exports.searchMerchantPrizeCodes=functions.region('europe-west1').https.onCall((data,context)=>{
  if (!context.auth?.uid) throw new functions.https.HttpsError('unauthenticated','Authentication required');
  return searchMerchantPrizeCodes(context.auth.uid,data?.prefix);
});

function normalizePrizeSearchCode(value) {
  return typeof value === 'string' ? value.trim().toUpperCase().replace(/[^A-Z0-9]/g,'') : '';
}
async function syncPrizeSearchCode(ref) {
  return db.runTransaction(async tx => {
    const snapshot=await tx.get(ref);
    if(!snapshot.exists) return;
    const data=snapshot.data();
    const code=normalizePrizeSearchCode(data.claim_code);
    if((data.claim_code_search || '')===code) return;
    tx.update(ref, {claim_code_search:code || admin.firestore.FieldValue.delete()});
  });
}
exports.syncPrizeSearchCodeCore=syncPrizeSearchCode;
exports.normalizePrizeSearchCode=normalizePrizeSearchCode;
exports.syncPrizeSearchCode=functions.region('europe-west1').firestore.document('prizes/{prizeId}').onWrite((change)=>syncPrizeSearchCode(change.after.ref));
