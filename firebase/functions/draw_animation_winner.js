const {publicWinner} = require('./public_winners');
const {checkAwardLinks, review} = require("./prize_integrity");
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const {runScheduledDraws} = require("./scheduled_draw_runner");
const {
  queuePushNotificationRequest,
} = require("./push_notification_request.js");
const {shouldNotifyMerchantForPrize} = require("./prize_merchant_notification_policy");

const db = admin.firestore();

function getTrimmedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function toBoolean(value, fallback = false) {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["true", "1", "yes", "y", "on"].includes(normalized)) return true;
    if (["false", "0", "no", "n", "off"].includes(normalized)) return false;
  }
  if (typeof value === "number") return value !== 0;
  return fallback;
}

function getSmtpSettings() {
  const smtpConfig = functions.config().smtp || {};
  const host = getTrimmedString(smtpConfig.host);
  const port = Number(smtpConfig.port || 587);
  const secure = toBoolean(smtpConfig.secure, port === 465);
  const user = getTrimmedString(smtpConfig.user);
  const pass = typeof smtpConfig.pass === "string" ? smtpConfig.pass : "";
  const fromEmail = getTrimmedString(smtpConfig.from_email);
  const fromName = getTrimmedString(smtpConfig.from_name);
  const replyTo = getTrimmedString(smtpConfig.reply_to);

  const missing = [];
  if (!host) missing.push("smtp.host");
  if (!Number.isFinite(port) || port <= 0) missing.push("smtp.port");
  if (!user) missing.push("smtp.user");
  if (!pass) missing.push("smtp.pass");
  if (!fromEmail) missing.push("smtp.from_email");
  if (!fromName) missing.push("smtp.from_name");
  if (missing.length > 0) throw new Error(`Missing SMTP config: ${missing.join(", ")}`);

  return { host, port, secure, user, pass, fromEmail, fromName, replyTo };
}

function createSmtpMailer() {
  const settings = getSmtpSettings();
  return {
    transporter: nodemailer.createTransport({
      host: settings.host,
      port: settings.port,
      secure: settings.secure,
      auth: { user: settings.user, pass: settings.pass },
    }),
    from: `${settings.fromName} <${settings.fromEmail}>`,
    replyTo: settings.replyTo,
  };
}

async function sendEmailNotification(mailer, to, subject, text, html) {
  await mailer.transporter.sendMail({
    from: mailer.from,
    to,
    subject,
    text,
    ...(html ? { html } : {}),
    ...(mailer.replyTo ? { replyTo: mailer.replyTo } : {}),
  });
}

function generateClaimCode(length = 8) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < length; i++) {
    code += chars[Math.floor(Math.random() * chars.length)];
  }
  return code;
}

// Meme regle d'exclusion que referral_game_engine.js / monthly_challenge.js :
// un compte supprime, rejete ou suspendu ne peut pas etre tire au sort.
function isExcludedAccount(userData) {
  if (!userData || userData.auto_deleted === true || userData.deleted === true) {
    return true;
  }
  const accountStatus = getTrimmedString(userData.account_status).toLowerCase();
  const playerStatus = getTrimmedString(userData.player_status_cached).toLowerCase();
  return ["rejected", "suspended"].includes(accountStatus) ||
    ["suspended", "suspendu"].includes(playerStatus);
}

function buildWinnerLabel(userData) {
  const email = getTrimmedString(userData.email);
  const firstName = getTrimmedString(userData.first_name || userData.firstName);
  const lastName = getTrimmedString(userData.last_name || userData.lastName);
  const displayName = getTrimmedString(userData.display_name || userData.displayName);
  return displayName || [firstName, lastName].filter(Boolean).join(" ") || email || "Gagnant inconnu";
}

