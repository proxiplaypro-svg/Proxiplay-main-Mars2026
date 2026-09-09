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
async function ownedShops(db,uid){
  const ref=db.doc('users/'+uid);
  const snapshots=await Promise.all(['owner','owner_id'].flatMap(field=>
    [ref,uid,'users/'+uid,'/users/'+uid].map(value=>db.collection('enseignes').where(field,'==',value).get())));
  return [...new Map(snapshots.flatMap(s=>s.docs).map(d=>[d.id,d])).values()]
    .filter(d=>shopOwnerPath(d.data())===ref.path);
}
function ownsPrize(prize,uid,shopPaths){
  if(prize.owner_id!=null) return userPath(prize.owner_id)==='users/'+uid;
  return shopPaths.has(prize.enseigne_id?.path);
}
module.exports={userPath,shopOwnerPath,shopOwnerRef,ownedShops,ownsPrize};
