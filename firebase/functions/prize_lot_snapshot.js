const admin=require('firebase-admin');
const functions=require('firebase-functions');
const fields=['name','description','claim_code','claimed','usage_deadline','win_date',
  'winner_id','game_id','enseigne_id','owner_id','enseigne_name','prize_type','fulfillment_type'];
function lotSnapshot(prize){
  return Object.fromEntries(fields.filter(k=>prize[k]!==undefined).map(k=>[k,prize[k]]));
}
// Does not recreate a player-deleted my_lots entry. Reads current prize state so
// delayed trigger delivery cannot restore stale claim or expiration information.
async function syncLotSnapshot(prizeId){
  const db=admin.firestore();
  return db.runTransaction(async tx=>{
    const ref=db.doc(`prizes/${prizeId}`); const prize=await tx.get(ref);
    const links=await tx.get(db.collectionGroup('my_lots').where('prize_id','==',ref));
    if(links.size>450) throw Error('Too many prize links; manual review required');
    for(const link of links.docs){
      if(!prize.exists) {tx.update(link.ref,{prize_deleted:true});continue;}
      if(link.ref.parent.parent.path!==prize.data().winner_id?.path){
        functions.logger.error('AWARD_MANUAL_REVIEW_REQUIRED',{prizeId,reason:'my_lot_wrong_owner'});continue;
      }
      tx.update(link.ref,{prize_snapshot:lotSnapshot(prize.data()),prize_deleted:false});
    }
  });
}
exports.lotSnapshot=lotSnapshot;
exports.syncLotSnapshot=syncLotSnapshot;
exports.syncPrizeLotSnapshot=functions.firestore.document('prizes/{prizeId}').onWrite((_change,context)=>syncLotSnapshot(context.params.prizeId));