function buildPrizePayload(animationId, animationData, winnerRef, drawnAt, claimCode, winnerData) {
  const prizeDescription = getTrimmedString(animationData.prize_description);
  const animationName = getTrimmedString(animationData.name);
  const winnerFirstName = getTrimmedString(winnerData.first_name || winnerData.firstName).split(/\s+/)[0] || "";
  const winnerCity = getTrimmedString(winnerData.city);

  return {
    prize_type: "principal",
    fulfillment_type: "platform",
    name: prizeDescription || animationName || "Gros lot",
    description: prizeDescription,
    prize_label: prizeDescription,
    winner_id: winnerRef,
    animation_id: animationId,
    claim_code: claimCode,
    claimed: false,
    win_date: drawnAt,
    ...(winnerFirstName
      ? { winnerFirstName: winnerFirstName, winner_first_name: winnerFirstName }
      : {}),
    ...(winnerCity ? { winnerCity: winnerCity, winner_city: winnerCity } : {}),
  };
}

// "Phase 1/2/3" (meme principe que main_prize_draw.js apres l'incident
// Kids Troc) : avant ce correctif, drawWinnerForAnimation faisait UNE
// boucle "for (const entryDoc of entriesSnap.docs) { await transaction.get(
// userRef) }" -- une lecture Firestore sequentielle par participant,
// A L'INTERIEUR de la transaction (introduit par bb55f91, 29/08/2026,
// jamais touche depuis). Exactement le motif qui a cause les timeouts de
// production sur le tirage principal (Kids Troc : 1576 participants).
// Phase 1 fait maintenant ce travail HORS transaction (lecture batchee des
// utilisateurs via getAll). Phase 3 ne relit que l'animation, le candidat
// choisi et le prize -- un cout constant quel que soit le nombre
// d'entries qualifiees. Phase 1 et Phase 3 dupliquent volontairement les
// memes verifications bon marche (deja_tire, deja_finalise) : Phase 1
// decide s'il faut tenter un tirage, Phase 3 revalide tout au moment du
// commit car rien ne garantit l'atomicite entre les deux (y compris une
// deuxieme execution concurrente du meme scheduler sur la meme animation).
const ANIMATION_PARTICIPANT_USER_BATCH_SIZE = 300;
// Borne explicite sur la boucle de repli de Phase 3 (candidat devenu
// inexclu/non qualifie entre Phase 1 et Phase 3) : garantit la
// terminaison sans jamais rescanner la collection entries.
const ANIMATION_MAX_CANDIDATE_ATTEMPTS = 20;

function isAnimationAlreadyFinalized(animationData) {
  return !!(getTrimmedString(animationData.winner_uid) || animationData.draw_status === 'no_eligible_entries');
}

// Lecture batchee des comptes utilisateurs pour un ensemble de candidats
// qualifies (un seul entry par uid par construction : l'id du doc entries
// EST le uid -- pas de ponderation/multiplicite a preserver ici, a la
// difference du tirage principal ou du parrainage). Fonctionne avec
// n'importe quel lecteur exposant getAll (Firestore nu en Phase 1, ou une
// Transaction en Phase 3 pour la relecture bornee du candidat).
async function loadEligibleAnimationCandidates(reader, entryDocs) {
  const uids = entryDocs.map((doc) => doc.id);
  const userRefs = uids.map((uid) => db.collection("users").doc(uid));
  const snapshotByPath = new Map();
  for (let i = 0; i < userRefs.length; i += ANIMATION_PARTICIPANT_USER_BATCH_SIZE) {
    const chunk = userRefs.slice(i, i + ANIMATION_PARTICIPANT_USER_BATCH_SIZE);
    // eslint-disable-next-line no-await-in-loop
    const snaps = await reader.getAll(...chunk);
    for (const snap of snaps) snapshotByPath.set(snap.ref.path, snap);
  }
  const candidates = [];
  for (const uid of uids) {
    const userRef = db.collection("users").doc(uid);
    const userSnap = snapshotByPath.get(userRef.path);
    if (userSnap && userSnap.exists && !isExcludedAccount(userSnap.data() || {})) {
      candidates.push({uid, userRef, userData: userSnap.data()});
    }
  }
  return candidates;
}

