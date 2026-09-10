const admin = require('firebase-admin');
const functions = require('firebase-functions');
const {excluded} = require('./prize_integrity');
const {getNowTimestamp} = require('./lib/emulator_runtime');
const {lotSnapshot} = require('./prize_lot_snapshot');
const deny = (message = 'Retrait refuse.') => { throw new functions.https.HttpsError('failed-precondition', message); };

// platform and partner are both coordinated by Proxiplay. Being a merchant,
// sponsor or knowing a code does not confer operator authority.
exports.claimOperatorPrize = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Connexion requise.');
  if (![data?.prizeId, data?.winnerId].every(v => typeof v === 'string' && /^[^/]{1,150}$/.test(v)) ||
      typeof data?.code !== 'string' || !data.code.length || data.code.length > 128) {
    throw new functions.https.HttpsError('invalid-argument', 'Lot, beneficiaire et code requis.');
  }
  const db = admin.firestore(), ref = db.doc('prizes/' + data.prizeId);
  if (data.requestId != null && (typeof data.requestId !== 'string' || !/^[a-zA-Z0-9_-]{16,100}$/.test(data.requestId))) {
    throw new functions.https.HttpsError('invalid-argument', 'Identifiant de requete invalide.');
  }
  return db.runTransaction(async tx => {
    const [operator, snap, winner, link] = await Promise.all([
      tx.get(db.doc('users/' + context.auth.uid)), tx.get(ref),
      tx.get(db.doc('users/' + data.winnerId)),
      tx.get(db.doc(`users/${data.winnerId}/my_lots/${data.prizeId}`)),
    ]);
    if (operator.data()?.user_role !== 'admin' || excluded(operator.data())) {
      throw new functions.https.HttpsError('permission-denied', 'Operateur Proxiplay requis.');
    }
    const prize = snap.data();
    if (!prize || !['platform','partner'].includes(prize.fulfillment_type) ||
        prize.winner_id?.path !== winner.ref.path || excluded(winner.data()) ||
        link.data()?.prize_id?.path !== ref.path || prize.claim_code !== data.code) deny();
    // Retry is a read-only acknowledgement of an earlier successful operation.
    if (prize.claimed === true) {
      if (prize.claim_method !== 'operator_v1' || !data.requestId ||
          prize.claim_request_id !== data.requestId || prize.claimed_by?.path !== operator.ref.path) {
        throw new functions.https.HttpsError('already-exists', 'Lot deja utilise.');
      }
      return {status: 'already_claimed', prizeId: ref.id};
    }
    if (prize.claimed != null && prize.claimed !== false) deny();
    if (['expired', 'expire', 'expiré'].includes(String(prize.status || '').toLowerCase())) {
      deny('Lot expire.');
    }
    if (prize.claimed_at || prize.redeemed_at || ['claimed', 'reclame', 'retire', 'redeemed']
      .includes(String(prize.status || '').toLowerCase())) {
      throw new functions.https.HttpsError('already-exists', 'Lot deja utilise : historique a verifier.');
    }
    const now = getNowTimestamp(admin);
    if (prize.usage_deadline != null && (typeof prize.usage_deadline.toMillis !== 'function' ||
        prize.usage_deadline.toMillis() < now.toMillis())) deny('Lot expire ou echeance invalide.');
    tx.update(ref, {claimed: true, status: 'claimed', claimed_by_admin: true,
      claimed_by: operator.ref, claimed_at: now, claim_method: 'operator_v1',
      claim_request_id: data.requestId || null});
    tx.update(link.ref, {prize_snapshot: lotSnapshot({...prize, claimed: true}), prize_deleted: false});
    return {status: 'claimed', prizeId: ref.id};
  });
});
