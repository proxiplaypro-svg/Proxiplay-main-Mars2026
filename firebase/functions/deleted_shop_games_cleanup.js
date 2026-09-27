const {userPath}=require('./merchant_ownership');

async function deleteDirectChildren(ref, name) {
  const children=await ref.collection(name).get();
  await Promise.all(children.docs.map(doc=>doc.ref.delete()));
}

// A shop removed with its merchant must take its games with it. Keeping a
// game whose shop and owner no longer exist makes prizes impossible to manage.
async function deleteGamesForDeletedShops(db, shopRefs) {
  const snapshots=await Promise.all(shopRefs.flatMap(shop=>[
    db.collection('games').where('enseigne_id','==',shop).get(),
    db.collection('games').where('enseigne_ref','==',shop).get(),
  ]));
  const games=[...new Map(snapshots.flatMap(s=>s.docs).map(doc=>[doc.id,doc])).values()];
  for(const game of games) {
    const [prizes,jobs]=await Promise.all([
      db.collection('prizes').where('game_id','==',game.ref).get(),
      db.collection('_partner_delivery_jobs').where('game_ref','==',game.ref).get(),
    ]);
    for(const job of jobs.docs) {
      // A queued partner delivery must never survive deletion of its source.
      if(['pending','sending'].includes(job.data().status)) {
        await job.ref.update({status:'review',reason:'game_deleted_account_removal'});
      }
    }
    for(const prize of prizes.docs) {
      const winner=userPath(prize.data().winner_id);
      if(winner) await db.doc(`${winner}/my_lots/${prize.id}`).delete();
      await Promise.all([
        prize.ref.delete(),
        db.doc(`public_prize_winners/${prize.id}`).delete(),
      ]);
    }
    await Promise.all([
      deleteDirectChildren(game.ref,'participants'),
      deleteDirectChildren(game.ref,'participants_details'),
      deleteDirectChildren(game.ref,'winners'),
    ]);
    await game.ref.delete();
  }
  return games.map(game=>game.ref.path);
}

module.exports={deleteGamesForDeletedShops};
