function userPath(value) {
  if(value && typeof value.path==='string') return /^users\/[^/]+$/.test(value.path)?value.path:'';
  if(typeof value!=='string'||!value) return '';
  const cleaned=value.replace(/^\//,'');
  return /^users\/[^/]+$/.test(cleaned)?cleaned:/^[^/]+$/.test(cleaned)?'users/'+cleaned:'';
}
function shopOwnerPath(data={}) {
  const primary=data.owner_id==null?'':userPath(data.owner_id);
  const legacy=data.owner==null?'':userPath(data.owner);
  if(data.owner_id!=null&&!primary || data.owner!=null&&!legacy || primary&&legacy&&primary!==legacy) return '';
  return primary||legacy;
}
function shopOwnerRef(db,data){const path=shopOwnerPath(data);return path?db.doc(path):null;}
// Only the protected enseigne flag can authorize ownerless operation. A flag
// on the game is never trusted. Existing, malformed or conflicting identities
// must not be hidden by switching management mode.
function gameOwnership(game = {}, shop = {}) {
  const owner = shopOwnerPath(shop);
  if (shop.managed_by_admin === true && shop.owner_id == null && shop.owner == null) {
    return game.owner_id == null
      ? {valid: true, ownerPath: ''}
      : {valid: false};
  }
  const explicit = game.owner_id == null ? owner : userPath(game.owner_id);
  return owner && explicit === owner
    ? {valid: true, ownerPath: owner}
    : {valid: false};
}
function gamePrizeOwnership(db, ownership, shopRef, fulfillmentType) {
  return {owner_id: ownership.ownerPath ? db.doc(ownership.ownerPath) : null,
    fulfillment_type: fulfillmentType,
    ...(fulfillmentType === 'partner' ? {partner_ref: shopRef} : {})};
}
async function ownedShops(db,uid){
  const ref=db.doc('users/'+uid);
  const snapshots=await Promise.all(['owner','owner_id'].flatMap(field=>
    [ref,uid,'users/'+uid,'/users/'+uid].map(value=>db.collection('enseignes').where(field,'==',value).get())));
  return [...new Map(snapshots.flatMap(s=>s.docs).map(d=>[d.id,d])).values()]
    .filter(d=>shopOwnerPath(d.data())===ref.path);
}
function ownsPrize(prize,uid,shopPaths){
  // An explicit merchant owner retains read access even for operator delivery.
  if(prize.owner_id!=null) return userPath(prize.owner_id)==='users/'+uid;
  return shopPaths.has(prize.enseigne_id?.path);
}
module.exports={userPath,shopOwnerPath,shopOwnerRef,ownedShops,ownsPrize,gameOwnership,gamePrizeOwnership};
