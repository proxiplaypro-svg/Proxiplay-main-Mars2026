const functions = require('firebase-functions');
const admin = require('firebase-admin');
const {shopOwnerRef} = require('./merchant_ownership');

const firestore = admin.firestore();

// Same region as getPrizeWinnerContactForMerchant (the other callable that
// exposes participant/winner PII to a merchant) so this stays consistent
// with the region already used from the same game-detail page.
const kRegion = 'us-central1';

function getTrimmedString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

// Minimal, local equivalent of index.js's toDocRef -- kept private to this
// file rather than importing from index.js, matching how other standalone
// callable modules (operator_prize_claim.js, game_qr_access.js) already
// avoid depending on index.js internals.
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

function csvEscape(value) {
  const s = value == null ? '' : String(value);
  return /[;"\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

// dd/mm/yyyy hh:mm, UTC -- readable in a French-locale spreadsheet without
// pulling in a date-formatting dependency for one column.
function formatDateFr(value) {
  const ms =
    value && typeof value.toMillis === 'function'
      ? value.toMillis()
      : value instanceof Date
        ? value.getTime()
        : null;
  if (!Number.isFinite(ms)) return '';
  const d = new Date(ms);
  const pad = (n) => String(n).padStart(2, '0');
  return `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`;
}

function slugify(value) {
  const base = getTrimmedString(value) || 'jeu';
  return (
    base
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 60) || 'jeu'
  );
}

const kColumns = [
  'prenom',
  'nom',
  'email',
  'telephone',
  'ville',
  'date_du_gain',
  'lot_gagne',
  'code_gagnant',
  'statut',
];
const kColumnLabels = {
  prenom: 'Prénom',
  nom: 'Nom',
  email: 'Email',
  telephone: 'Téléphone',
  ville: 'Ville',
  date_du_gain: 'Date du gain',
  lot_gagne: 'Lot gagné',
  code_gagnant: 'Code gagnant',
  statut: 'Statut',
};

// Mirrors PrizesRecord.isAvailable/isExpired (lib/backend/schema/prizes_record.dart)
// so the exported status matches what the merchant/player see in the app.
function prizeStatus(prize) {
  if (prize.claimed === true) return 'Retiré';
  const deadline = prize.usage_deadline;
  const ms =
    deadline && typeof deadline.toMillis === 'function'
      ? deadline.toMillis()
      : null;
  if (Number.isFinite(ms) && ms < Date.now()) return 'Expiré';
  return 'À retirer';
}

// "Lot gagné" must never be blank when the prize carries enough information
// to identify it -- name is the modern field, description covers older
// documents that only ever had that, and prize_type is the last resort for
// the rare historical document with neither (still better than empty).
function prizeLabel(prize) {
  const name = getTrimmedString(prize.name);
  if (name) return name;
  const description = getTrimmedString(prize.description);
  if (description) return description;
  const type = getTrimmedString(prize.prize_type);
  if (type === 'principal') return 'Lot principal';
  if (type === 'secondaire') return 'Lot secondaire';
  if (type) return type;
  return 'Lot gagné';
}

function buildCsv(rows) {
  const header = kColumns.map((c) => csvEscape(kColumnLabels[c])).join(';');
  const lines = rows.map((row) =>
    kColumns.map((c) => csvEscape(row[c])).join(';'),
  );
  // Leading UTF-8 BOM: French-locale Excel otherwise guesses a legacy
  // codepage and accented names/cities render as mojibake. ';' separator
  // matches Excel FR's default list separator (',' is the decimal mark).
  return '\uFEFF' + [header, ...lines].join('\r\n') + '\r\n';
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
    const isCallerAdmin =
      (await callerRef.get()).data()?.user_role === 'admin';
    const shopRef = toDocRef(gameData.enseigne_id || gameData.enseigne_ref);
    const shop = shopRef ? await shopRef.get() : null;
    const ownerRef =
      gameData.owner_id != null
        ? toDocRef(gameData.owner_id)
        : shopOwnerRef(firestore, shop?.data());

    if (!isCallerAdmin && (!ownerRef || ownerRef.path !== callerRef.path)) {
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
    const prizesSnap = await firestore
      .collection('prizes')
      .where('game_id', '==', gameRef)
      .get();

    const winnerRefsByPath = new Map();
    const prizeEntries = [];
    prizesSnap.docs.forEach((doc) => {
      const prize = doc.data() || {};
      const winnerRef = toDocRef(prize.winner_id);
      // No winner_id yet == not actually awarded to anyone -- not a winner.
      if (!winnerRef) return;
      winnerRefsByPath.set(winnerRef.path, winnerRef);
      prizeEntries.push({prize, winnerRef});
    });

    const uniqueWinnerRefs = [...winnerRefsByPath.values()];
    const userSnaps = uniqueWinnerRefs.length
      ? await firestore.getAll(...uniqueWinnerRefs)
      : [];
    const usersByPath = new Map(
      userSnaps.map((s) => [s.ref.path, s.data() || {}]),
    );

    // One row per prize won -- a player with several prizes on this game
    // gets several rows, never merged (see report).
    const rows = prizeEntries.map(({prize, winnerRef}) => {
      const userData = usersByPath.get(winnerRef.path) || {};
      return {
        prenom: getTrimmedString(userData.first_name),
        nom: getTrimmedString(userData.last_name),
        email: getTrimmedString(userData.email),
        telephone: getTrimmedString(userData.phone_number),
        ville: getTrimmedString(userData.city),
        date_du_gain: formatDateFr(prize.win_date),
        lot_gagne: prizeLabel(prize),
        code_gagnant: getTrimmedString(prize.claim_code),
        statut: prizeStatus(prize),
      };
    });

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