// Transaction courte partagee par les deux issues "sans gagnant" (aucune
// entry qualifiee en Phase 1, ou plus aucun candidat eligible apres la
// boucle de repli de Phase 3). Relit l'animation pour detecter une
// execution concurrente qui l'aurait deja finalisee.
async function finalizeAnimationWithoutWinner(animationRef, now) {
  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(animationRef);
    if (!snap.exists) return {status: "not_found"};
    const data = snap.data() || {};
    if (isAnimationAlreadyFinalized(data)) return {status: "already_finalized"};
    transaction.set(animationRef, {status: "ended", draw_status: "no_eligible_entries", drawn_at: now}, {merge: true});
    return {status: "no_eligible_entries"};
  });
}

async function drawWinnerForAnimation(animationId, { now = admin.firestore.Timestamp.now() } = {}) {
  const animationRef = db.collection("animations").doc(animationId);
  const t0 = Date.now();
  const step = (label) => functions.logger.info('DRAW_STEP_TIMING', {job: 'drawAnimationWinners', animationId, step: label, elapsedMs: Date.now() - t0});

  // ---------------- Phase 1 : hors transaction ----------------
  const animationSnap = await animationRef.get();
  step('phase1_animation_read');
  if (!animationSnap.exists) return {status: "not_found"};
  const animationData = animationSnap.data() || {};
  if (isAnimationAlreadyFinalized(animationData)) {
    return getTrimmedString(animationData.winner_uid)
      ? {status: "already_drawn", winnerUid: getTrimmedString(animationData.winner_uid)}
      : {status: "already_finalized"};
  }

  // Joueurs qualifies : animations/{id}/entries/{uid} avec
  // threshold_reached == true. Ecrit par participateInGameTransaction
  // (source de verite CF).
  const entriesSnap = await animationRef.collection("entries").where("threshold_reached", "==", true).get();
  step(`phase1_entries_read:count=${entriesSnap.docs.length}`);
  if (entriesSnap.empty) {
    const result = await finalizeAnimationWithoutWinner(animationRef, now);
    step(`phase1_short_circuit:${result.status}`);
    return result.status === 'no_eligible_entries' ? {...result, status: 'no_qualified_entries'} : result;
  }

  const eligible = await loadEligibleAnimationCandidates(db, entriesSnap.docs);
  step(`phase1_eligible_loaded:count=${eligible.length}`);
  if (eligible.length === 0) {
    const result = await finalizeAnimationWithoutWinner(animationRef, now);
    step(`phase1_short_circuit:${result.status}`);
    return result;
  }

  // ---------------- Phase 2 : selection pure, aucune I/O ----------------
  // Meme semantique probabiliste qu'avant la restructuration (tirage
  // uniforme) ; le generateur (Math.random, distinct de crypto.randomInt
  // utilise par les autres moteurs) est volontairement laisse inchange --
  // ce n'est pas l'objet de ce chantier.
  const initialCandidate = eligible[Math.floor(Math.random() * eligible.length)];

  // ---------------- Phase 3 : transaction courte, O(1) ----------------
  const initialPool = [initialCandidate, ...eligible.filter((c) => c !== initialCandidate)];

  const result = await db.runTransaction(async (transaction) => {
    step('phase3_attempt_start');
    const freshSnap = await transaction.get(animationRef);
    step('phase3_animation_read');
    if (!freshSnap.exists) return {status: "not_found"};
    const freshData = freshSnap.data() || {};
    if (isAnimationAlreadyFinalized(freshData)) {
      return getTrimmedString(freshData.winner_uid)
        ? {status: "already_drawn", winnerUid: getTrimmedString(freshData.winner_uid)}
        : {status: "already_finalized"};
    }

    let winner = null;
    let pool = initialPool;
    let attempt = 0;
    for (; attempt < ANIMATION_MAX_CANDIDATE_ATTEMPTS && pool.length > 0; attempt += 1) {
      const candidate = attempt === 0 ? pool[0] : pool[Math.floor(Math.random() * pool.length)];
      // eslint-disable-next-line no-await-in-loop
      const userSnap = await transaction.get(candidate.userRef);
      step(`phase3_candidate_read:attempt=${attempt}`);
      if (userSnap.exists && !isExcludedAccount(userSnap.data() || {})) {
        winner = {...candidate, userData: userSnap.data()};
        break;
      }
      pool = pool.filter((c) => c.uid !== candidate.uid);
    }
    if (!winner) {
      if (pool.length === 0) {
        transaction.set(animationRef, {status: "ended", draw_status: "no_eligible_entries", drawn_at: now}, {merge: true});
        return {status: "no_eligible_entries"};
      }
      functions.logger.warn('DRAW_CANDIDATE_RETRY_BUDGET_EXCEEDED', {job: 'drawAnimationWinners', animationId, triedCount: attempt, untestedRemaining: pool.length});
      return {status: "retry_needed", reason: "candidate_retry_budget_exceeded"};
    }

    const winnerLabel = buildWinnerLabel(winner.userData);
    const winnerEmail = getTrimmedString(winner.userData.email);
    const claimCode = generateClaimCode();

    // Id deterministe (pas de doc() auto-id) : rejouer cette fonction sur la
    // meme animation reutilise le meme prize au lieu d'en creer un second.
    const prizeRef = db.collection("prizes").doc(`animation_${animationId}`);
    const prizeSnap = await transaction.get(prizeRef);
    step('phase3_prize_read');
    const integrity = await checkAwardLinks(transaction, {prizeRef, winnerRef: winner.userRef, sourceField: 'animation_id', sourceValue: animationId, prizeSnap});
    if (integrity.status !== 'consistent') return integrity;
    if (!prizeSnap.exists) {
      transaction.set(
        prizeRef,
        buildPrizePayload(animationId, freshData, winner.userRef, now, claimCode, winner.userData),
      );
    }

    transaction.set(
      winner.userRef.collection("my_lots").doc(prizeRef.id),
      { prize_id: prizeRef, updated_at: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true },
    );

    transaction.set(animationRef.collection('public_winner').doc('current'), publicWinner(winner.userData, now));
    // Format attendu par l'API admin /api/admin/animations/[id]/detail
    transaction.set(animationRef.collection("winner").doc("current"), {
      uid: winner.uid,
      label: winnerLabel,
      email: winnerEmail,
      selected_at: now,
    });

    transaction.set(
      animationRef,
      { winner_uid: winner.uid, winner_ref: winner.userRef, drawn_at: now, status: "ended" },
      { merge: true },
    );

    return {
      status: "completed",
      winnerUid: winner.uid,
      winnerEmail,
      winnerLabel,
      claimCode,
      prizeId: prizeRef.id,
      qualifiedCount: entriesSnap.size,
      eligibleCount: eligible.length,
    };
  }).then((r) => { step(`phase3_settled:${r?.status || 'unknown'}`); return r; },
    (error) => { step(`phase3_failed:${error?.code || error?.message || 'unknown'}`); throw error; });

  if (result.status === "completed") {
    await notifyAnimationWinner(animationId, animationRef, result);
  }

  return result;
}

