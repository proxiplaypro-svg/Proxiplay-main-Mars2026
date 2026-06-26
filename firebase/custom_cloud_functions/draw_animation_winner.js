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

async function drawWinnerForAnimation(animationRef, animationId, animationData) {
  const prizeDescription = getTrimmedString(animationData.prize_description);

  // Joueurs qualifiés : users/{uid}/animations/{animationId} avec qualified == true
  const progressSnap = await db
    .collectionGroup("animations")
    .where("qualified", "==", true)
    .get();

  const qualifiedEntries = progressSnap.docs.filter((doc) => {
    const uid = doc.ref.parent.parent && doc.ref.parent.parent.id;
    return doc.id === animationId && typeof uid === "string" && uid.length > 0;
  });

  if (qualifiedEntries.length === 0) {
    functions.logger.info(
      `drawAnimationWinners: no qualified entries for animationId=${animationId}`
    );
    return;
  }

  const randomIndex = Math.floor(Math.random() * qualifiedEntries.length);
  const winnerUid = qualifiedEntries[randomIndex].ref.parent.parent.id;

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

  const drawnAt = admin.firestore.FieldValue.serverTimestamp();

  // Écrit le gagnant dans animations/{id}/winner/current
  // (format attendu par l'API admin /api/admin/animations/[id]/detail)
  await animationRef.collection("winner").doc("current").set({
    uid: winnerUid,
    label: winnerLabel,
    email: winnerEmail,
    selected_at: drawnAt,
  });

  // Marque le gagnant + passe le statut à ended sur le document animation
  // winner_uid sert aussi de garde-fou contre un double tirage
  await animationRef.set(
    { winner_uid: winnerUid, winner_ref: userRef, drawn_at: drawnAt, status: "ended" },
    { merge: true }
  );

  // Crée le document prize (animation_id en string pour matcher les queries admin)
  await db.collection("prizes").add({
    prize_type: "principal",
    name: prizeDescription,
    prize_label: prizeDescription,
    winner_id: userRef,
    animation_id: animationId,
    claimed: false,
    win_date: drawnAt,
  });

  // Notifications
  try {
    const mailer = createSmtpMailer();
    if (winnerEmail) {
      const subject = "Vous avez gagne le gros lot !";
      const html = `
        <p>Felicitations ${winnerFirstName || ""} ! Vous avez ete tire au sort et remportez : ${prizeDescription}</p>
        <p>L'equipe Proxiplay vous contactera pour organiser la remise du lot.</p>
      `;
      const text = [
        `Felicitations ${winnerFirstName || ""} ! Vous avez ete tire au sort et remportez : ${prizeDescription}`,
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
      `drawAnimationWinners: notification failure animationId=${animationId} winnerUid=${winnerUid}`,
      notificationError
    );
  }

  functions.logger.info("drawAnimationWinners: winner drawn", {
    animationId,
    winnerUid,
    winnerEmail,
    winnerLabel,
    qualifiedEntriesCount: qualifiedEntries.length,
  });
}

// Tourne chaque nuit à minuit (heure de Paris).
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
