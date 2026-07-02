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

async function drawWinnerForAnimation(animationRef, animationId, animationData) {
  const prizeDescription = getTrimmedString(animationData.prize_description);
  const animationName = getTrimmedString(animationData.name);

  // Joueurs qualifiés : animations/{id}/entries/{uid} avec threshold_reached == true
  // Écrit par participateInGameTransaction (source de vérité CF)
  const entriesSnap = await animationRef
    .collection("entries")
    .where("threshold_reached", "==", true)
    .get();

  if (entriesSnap.empty) {
    functions.logger.info(
      `drawAnimationWinners: no qualified entries for animationId=${animationId}`
    );
    return;
  }

  const qualifiedEntries = entriesSnap.docs;
  const randomIndex = Math.floor(Math.random() * qualifiedEntries.length);
  const winnerUid = qualifiedEntries[randomIndex].id;

  const userRef = db.collection("users").doc(winnerUid);
  const userSnap = await userRef.get();
  const userData = userSnap.exists ? userSnap.data() || {} : {};
  const winnerEmail = getTrimmedString(userData.email);
  const winnerFirstName = getTrimmedString(userData.first_name || userData.firstName);
  const winnerDisplayName = getTrimmedString(userData.display_name || userData.displayName);
  const winnerLabel =
    winnerDisplayName ||
    [winnerFirstName, getTrimmedString(userData.last_name || userData.lastName)]
      .filter(Boolean)
      .join(" ") ||
    winnerEmail ||
    "Gagnant inconnu";

  const drawnAt = admin.firestore.Timestamp.now();
  const claimCode = generateClaimCode();

  // Gagnant dans animations/{id}/winner/current
  // Format attendu par l'API admin /api/admin/animations/[id]/detail
  await animationRef.collection("winner").doc("current").set({
    uid: winnerUid,
    label: winnerLabel,
    email: winnerEmail,
    selected_at: drawnAt,
  });

  // winner_uid sur le document animation = garde-fou contre double tirage
  await animationRef.set(
    { winner_uid: winnerUid, winner_ref: userRef, drawn_at: drawnAt, status: "ended" },
    { merge: true }
  );

  // Prize principal dans prizes/ — champs compatibles Flutter PrizesRecord
  const prizeRef = db.collection("prizes").doc();
  await prizeRef.set({
    prize_type: "principal",
    name: prizeDescription || animationName || "Gros lot",
    description: prizeDescription,
    prize_label: prizeDescription,
    winner_id: userRef,
    animation_id: animationId,
    claim_code: claimCode,
    claimed: false,
    win_date: drawnAt,
  });

  // my_lots : rend le lot visible dans "Mes lots" de l'app Flutter joueur
  await db.collection("users").doc(winnerUid).collection("my_lots").add({
    prize_id: prizeRef,
  });

  // Récupérer les commerçants participants pour les notifier
  const participatingGamesSnap = await db
    .collection("games")
    .where("animation_id", "==", animationId)
    .get();

  // Notification au gagnant (joueur)
  try {
    const mailer = createSmtpMailer();
    if (winnerEmail) {
      const subject = "Vous avez gagné le gros lot !";
      const html = `
        <p>Félicitations ${winnerFirstName || ""} !</p>
        <p>Vous avez été tiré au sort et remportez : <strong>${prizeDescription}</strong></p>
        <p>Votre code de réclamation : <strong>${claimCode}</strong></p>
        <p>L'équipe Proxiplay vous contactera pour organiser la remise du lot.</p>
      `;
      const text = [
        `Félicitations ${winnerFirstName || ""} !`,
        `Vous avez été tiré au sort et remportez : ${prizeDescription}`,
        `Votre code de réclamation : ${claimCode}`,
        "L'équipe Proxiplay vous contactera pour organiser la remise du lot.",
      ].join("\n");
      await sendEmailNotification(mailer, winnerEmail, subject, text, html);
    }
    await queuePushNotificationRequest(db, {
      title: "Vous avez gagné le gros lot !",
      body: `Félicitations ! Vous remportez : ${prizeDescription}`,
      userRefOrPath: userRef,
      createdBy: `system/draw_animation_winners/${animationId}`,
    });
  } catch (notificationError) {
    functions.logger.error(
      `drawAnimationWinners: winner notification failure animationId=${animationId} winnerUid=${winnerUid}`,
      notificationError
    );
  }

  // Notifications aux commerçants participants
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

      const ownerData = ownerSnap.data() || {};
      const merchantEmail = getTrimmedString(ownerData.email);
      const enseigneName = getTrimmedString(enseigneData.name || gameData.enseigne_name);

      const mailer = createSmtpMailer();
      if (merchantEmail) {
        const subject = `Un gagnant a été tiré au sort pour l'animation : ${animationName}`;
        const html = `
          <p>Bonjour ${enseigneName ? enseigneName : ""} !</p>
          <p>Le tirage au sort de l'animation <strong>${animationName}</strong> vient d'avoir lieu.</p>
          <p>Le gagnant du gros lot (<em>${prizeDescription}</em>) sera contacté par l'équipe Proxiplay.</p>
        `;
        const text = [
          `Bonjour ${enseigneName ? enseigneName : ""} !`,
          `Le tirage au sort de l'animation "${animationName}" vient d'avoir lieu.`,
          `Le gagnant du gros lot (${prizeDescription}) sera contacté par l'équipe Proxiplay.`,
        ].join("\n");
        await sendEmailNotification(mailer, merchantEmail, subject, text, html);
      }

      await queuePushNotificationRequest(db, {
        title: `Tirage au sort : ${animationName}`,
        body: `Un gagnant a été désigné pour le gros lot de l'animation.`,
        userRefOrPath: ownerRef,
        createdBy: `system/draw_animation_winners/${animationId}`,
      });
    } catch (merchantNotifError) {
      functions.logger.error(
        `drawAnimationWinners: merchant notification failure gameId=${gameDoc.id}`,
        merchantNotifError
      );
    }
  }

  functions.logger.info("drawAnimationWinners: winner drawn", {
    animationId,
    winnerUid,
    winnerEmail,
    winnerLabel,
    claimCode,
    qualifiedCount: qualifiedEntries.length,
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
        await drawWinnerForAnimation(doc.ref, doc.id, doc.data() || {});
      } catch (error) {
        functions.logger.error(
          `drawAnimationWinners: failed for animationId=${doc.id}`,
          error
        );
      }
    }

    return null;
  });
