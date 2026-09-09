const functions = require('firebase-functions');
function path(value) { return typeof value?.path === 'string' ? value.path : typeof value === 'string' ? value : ''; }
function excluded(user) {
  return !user || user.deleted === true || user.auto_deleted === true ||
    ['rejected','suspended'].includes(String(user.account_status || '').toLowerCase()) ||
    ['suspended','suspendu'].includes(String(user.player_status_cached || '').toLowerCase());
}
function review(prizeId, reason) {
  functions.logger.error('AWARD_MANUAL_REVIEW_REQUIRED', {prizeId, reason});
  return {status:'manual_review_required', prizeId, reason};
}
// Read phase only: invoke before any transaction writes. Never repairs contradictions.
async function checkAwardLinks(tx, {prizeRef, winnerRef, sourceField, sourceValue, prizeSnap}) {
  if (!/^users\/[^/]+$/.test(path(winnerRef))) return review(prizeRef.id,'invalid_winner_reference');
  const user = await tx.get(winnerRef);
  if (!user.exists) return review(prizeRef.id,'missing_winner_account');
  const prize = prizeSnap || await tx.get(prizeRef);
  if (prize.exists && (path(prize.data().winner_id) !== winnerRef.path ||
      !sourceField || path(prize.data()[sourceField]) !== path(sourceValue))) return review(prizeRef.id,'winner_or_source_mismatch');
  const canonical = await tx.get(winnerRef.collection('my_lots').doc(prizeRef.id));
  if (canonical.exists && path(canonical.data().prize_id) !== prizeRef.path) return review(prizeRef.id,'contradictory_canonical_link');
  const links = await tx.get(prizeRef.firestore.collectionGroup('my_lots').where('prize_id','==',prizeRef));
  if (links.docs.some(doc => doc.ref.path !== winnerRef.path + '/my_lots/' + prizeRef.id)) return review(prizeRef.id,'noncanonical_or_duplicate_link');
  return {status:'consistent', linked:canonical.exists};
}
function prizeSource(prize) {
  for (const field of ['game_id','animation_id','referral_game_id','monthly_challenge_draw_ref']) {
    if (prize[field]) return {sourceField:field,sourceValue:prize[field]};
  }
  return {};
}
module.exports={path,excluded,review,checkAwardLinks,prizeSource};
