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
  'jeu',
  'date_participation',
  'gagnant',
  'lot_gagne',
];
const kColumnLabels = {
  prenom: 'Prénom',
  nom: 'Nom',
  email: 'Email',
  telephone: 'Téléphone',
  ville: 'Ville',
  jeu: 'Jeu',
  date_participation: 'Date de participation',
  gagnant: 'Gagnant',
  lot_gagne: 'Lot gagné',
};

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

// Exports the players who took part in one game, for the merchant who owns
// that game (or an admin) only -- never a cross-merchant or cross-game
// listing. See export_game_participants.md in the PR/report for the full
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
        'Only the game owner can export its participants.',
      );
    }

    const participantsSnap = await gameRef.collection('participants').get();

    const rows = [];
    if (!participantsSnap.empty) {
      // Dedupe + batch-fetch user docs in one round trip (firestore.getAll)
      // instead of one get() per participant.
      const userRefsByPath = new Map();
      participantsSnap.docs.forEach((doc) => {
        const userRef = toDocRef(doc.data().user_id);
        if (userRef) userRefsByPath.set(userRef.path, userRef);
      });
      const uniqueUserRefs = [...userRefsByPath.values()];

      const [userSnaps, prizesSnap] = await Promise.all([
        uniqueUserRefs.length
          ? firestore.getAll(...uniqueUserRefs)
          : Promise.resolve([]),
        firestore.collection('prizes').where('game_id', '==', gameId).get(),
      ]);
      const usersByPath = new Map(
        userSnaps.map((s) => [s.ref.path, s.data() || {}]),
      );

      const prizesByWinnerPath = new Map();
      prizesSnap.docs.forEach((doc) => {
        const prize = doc.data() || {};
        const winnerRef = toDocRef(prize.winner_id);
        if (!winnerRef) return;
        const name =
          getTrimmedString(prize.name) || getTrimmedString(prize.description);
        if (!name) return;
        const existing = prizesByWinnerPath.get(winnerRef.path);
        prizesByWinnerPath.set(
          winnerRef.path,
          existing ? `${existing}; ${name}` : name,
        );
      });

      const gameName = getTrimmedString(gameData.name) || 'Jeu';

      participantsSnap.docs.forEach((doc) => {
        const participant = doc.data() || {};
        const userRef = toDocRef(participant.user_id);
        const userData = userRef ? usersByPath.get(userRef.path) || {} : {};
        const prizeName = userRef
          ? prizesByWinnerPath.get(userRef.path)
          : undefined;
        rows.push({
          prenom: getTrimmedString(userData.first_name),
          nom: getTrimmedString(userData.last_name),
          email: getTrimmedString(userData.email),
          telephone: getTrimmedString(userData.phone_number),
          ville: getTrimmedString(userData.city),
          jeu: gameName,
          date_participation: formatDateFr(participant.participation_date),
          gagnant: prizeName ? 'Oui' : 'Non',
          lot_gagne: prizeName || '',
        });
      });
    }

    const csv = buildCsv(rows);
    const fileName = `proxiplay_joueurs_${slugify(gameData.name)}_${new Date().toISOString().slice(0, 10)}.csv`;

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
