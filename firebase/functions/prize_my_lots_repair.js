// Repare, de facon strictement additive, le lien manquant
// users/{winnerUid}/my_lots/{prizeId} pour un lot ("prizes") qui a deja un
// gagnant (winner_id, DocumentReference) mais aucune entree my_lots
// correspondante -- ce qui le rend invisible sur l'ecran joueur "Mes lots"
// (LotsJoueurPageWidget), qui ne lit plus que my_lots depuis la migration du
// 2026-03-15 (commit 86f4cec).
//
// Cas couverts par ce module (independant du moteur qui a cree le lot -- gain
// instantane, grand tirage, parrainage, defi mensuel/commercant du mois,
// animation, ou tout mecanisme futur) :
// - lots historiques crees avant l'introduction de my_lots ;
// - lots dont l'ecriture my_lots a echoue ou a ete oubliee (bug, moteur
//   partiellement transactionnel, panne).
//
// Ce module n'ecrit jamais dans "prizes" et ne modifie ni ne supprime jamais
// une entree my_lots existante : findMissingMyLotsLinks() est en lecture
// seule, repairMissingMyLotsLink() ne fait que CREER l'entree manquante (et
// se relit dans la meme transaction pour rester idempotent -- un second
// appel sur le meme prizeId renvoie "already_linked" sans rien ecrire).

const admin = require("firebase-admin");

const db = admin.firestore();

function isUsableWinnerRef(winnerRef) {
  return !!winnerRef && typeof winnerRef.collection === "function";
}

/**
 * Scanne une page de la collection "prizes" (paginee par ID de document) et
 * retourne les lots dont le winner_id est exploitable mais dont l'entree
 * my_lots correspondante est absente. Purement en lecture -- ne modifie rien.
 */
async function findMissingMyLotsLinks({pageSize = 200, startAfterId = ""} = {}) {
  const boundedPageSize = Math.max(1, Math.min(500, Number(pageSize) || 200));
  let query = db
    .collection("prizes")
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(boundedPageSize);
  if (startAfterId) {
    query = query.startAfter(startAfterId);
  }

  const snap = await query.get();
  const missing = [];
  const skippedNoWinner = [];

  for (const doc of snap.docs) {
    const prize = doc.data() || {};
    const winnerRef = prize.winner_id;
    if (!isUsableWinnerRef(winnerRef)) {
      // Pas encore de gagnant (lot pas encore attribue), ou winner_id dans un
      // format non exploitable (ex. chaine plutot que DocumentReference) --
      // ce module ne corrige que le lien my_lots, pas le format de winner_id
      // lui-meme ; on le journalise pour visibilite (voir CORRECTION ATTENDUE
      // : "differents formats incompatibles de winner_id").
      if (winnerRef) {
        skippedNoWinner.push({prizeId: doc.id, winnerIdType: typeof winnerRef});
      }
      continue;
    }
    const myLotRef = winnerRef.collection("my_lots").doc(doc.id);
    // eslint-disable-next-line no-await-in-loop
    const myLotSnap = await myLotRef.get();
    if (!myLotSnap.exists) {
      missing.push({prizeId: doc.id, winnerPath: winnerRef.path});
    }
  }

  return {
    missing,
    skippedNoWinner,
    scanned: snap.docs.length,
    lastId: snap.docs.length > 0 ? snap.docs[snap.docs.length - 1].id : "",
    hasMore: snap.docs.length === boundedPageSize,
  };
}

/**
 * Cree l'entree users/{winnerUid}/my_lots/{prizeId} manquante pour un prize
 * precis. N'ecrit jamais dans "prizes". Idempotent : si l'entree existe deja
 * (course avec un autre appel, ou deja reparee), ne fait rien et le signale.
 */
async function repairMissingMyLotsLink(prizeId) {
  const prizeRef = db.collection("prizes").doc(prizeId);
  return db.runTransaction(async (transaction) => {
    const prizeSnap = await transaction.get(prizeRef);
    if (!prizeSnap.exists) {
      throw new Error(`Prize introuvable: ${prizeId}`);
    }
    const prize = prizeSnap.data() || {};
    const winnerRef = prize.winner_id;
    if (!isUsableWinnerRef(winnerRef)) {
      throw new Error(
        `Prize ${prizeId} n'a pas de winner_id (DocumentReference) exploitable -- rien a reparer.`,
      );
    }

    const myLotRef = winnerRef.collection("my_lots").doc(prizeRef.id);
    const myLotSnap = await transaction.get(myLotRef);
    if (myLotSnap.exists) {
      return {status: "already_linked", prizeId, winnerPath: winnerRef.path};
    }

    transaction.set(myLotRef, {
      prize_id: prizeRef,
      repaired_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {status: "repaired", prizeId, winnerPath: winnerRef.path};
  });
}

module.exports = {findMissingMyLotsLinks, repairMissingMyLotsLink};
