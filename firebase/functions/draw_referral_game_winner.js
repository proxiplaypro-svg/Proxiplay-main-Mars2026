const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");
const nodemailer = require("nodemailer");
const {
  queuePushNotificationRequest,
} = require("./push_notification_request.js");
const { pickWinningTicket } = require("./lib/referral_games_core");

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
    code += chars[crypto.randomInt(0, chars.length)];
  }
  return code;
}

// Tire un ticket au hasard parmi referral_games/{id}/entries : un document
// par parrainage valide (le filleul a utilise le code pour creer son compte),
// cree uniquement cote serveur par registerReferralAcceptance. Un joueur qui
// a parraine plusieurs fois a donc mecaniquement plusieurs tickets et donc
// plus de chances, sans algorithme de ponderation dedie.
async function drawWinnerForReferralGame(gameRef, gameId, gameData) {
  const prizeDescription = getTrimmedString(gameData.prize_description);
  const gameTitle = getTrimmedString(gameData.title);

  const entriesSnap = await gameRef.collection("entries").get();
  if (entriesSnap.empty) {
    functions.logger.info(
      `drawReferralGameWinner: no entries for gameId=${gameId}`
    );
    await gameRef.set(
      { status: "ended", drawn_at: admin.firestore.Timestamp.now() },
      { merge: true }
    );
    return;
  }

  const ticketDocs = entriesSnap.docs;
  const drawResult = pickWinningTicket(
    ticketDocs.map((doc) => doc.data() || {})
  );
  const winnerUid = drawResult ? drawResult.winnerUid : "";
  const winnerTicketCount = drawResult ? drawResult.winnerTicketCount : 0;
  const tickets = ticketDocs;

  if (!winnerUid) {
    functions.logger.error(
      `drawReferralGameWinner: winning ticket has no inviter_uid, gameId=${gameId}`
    );
    return;
  }

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

  // winner_uid sur le document du jeu = garde-fou contre double tirage
  await gameRef.set(
    {
      winner_uid: winnerUid,
      winner_ref: userRef,
      winner_ticket_count: winnerTicketCount,
      total_ticket_count: tickets.length,
      drawn_at: drawnAt,
      status: "ended",
    },
    { merge: true }
  );

  const denormalizedWinnerFirstName = winnerFirstName.split(/\s+/)[0] || "";
  const denormalizedWinnerCity = getTrimmedString(userData.city);
  const denormalizedWinnerFields = {
    ...(denormalizedWinnerFirstName
      ? {
          winnerFirstName: denormalizedWinnerFirstName,
          winner_first_name: denormalizedWinnerFirstName,
        }
      : {}),
    ...(denormalizedWinnerCity
      ? { winnerCity: denormalizedWinnerCity, winner_city: denormalizedWinnerCity }
      : {}),
  };

  const prizeRef = db.collection("prizes").doc();
  await prizeRef.set({
    prize_type: "principal",
    name: prizeDescription || gameTitle || "Lot parrainage",
    description: prizeDescription,
    prize_label: prizeDescription,
    winner_id: userRef,
    referral_game_id: gameId,
    claim_code: claimCode,
    claimed: false,
    win_date: drawnAt,
    ...denormalizedWinnerFields,
  });

  await db.collection("users").doc(winnerUid).collection("my_lots").add({
    prize_id: prizeRef,
  });

  try {
    const mailer = createSmtpMailer();
    if (winnerEmail) {
      const subject = "Vous avez gagne le tirage au sort parrainage !";
      const html = `
        <p>Felicitations ${winnerFirstName || ""} !</p>
        <p>Grace a vos parrainages, vous avez ete tire au sort et remportez : <strong>${prizeDescription}</strong></p>
        <p>Votre code de reclamation : <strong>${claimCode}</strong></p>
        <p>L'equipe Proxiplay vous contactera pour organiser la remise du lot.</p>
      `;
      const text = [
        `Felicitations ${winnerFirstName || ""} !`,
        `Grace a vos parrainages, vous avez ete tire au sort et remportez : ${prizeDescription}`,
        `Votre code de reclamation : ${claimCode}`,
        "L'equipe Proxiplay vous contactera pour organiser la remise du lot.",
      ].join("\n");
      await sendEmailNotification(mailer, winnerEmail, subject, text, html);
    }
    await queuePushNotificationRequest(db, {
      title: "Vous avez gagne le tirage au sort parrainage !",
      body: `Felicitations ! Vous remportez : ${prizeDescription}`,
      userRefOrPath: userRef,
      createdBy: `system/draw_referral_game_winner/${gameId}`,
    });
  } catch (notificationError) {
    functions.logger.error(
      `drawReferralGameWinner: winner notification failure gameId=${gameId} winnerUid=${winnerUid}`,
      notificationError
    );
  }

  functions.logger.info("drawReferralGameWinner: winner drawn", {
    gameId,
    winnerUid,
    winnerEmail,
    winnerLabel,
    claimCode,
    winnerTicketCount,
    totalTicketCount: tickets.length,
  });
}

// Tourne chaque nuit a minuit (Europe/Paris).
// Traite tous les jeux de parrainage "active" dont end_date est passee et
// sans gagnant.
exports.drawReferralGameWinner = functions.pubsub
  .schedule("0 0 * * *")
  .timeZone("Europe/Paris")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    const gamesSnap = await db
      .collection("referral_games")
      .where("status", "==", "active")
      .where("end_date", "<=", now)
      .get();

    const eligible = gamesSnap.docs.filter(
      (doc) => !getTrimmedString((doc.data() || {}).winner_uid)
    );

    functions.logger.info("drawReferralGameWinner: run started", {
      total: gamesSnap.size,
      eligible: eligible.length,
    });

    for (const doc of eligible) {
      try {
        await drawWinnerForReferralGame(doc.ref, doc.id, doc.data() || {});
      } catch (error) {
        functions.logger.error(
          `drawReferralGameWinner: failed for gameId=${doc.id}`,
          error
        );
      }
    }

    return null;
  });

exports.drawWinnerForReferralGame = drawWinnerForReferralGame;
