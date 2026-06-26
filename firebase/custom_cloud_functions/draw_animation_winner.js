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
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["true", "1", "yes", "y", "on"].includes(normalized)) {
      return true;
    }
    if (["false", "0", "no", "n", "off"].includes(normalized)) {
      return false;
    }
  }
  if (typeof value === "number") {
    return value !== 0;
  }
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
  if (missing.length > 0) {
    throw new Error(`Missing SMTP config: ${missing.join(", ")}`);
  }

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

async function sendEmailNotification(mailer, to, subject, text, html = "") {
  await mailer.transporter.sendMail({
    from: mailer.from,
    to,
    subject,
    text,
    ...(html ? { html } : {}),
    ...(mailer.replyTo ? { replyTo: mailer.replyTo } : {}),
  });
}

exports.scheduledDrawAnimationWinners = functions.pubsub
  .schedule("every 60 minutes")
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();

    // Animations actives dont la date de fin est passée
    const animationsSnap = await db
      .collection("animations")
      .where("status", "==", "active")
      .where("end_date", "<=", now)
      .get();

    // Uniquement celles sans gagnant déjà tiré
    const eligibleAnimations = animationsSnap.docs.filter((doc) => {
      const data = doc.data() || {};
      return !getTrimmedString(data.winner_uid);
    });

    // Charge tous les documents de progression qualifiés (users/{uid}/animations/{animId})
    // même approche que l'API admin /api/admin/animations/[id]/detail
    const allProgressSnap = await db
      .collectionGroup("animations")
      .where("qualified", "==", true)
      .get();

    let processed = 0;
    let drawn = 0;
    let skipped = 0;
    let failed = 0;

    for (const animationSnap of eligibleAnimations) {
      const animationId = animationSnap.id;

      try {
        processed += 1;

        const animationRef = animationSnap.ref;
        const animationData = animationSnap.data() || {};
        const prizeDescription = getTrimmedString(animationData.prize_description);

        // Filtre les joueurs qualifiés pour cette animation spécifique
        // users/{uid}/animations/{animationId} — doc.id === animationId
        const qualifiedEntries = allProgressSnap.docs.filter((doc) => {
          const uid = doc.ref.parent.parent && doc.ref.parent.parent.id;
          return doc.id === animationId && typeof uid === "string" && uid.length > 0;
        });

        if (qualifiedEntries.length === 0) {
          skipped += 1;
          functions.logger.info(
            `scheduledDrawAnimationWinners: no qualified entries for animationId=${animationId}`
          );
          continue;
        }

        // Tirage aléatoire
        const randomIndex = Math.floor(Math.random() * qualifiedEntries.length);
        const winnerEntry = qualifiedEntries[randomIndex];
        const winnerUid = winnerEntry.ref.parent.parent.id;

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

        // Met à jour le document animation : winner_uid + status ended
        await animationRef.set(
          {
            winner_uid: winnerUid,
            winner_ref: userRef,
            drawn_at: drawnAt,
            status: "ended",
          },
          { merge: true }
        );

        // Crée le document prize dans prizes/
        // animation_id est stocké en string pour matcher la query de l'API admin
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
            createdBy: `system/scheduled_draw_animation_winners/${animationId}`,
          });
        } catch (notificationError) {
          functions.logger.error(
            `scheduledDrawAnimationWinners: notification failure for animationId=${animationId} winnerUid=${winnerUid}`,
            notificationError
          );
        }

        drawn += 1;
        functions.logger.info("scheduledDrawAnimationWinners: winner drawn", {
          animationId,
          winnerUid,
          winnerEmail,
          winnerLabel,
          qualifiedEntriesCount: qualifiedEntries.length,
          contextEventId: context && context.eventId || null,
        });
      } catch (error) {
        failed += 1;
        functions.logger.error(
          `scheduledDrawAnimationWinners: failed for animationId=${animationId}`,
          error
        );
      }
    }

    functions.logger.info("scheduledDrawAnimationWinners: run completed", {
      scannedAnimations: animationsSnap.size,
      eligibleAnimations: eligibleAnimations.length,
      processed,
      drawn,
      skipped,
      failed,
      contextEventId: context && context.eventId || null,
    });

    return null;
  });