// Reparation : si un ancien tirage (avant ce correctif) a laisse winner_uid
// pose sans prize/my_lots, ou si une reprise a echoue apres l'ecriture du
// prize mais avant les notifications, cette fonction complete ce qui manque
// sans jamais rejouer le tirage lui-meme (le gagnant deja designe ne change
// pas). Idempotente : sans rien a reparer, elle ne fait aucune ecriture.
async function repairAnimationDraw(animationId) {
  const animationRef = db.collection("animations").doc(animationId);

  const result = await db.runTransaction(async (transaction) => {
    const animationSnap = await transaction.get(animationRef);
    if (!animationSnap.exists) {
      throw new Error("Animation not found.");
    }
    const animationData = animationSnap.data() || {};
    const winnerUid = getTrimmedString(animationData.winner_uid);
    if (!winnerUid) {
      return { status: "nothing_to_repair" };
    }

    const winnerRef = db.collection("users").doc(winnerUid);
    const winnerSnap = await transaction.get(winnerRef);
    if (!winnerSnap.exists) {
      return review(animationId, 'missing_winner_account');
    }
    const winnerData = winnerSnap.data() || {};

    const prizeRef = db.collection("prizes").doc(`animation_${animationId}`);
    const prizeSnap = await transaction.get(prizeRef);
    const integrity = await checkAwardLinks(transaction, {prizeRef, winnerRef: winnerRef, sourceField: 'animation_id', sourceValue: animationId, prizeSnap});
    if (integrity.status !== 'consistent') return integrity;
    const drawnAt = animationData.drawn_at || admin.firestore.Timestamp.now();
    const claimCode = generateClaimCode();

    transaction.set(animationRef.collection('public_winner').doc('current'), publicWinner(winnerData, drawnAt));
    let prizeCreated = false;
    if (!prizeSnap.exists) {
      transaction.set(
        prizeRef,
        buildPrizePayload(animationId, animationData, winnerRef, drawnAt, claimCode, winnerData),
      );
      prizeCreated = true;
    }

    transaction.set(
      winnerRef.collection("my_lots").doc(prizeRef.id),
      { prize_id: prizeRef, updated_at: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true },
    );

    transaction.set(
      animationRef.collection("winner").doc("current"),
      {
        uid: winnerUid,
        label: buildWinnerLabel(winnerData),
        email: getTrimmedString(winnerData.email),
        selected_at: drawnAt,
      },
      { merge: true },
    );

    transaction.set(
      animationRef,
      { status: "ended", drawn_at: drawnAt, winner_ref: winnerRef },
      { merge: true },
    );

    return {
      status: prizeCreated ? "repaired_prize_and_my_lots" : "repaired_my_lots",
      winnerUid,
      prizeId: prizeRef.id,
    };
  });

  return result;
}

