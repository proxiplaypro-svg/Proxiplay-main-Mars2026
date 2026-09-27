const functions = require('firebase-functions');
const admin = require('firebase-admin');
const {shopOwnerRef} = require('./merchant_ownership');

const firestore = admin.firestore();

// Same region as getPrizeWinnerContactForMerchant (the other callable that
// exposes participant/winner PII to a merchant) so this stays consistent
// with the region already used from the same game-detail page.
const kRegion = 'us-central1';

const {buildCsv,slugify} = require('./game_winner_rows');
const getTrimmedString = value => typeof value === 'string' ? value.trim() : '';
function toDocRef(value) {
  if (!value) return null;
  if (typeof value === 'string') {
    const path = getTrimmedString(value);
    return path && path.includes('/') ? firestore.doc(path) : null;
  }
  if (typeof value.path === 'string' && typeof value.get === 'function') {
    return value;
  }
  if (typeof value.path === 'string') {
    return firestore.doc(value.path);
  }
  return null;
}

// Exports the winners (players actually awarded a prize) of one game, for
// the merchant who owns that game (or an admin) only -- never a
// cross-merchant or cross-game listing, and never a losing participation.
// See export_game_participants.md in the PR/report for the full
// authorization + data-source writeup.
exports.exportGameParticipantsCallable = functions
  .region(kRegion)
  .runWith({timeoutSeconds: 60, memory: '256MB'})
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Unauthenticated calls are not allowed.',
      );
    }

    const gameId = getTrimmedString(data && data.gameId);
    if (!gameId || gameId.includes('/')) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'A valid gameId is required.',
      );
    }

    const format = getTrimmedString(data && data.format) || 'csv';
    if (format !== 'csv') {
      // PDF is not implemented yet (see report) -- fail loudly instead of
      // silently falling back to CSV or ignoring the requested format.
      throw new functions.https.HttpsError(
        'unimplemented',
        'Only format "csv" is currently supported.',
      );
    }

    const gameRef = firestore.collection('games').doc(gameId);
    const gameSnap = await gameRef.get();
    if (!gameSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Game not found.');
    }
    const gameData = gameSnap.data() || {};

    const callerRef = firestore.collection('users').doc(context.auth.uid);
    const isCallerAdmin = require('./admin_identity').isTrustedAdmin(
      context.auth, (await callerRef.get()).data());
    const shopRef = toDocRef(gameData.enseigne_id || gameData.enseigne_ref);
    const shop = shopRef ? await shopRef.get() : null;
    const ownerRef =
      gameData.owner_id != null
        ? toDocRef(gameData.owner_id)
        : shopOwnerRef(firestore, shop?.data());

    if (!isCallerAdmin && (!require('./merchant_ownership').gameOwnership(gameData, shop?.data()).valid ||
        !ownerRef || ownerRef.path !== callerRef.path)) {
      console.error('[EXPORT_GAME_PARTICIPANTS_BLOCKED]', {
        gameId,
        callerUid: context.auth.uid,
      });
      throw new functions.https.HttpsError(
        'permission-denied',
        'Only the game owner can export its winners.',
      );
    }

    // Canonical source of "who actually won a prize on this game": prizes,
    // not participants.hasWinner (same source getMerchantPrizes already uses
    // -- see merchant_prizes.js -- so "Voir les codes gagnants" and this
    // export never disagree). game_id on prizes is a DocumentReference, so
    // the query must compare against gameRef, not the raw gameId string --
    // a bare-string comparison here previously never matched anything.
    const rows = (await require('./game_winner_rows').loadGameWinners(firestore, gameRef)).map(e=>e.row);

    const csv = buildCsv(rows);
    const fileName = `proxiplay_gagnants_${slugify(gameData.name)}_${new Date().toISOString().slice(0, 10)}.csv`;

    console.log('[EXPORT_GAME_PARTICIPANTS_OK]', {
      gameId,
      callerUid: context.auth.uid,
      format: 'csv',
      rowCount: rows.length,
    });

    // Audit trail: who exported what, never the exported data itself.
    await firestore.collection('_export_audit_logs').add({
      merchantId: callerRef.path,
      gameId,
      format: 'csv',
      exportedAt: admin.firestore.FieldValue.serverTimestamp(),
      rowCount: rows.length,
    });

    return {
      ok: true,
      format: 'csv',
      fileName,
      rowCount: rows.length,
      csvBase64: Buffer.from(csv, 'utf8').toString('base64'),
    };
  });
