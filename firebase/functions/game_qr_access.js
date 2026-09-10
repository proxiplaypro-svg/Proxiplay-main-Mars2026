const admin = require('firebase-admin');
const functions = require('firebase-functions');
const crypto = require('node:crypto');
const {userPath, shopOwnerPath} = require('./merchant_ownership');
const {excluded} = require('./prize_integrity');
const {getNowTimestamp} = require('./lib/emulator_runtime');
const fail = () => { throw new functions.https.HttpsError('failed-precondition', 'QR invalide ou expire. Scannez le QR en boutique.'); };
const shopPath = game => (game.enseigne_id || game.enseigne_ref)?.path || '';
const validId = value => typeof value === 'string' && /^[^/]{1,150}$/.test(value);

// Private collection: no client rule grants access. Printed capabilities can be
// reused by different players; the participation transaction enforces one/day.
async function validateQr(tx, gameRef, game, token, now) {
  if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token)) fail();
  const snap = await tx.get(gameRef.firestore.doc('game_qr_access/' + gameRef.id));
  const proof = snap.data();
  const shop = shopPath(game);
  const currentShop = /^enseignes\/[^/]+$/.test(shop) ? await tx.get(gameRef.firestore.doc(shop)) : null;
  if (!proof || proof.game_path !== gameRef.path || proof.shop_path !== shopPath(game) ||
      proof.shop_owner_path !== shopOwnerPath(currentShop?.data()) ||
      proof.owner_path !== userPath(game.owner_id) || typeof proof.expires_at?.toMillis !== 'function' ||
      proof.expires_at.toMillis() <= now.toMillis() ||
      typeof proof.token !== 'string' || proof.token.length !== token.length ||
      !crypto.timingSafeEqual(Buffer.from(proof.token), Buffer.from(token))) fail();
}

exports.issueGameQrAccess = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Connexion requise.');
  if (!validId(data?.gameId)) throw new functions.https.HttpsError('invalid-argument', 'Jeu invalide.');
  const db = admin.firestore(), gameRef = db.doc('games/' + data.gameId);
  return db.runTransaction(async tx => {
    const [gameSnap, userSnap, current] = await Promise.all([
      tx.get(gameRef), tx.get(db.doc('users/' + context.auth.uid)),
      tx.get(db.doc('game_qr_access/' + data.gameId)),
    ]);
    const game = gameSnap.data(), user = userSnap.data();
    if (!game || excluded(user)) throw new functions.https.HttpsError('permission-denied', 'Acces refuse.');
    const shop = shopPath(game);
    const shopSnap = /^enseignes\/[^/]+$/.test(shop) ? await tx.get(db.doc(shop)) : null;
    const owner = shopOwnerPath(shopSnap?.data());
    const explicit = userPath(game.owner_id);
    if (user.user_role !== 'admin' && !(user.user_role === 'commercant' &&
        owner === 'users/' + context.auth.uid && (game.owner_id == null || explicit === owner))) {
      throw new functions.https.HttpsError('permission-denied', 'Acces refuse.');
    }
    const now = getNowTimestamp(admin);
    if (typeof game.end_date?.toMillis !== 'function' || game.end_date.toMillis() <= now.toMillis() ||
        ['ended','cancelled','canceled','disabled'].includes(game.status)) fail();
    const old = current.data();
    if (data.rotate !== true && old?.game_path === gameRef.path && old.shop_path === shop &&
        old.owner_path === explicit && old.shop_owner_path === owner && old.expires_at.toMillis() > now.toMillis()) {
      return {token: old.token, expiresAt: old.expires_at.toMillis()};
    }
    const token = crypto.randomBytes(32).toString('hex');
    tx.set(current.ref, {token, game_path: gameRef.path, shop_path: shop,
      owner_path: explicit, shop_owner_path: owner, expires_at: game.end_date, issued_by: context.auth.uid});
    return {token, expiresAt: game.end_date.toMillis()};
  });
});
exports.validateQr = validateQr;