async function notifyAnimationWinner(animationId, animationRef, drawResult) {
  const { winnerUid, winnerEmail, winnerLabel, claimCode } = drawResult;
  const animationSnap = await animationRef.get();
  const animationData = animationSnap.exists ? animationSnap.data() || {} : {};
  const prizeDescription = getTrimmedString(animationData.prize_description);
  const animationName = getTrimmedString(animationData.name);
  const winnerFirstName = winnerLabel.split(/\s+/)[0] || "";
  const userRef = db.collection("users").doc(winnerUid);

  try {
    const mailer = createSmtpMailer();
    if (winnerEmail) {
      const subject = "Vous avez gagne le gros lot !";
      const html = `
        <p>Felicitations ${winnerFirstName || ""} !</p>
        <p>Vous avez ete tire au sort et remportez : <strong>${prizeDescription}</strong></p>
        <p>Votre code de reclamation : <strong>${claimCode}</strong></p>
        <p>L'equipe Proxiplay vous contactera pour organiser la remise du lot.</p>
      `;
      const text = [
        `Felicitations ${winnerFirstName || ""} !`,
        `Vous avez ete tire au sort et remportez : ${prizeDescription}`,
        `Votre code de reclamation : ${claimCode}`,
        "L'equipe Proxiplay vous contactera pour organiser la remise du lot.",
      ].join("\n");
      await sendEmailNotification(mailer, winnerEmail, subject, text, html);
    }
    await queuePushNotificationRequest(db, {
      title: "Vous avez gagne le gros lot !",
      body: `Felicitations ! Vous remportez : ${prizeDescription}`,
      userRefOrPath: userRef,
      createdBy: `system/draw_animation_winners/${animationId}`,
    });
  } catch (notificationError) {
    functions.logger.error(
      'ANIMATION_NOTIFICATION_FAILED',
      {animationId, code: notificationError.code || null},
    );
  }

  const participatingGamesSnap = await db
    .collection("games")
    .where("animation_id", "==", animationId)
    .get();

  const ownerRefsSeen = new Set();
  for (const gameDoc of participatingGamesSnap.docs) {
    try {
      const gameData = gameDoc.data() || {};
      const enseigneRef = gameData.enseigne_ref || gameData.enseigne_id || null;
      if (!enseigneRef || typeof enseigneRef.get !== "function") continue;

      const enseigneSnap = await enseigneRef.get();
      if (!enseigneSnap.exists) continue;

      const enseigneData = enseigneSnap.data() || {};
      const ownerRef = enseigneData.owner || null;
      if (!ownerRef || typeof ownerRef.id !== "string") continue;
      if (ownerRefsSeen.has(ownerRef.id)) continue;
      // Meme politique que notifyPrizeWon : une enseigne geree par Proxiplay
      // ne recoit plus l'annonce marchand du gagnant, ici pour le gros lot
      // d'animation. Ne consomme pas la dedup ownerRefsSeen pour ne pas
      // bloquer une autre fiche non geree du meme proprietaire.
      if (!shouldNotifyMerchantForPrize(enseigneData)) continue;
      ownerRefsSeen.add(ownerRef.id);

      const ownerSnap = await ownerRef.get();
      if (!ownerSnap.exists) continue;

      await queuePushNotificationRequest(db, {
        title: `Tirage au sort : ${animationName}`,
        body: `Un gagnant a ete designe pour le gros lot de l'animation.`,
        userRefOrPath: ownerRef,
        createdBy: `system/draw_animation_winners/${animationId}`,
      });
    } catch (merchantNotifError) {
      functions.logger.error(
        'ANIMATION_MERCHANT_NOTIFICATION_FAILED',
        {animationId, gameId: gameDoc.id, code: merchantNotifError.code || null},
      );
    }
  }

  functions.logger.info("drawAnimationWinners: winner drawn", {
    animationId,
    merchantsNotified: ownerRefsSeen.size,
  });
}

