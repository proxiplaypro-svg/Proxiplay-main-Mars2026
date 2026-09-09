const admin=require('firebase-admin');
const functions=require('firebase-functions');
const db=admin.firestore();
// create_by is audit metadata. Ownership is explicit owner_id, with enseigne
// fallback only for historical documents that do not have an owner_id.
async function merchantGamesPage(uid,{cursor='',pageSize=20}={}){
  if(typeof cursor!=='string'||cursor.includes('/')) throw new functions.https.HttpsError('invalid-argument','Invalid cursor');
  const size=Math.max(1,Math.min(50,Number(pageSize)||20));
  const user=db.doc(`users/${uid}`);
  const shops=await db.collection('enseignes').where('owner','==',user).get();
  const shopPaths=new Set(shops.docs.map(d=>d.ref.path));
  const queries=[db.collection('games').where('owner_id','==',user), db.collection('games').where('owner_id','==',uid)];
  for(const shop of shops.docs) for(const field of ['enseigne_id','enseigne_ref']) queries.push(db.collection('games').where(field,'==',shop.ref));
  const pages=await Promise.all(queries.map(q=>{
    q=q.orderBy(admin.firestore.FieldPath.documentId()).limit(size+1);
    return (cursor?q.startAfter(cursor):q).get();
  }));
  const docs=[...new Map(pages.flatMap(p=>p.docs).map(d=>[d.id,d])).values()].sort((a,b)=>a.id<b.id?-1:a.id>b.id?1:0);
  // Cursor advances over examined records, including contradictory historic ones.
  // Never skip unexamined records from another query branch.
  const examined=docs.slice(0,size);
  const ids=examined.filter(d=>{
    const g=d.data(); const owner=g.owner_id?.path||g.owner_id;
    const shop=g.enseigne_id?.path||g.enseigne_ref?.path;
    return owner ? (owner===uid||owner===user.path) && (!shop || shopPaths.has(shop)) : shopPaths.has(shop);
  }).map(d=>d.id);
  return {ids,cursor:examined.at(-1)?.id||cursor,hasMore:docs.length>size};
}
exports.merchantGamesPage=merchantGamesPage;
exports.getMerchantGames=functions.region('europe-west1').https.onCall(async(data,context)=>{
  if(!context.auth) throw new functions.https.HttpsError('unauthenticated','Authentication required');
  return merchantGamesPage(context.auth.uid,data||{});
});
