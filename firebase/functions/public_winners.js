const admin = require('firebase-admin');
const functions = require('firebase-functions');
function publicText(value, max = 120) {
  const text = typeof value === 'string' ? value.trim() : '';
  return /@|https?:|\+?\d[\d ()-]{7,}/i.test(text) ? '' : text.slice(0, max);
}
function publicWinner(user = {}, date = null) {
  return {
    label: publicText(user.first_name || user.firstName, 50).split(/\s+/)[0] || 'Un joueur',
    city: publicText(user.city, 80),
    selected_at: date,
  };
}
function publicPrize(prize, user = {}) {
  const winner = publicWinner(user, prize.win_date || null);
  return {
    winnerFirstName: winner.label, winnerCity: winner.city,
    name: publicText(prize.name), enseigne_name: publicText(prize.enseigne_name),
    win_date: winner.selected_at,
    ...(prize.game_id?.path?.startsWith('games/') ? {game_id: prize.game_id} : {}),
  };
}
async function syncPublicPrize(prizeId, {createOnly = false, apply = true} = {}) {
  const db = admin.firestore();
  return db.runTransaction(async tx => {
    const prizeRef = db.doc(`prizes/${prizeId}`);
    const publicRef = db.doc(`public_prize_winners/${prizeId}`);
    const [prize, projection] = await Promise.all([tx.get(prizeRef), tx.get(publicRef)]);
    if (!prize.exists) {
      if (projection.exists && apply && !createOnly) tx.delete(publicRef);
      return {status: 'missing_prize'};
    }
    if (createOnly && projection.exists) return {status: 'already_exists'};
    const winnerRef = prize.data().winner_id;
    if (!/^users\/[^/]+$/.test(winnerRef?.path || '')) return {status: 'manual_review_required'};
    const user = await tx.get(winnerRef);
    if (!user.exists) return {status: 'manual_review_required'};
    if (apply) tx.set(publicRef, publicPrize(prize.data(), user.data()));
    return {status: apply ? 'published' : 'would_publish'};
  });
}
exports.publicWinner = publicWinner;
exports.publicPrize = publicPrize;
exports.syncPublicPrize = syncPublicPrize;
// Historical migration: create-only, transactionally validated, dry-run by default.
async function backfillAnimationWinner(animationId, {apply = false} = {}) {
  const db = admin.firestore();
  return db.runTransaction(async tx => {
    const ref = db.doc(`animations/${animationId}`);
    const target = ref.collection('public_winner').doc('current');
    const [source, existing, privateWinner] = await Promise.all([
      tx.get(ref), tx.get(target), tx.get(ref.collection('winner').doc('current')),
    ]);
    if (existing.exists) return {status:'already_exists'};
    const uid = source.data()?.winner_uid;
    if (!source.exists || typeof uid !== 'string' || !uid || uid.includes('/') ||
        (privateWinner.exists && privateWinner.data().uid !== uid)) return {status:'manual_review_required'};
    const user = await tx.get(db.doc(`users/${uid}`));
    if (!user.exists) return {status:'manual_review_required'};
    if (apply) tx.create(target, publicWinner(user.data(), source.data().drawn_at || privateWinner.data()?.selected_at || null));
    return {status:apply?'published':'would_publish'};
  });
}
exports.backfillAnimationWinner = backfillAnimationWinner;
exports.syncPublicPrizeWinner = functions.firestore.document('prizes/{prizeId}').onWrite(
  (_change, context) => syncPublicPrize(context.params.prizeId),
);
