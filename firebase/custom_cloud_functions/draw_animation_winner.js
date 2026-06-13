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

  return {
    host,
    port,
    secure,
    user,
    pass,
    fromEmail,
    fromName,
    replyTo,
  };
}

function createSmtpMailer() {
  const settings = getSmtpSettings();
  return {
    transporter: nodemailer.createTransport({
      host: settings.host,
      port: settings.port,
      secure: settings.secure,
      auth: {
        user: settings.user,
        pass: settings.pass,
      },
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
    const animationsSnap = await db
      .collection("animations")
      .where("status", "==", "active")
      .where("end_date", "<=", now)
      .get();

    const eligibleAnimations = animationsSnap.docs.filter((doc) => {
      const animationData = doc.data() || {};
      return !getTrimmedString(animationData.winner_uid);
    });

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

        const qualifiedEntriesSnap = await animationRef
          .collection("entries")
          .where("threshold_reached", "==", true)
          .get();

        if (qualifiedEntriesSnap.empty) {
          skipped += 1;
          functions.logger.info(
            `scheduledDrawAnimationWinners: no qualified entries for animationId=${animationId}`
          );
          continue;
        }

        const qualifiedEntries = qualifiedEntriesSnap.docs;
        const randomIndex = Math.floor(Math.random() * qualifiedEntries.length);
        const winnerEntry = qualifiedEntries[randomIndex];
        const winnerUid = winnerEntry.id;
        const userRef = db.collection("users").doc(winnerUid);
        const userSnap = await userRef.get();
        const userData = userSnap.exists ? userSnap.data() || {} : {};
        const winnerEmail = getTrimmedString(userData.email);
        const winnerName = getTrimmedString(userData.first_name);

        await animationRef.set(
          {
            winner_uid: winnerUid,
            winner_ref: userRef,
            drawn_at: admin.firestore.FieldValue.serverTimestamp(),
            status: "ended",
          },
          { merge: true }
        );

        await db.collection("prizes").add({
          prize_type: "principal",
          name: prizeDescription,
          winner_id: userRef,
          animation_id: animationRef,
          claimed: false,
          win_date: admin.firestore.FieldValue.serverTimestamp(),
        });

        try {
          const mailer = createSmtpMailer();

          if (winnerEmail) {
            const subject = "\uD83C\uDF89 Vous avez gagn\u00E9 le gros lot !";
            const html = `
        <p>F\u00E9licitations ${winnerName || ""} ! Vous avez \u00E9t\u00E9 tir\u00E9 au sort et remportez : ${prizeDescription}</p>
        <p>L'\u00E9quipe Proxiplay vous contactera pour organiser la remise du lot.</p>
      `;
            const text = [
              `F\u00E9licitations ${winnerName || ""} ! Vous avez \u00E9t\u00E9 tir\u00E9 au sort et remportez : ${prizeDescription}`,
              "L'\u00E9quipe Proxiplay vous contactera pour organiser la remise du lot.",
            ].join("\n");

            await sendEmailNotification(mailer, winnerEmail, subject, text, html);
          }

          await queuePushNotificationRequest(db, {
            title: "\uD83C\uDF89 Vous avez gagn\u00E9 le gros lot !",
            body: `F\u00E9licitations ! Vous remportez : ${prizeDescription}`,
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
          winnerName,
          qualifiedEntriesCount: qualifiedEntries.length,
          contextEventId: context?.eventId || null,
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
      contextEventId: context?.eventId || null,
    });

    return null;
  });