// Tourne chaque nuit à minuit (Europe/Paris).
// Traite toutes les animations "active" dont end_date est passée et sans gagnant.
//
// runWith/concurrency/timeBudgetMs ajoutes avec la restructuration Phase
// 1/2/3 ci-dessus, par coherence avec pickMainPrizeWinners (main_prize_
// draw.js) qui avait besoin exactement de la meme marge pour la meme
// raison : Phase 1 fait maintenant un travail O(N) (lectures batchees)
// HORS transaction -- deplace, pas supprime -- donc le meme besoin de
// marge CPU/temps pour deserialiser potentiellement des milliers
// d'entries s'applique ici. Avant ce changement, cette fonction tournait
// aux limites Gen1 par defaut (60s/256MB, jamais declarees explicitement)
// ET en serie stricte (concurrency implicite = 1, aucun budget temps) :
// une seule animation bloquee (ex. en boucle de repli) aurait empeche
// toutes les suivantes d'etre meme tentees avant le timeout de la
// invocation entiere -- risque explicitement souleve par l'audit.
exports.drawAnimationWinners = functions.runWith({timeoutSeconds: 300, memory: "1GB"}).pubsub
  .schedule("0 0 * * *")
  .timeZone("Europe/Paris")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    return runScheduledDraws({
      name: "drawAnimationWinners",
      logger: functions.logger,
      concurrency: 8,
      timeBudgetMs: 270000,
      load: async () => {
        const animationsSnap = await db
          .collection("animations")
          .where("status", "==", "active")
          .where("end_date", "<=", now)
          .get();

        return animationsSnap.docs.filter(
          (doc) => !getTrimmedString((doc.data() || {}).winner_uid)
        );
      },
      draw: (doc) => drawWinnerForAnimation(doc.id, {now}),
    });
  });

exports.drawWinnerForAnimation = drawWinnerForAnimation;
exports.repairAnimationDraw = repairAnimationDraw;
exports.isExcludedAccount = isExcludedAccount;
exports.loadEligibleAnimationCandidates = loadEligibleAnimationCandidates;
exports.ANIMATION_MAX_CANDIDATE_ATTEMPTS = ANIMATION_MAX_CANDIDATE_ATTEMPTS;
