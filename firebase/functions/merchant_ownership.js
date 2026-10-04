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
  // owner_id identifie le RESPONSABLE DE LA REMISE, jamais seulement
  // l'enseigne hote. Pour 'partner' comme pour 'platform', ce n'est jamais
  // le marchand : le partenaire externe (email, hors Firestore) ou la
  // plateforme (admin) remettent le lot, meme quand l'enseigne du jeu a un
  // proprietaire par ailleurs. Avant ce correctif, seul 'partner' etait
  // structurellement protege (prizeFulfillment() interdit cette valeur des
  // qu'un proprietaire existe) ; 'platform' n'avait pas cette garde et
  // heritait quand meme de owner_id == marchand, permettant a ce dernier de
  // lire le prize complet (claim_code inclus) via les chemins qui prouvent
  // la propriete (Rules get/list, ownsPrize()/getMerchantPrizes).
  // enseigne_id (trace de "dans quelle boutique le jeu a eu lieu") reste
  // ecrit separement par chaque appelant, hors de cette fonction : ne pas
  // le confondre avec le responsable de remise.
  return {owner_id: (fulfillmentType === 'merchant' && ownership.ownerPath) ? db.doc(ownership.ownerPath) : null,
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
  // Meme garde-fou que isMerchantPrize() cote firestore.rules (prizes/{id}
  // allow get/list) : gamePrizeOwnership() pose owner_id des que l'enseigne
  // a un proprietaire, quel que soit le fulfillment_type -- un lot
  // partner/platform peut donc porter owner_id == ce marchand sans qu'il
  // ait a le remettre. Sans ce filtre ici, getMerchantPrizes renvoyait des
  // ids que le client ne pouvait de toute facon plus lire (regle resserree),
  // et loadMerchantPrizes() (Future.wait sur des .get() individuels)
  // echouait entierement a la premiere permission-denied au lieu de
  // simplement omettre ce lot.
  const fulfillment = Object.prototype.hasOwnProperty.call(prize, 'fulfillment_type')
    ? prize.fulfillment_type : 'merchant';
  if (fulfillment !== 'merchant') return false;
  // An explicit merchant owner retains read access even for operator delivery.
  if(prize.owner_id!=null) return userPath(prize.owner_id)==='users/'+uid;
  return shopPaths.has(prize.enseigne_id?.path);
}
module.exports={userPath,shopOwnerPath,shopOwnerRef,ownedShops,ownsPrize,gameOwnership,gamePrizeOwnership};
