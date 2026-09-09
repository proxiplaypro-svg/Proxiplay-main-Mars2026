const admin=require('firebase-admin');
const functions=require('firebase-functions');
const {ownedShops,ownsPrize,userPath}=require('./merchant_ownership');
const db=admin.firestore();
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
  const size=Math.max(1,Math.min(100,Math.floor(Number(pageSize)||40)));
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
exports.getMerchantPrizes=functions.region('europe-west1').https.onCall((data,context)=>{
  if(!context.auth) throw new functions.https.HttpsError('unauthenticated','Authentication required');
  return merchantPrizesPage(context.auth.uid,data||{});
});
