const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const {
  queuePushNotificationRequest,
} = require("./push_notification_request.js");

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

// Tirage transactionnel : selection du gagnant, ecriture du winner/current,
// du statut de l'animation, du prize (id deterministe animation_<id>, donc
// idempotent) et de my_lots se font dans UNE seule transaction Firestore.
// Avant ce correctif ces 5 ecritures etaient successives et independantes :
// un crash de la Function entre l'ecriture de winner_uid et la creation du
// prize laissait un "gagnant" officiel sans aucun lot dans "Mes lots", et le
// cron suivant ne le detectait jamais puisqu'il ne traite que les animations
// SANS winner_uid.
async function drawWinnerForAnimation(animationId, { now = admin.firestore.Timestamp.now() } = {}) {
  const animationRef = db.collection("animations").doc(animationId);

  const result = await db.runTransaction(async (transaction) => {
    const animationSnap = await transaction.get(animationRef);
    if (!animationSnap.exists) {
      return { status: "not_found" };
    }
    const animationData = animationSnap.data() || {};

    if (getTrimmedString(animationData.winner_uid)) {
      return { status: "already_drawn", winnerUid: getTrimmedString(animationData.winner_uid) };
    }

    // Joueurs qualifies : animations/{id}/entries/{uid} avec
    // threshold_reached == true. Ecrit par participateInGameTransaction
    // (source de verite CF).
    const entriesSnap = await transaction.get(
      animationRef.collection("entries").where("threshold_reached", "==", true),
    );

    if (entriesSnap.empty) {
      return { status: "no_qualified_entries" };
    }

    const candidates = [];
    for (const entryDoc of entriesSnap.docs) {
      const uid = entryDoc.id;
      const userRef = db.collection("users").doc(uid);
      const userSnap = await transaction.get(userRef);
      if (!userSnap.exists || isExcludedAccount(userSnap.data() || {})) {
        continue;
      }
      candidates.push({ uid, userRef, userData: userSnap.data() || {} });
    }

    if (candidates.length === 0) {
      transaction.set(
        animationRef,
        { status: "ended", draw_status: "no_eligible_entries", drawn_at: now },
        { merge: true },
      );
      return { status: "no_eligible_entries" };
    }

    const winner = candidates[Math.floor(Math.random() * candidates.length)];
    const winnerLabel = buildWinnerLabel(winner.userData);
    const winnerEmail = getTrimmedString(winner.userData.email);
    const claimCode = generateClaimCode();

    // Id deterministe (pas de doc() auto-id) : rejouer cette fonction sur la
    // meme animation reutilise le meme prize au lieu d'en creer un second.
    const prizeRef = db.collection("prizes").doc(`animation_${animationId}`);
    const prizeSnap = await transaction.get(prizeRef);
    if (!prizeSnap.exists) {
      transaction.set(
        prizeRef,
        buildPrizePayload(animationId, animationData, winner.userRef, now, claimCode, winner.userData),
      );
    }

    transaction.set(
      winner.userRef.collection("my_lots").doc(prizeRef.id),
      { prize_id: prizeRef, updated_at: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true },
    );

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
      eligibleCount: candidates.length,
    };
  });

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
      throw new Error("Winner no longer exists.");
    }
    const winnerData = winnerSnap.data() || {};

    const prizeRef = db.collection("prizes").doc(`animation_${animationId}`);
    const prizeSnap = await transaction.get(prizeRef);
    const drawnAt = animationData.drawn_at || admin.firestore.Timestamp.now();
    const claimCode = generateClaimCode();

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
      `drawAnimationWinners: winner notification failure animationId=${animationId} winnerUid=${winnerUid}`,
      notificationError,
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
        `drawAnimationWinners: merchant notification failure gameId=${gameDoc.id}`,
        merchantNotifError,
      );
    }
  }

  functions.logger.info("drawAnimationWinners: winner drawn", {
    animationId,
    winnerUid,
    winnerEmail,
    winnerLabel,
    claimCode,
    merchantsNotified: ownerRefsSeen.size,
  });
}

// Tourne chaque nuit à minuit (Europe/Paris).
// Traite toutes les animations "active" dont end_date est passée et sans gagnant.
exports.drawAnimationWinners = functions.pubsub
  .schedule("0 0 * * *")
  .timeZone("Europe/Paris")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    const animationsSnap = await db
      .collection("animations")
      .where("status", "==", "active")
      .where("end_date", "<=", now)
      .get();

    const eligible = animationsSnap.docs.filter(
      (doc) => !getTrimmedString((doc.data() || {}).winner_uid)
    );

    functions.logger.info("drawAnimationWinners: run started", {
      total: animationsSnap.size,
      eligible: eligible.length,
    });

    for (const doc of eligible) {
      try {
        const result = await drawWinnerForAnimation(doc.id, { now });
        functions.logger.info(
          `drawAnimationWinners: ${result.status} animationId=${doc.id}`,
        );
      } catch (error) {
        functions.logger.error(
          `drawAnimationWinners: failed for animationId=${doc.id}`,
          error
        );
      }
    }

    return null;
  });

exports.drawWinnerForAnimation = drawWinnerForAnimation;
exports.repairAnimationDraw = repairAnimationDraw;
exports.isExcludedAccount = isExcludedAccount;
