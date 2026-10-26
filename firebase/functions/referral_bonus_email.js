// Congratulation e-mail to the inviter when the "all games until midnight"
// referral bonus is actually granted (reward_events/{referralId} is created
// in the grant transaction). Separate from the prize e-mails: it only reuses
// the SMTP sender passed in.
//
// Idempotent: the event is claimed once (email_status) in a transaction; an
// e-mail whose sending did not complete is never resent automatically. A
// failure never touches the bonus, already granted before this runs.
const admin = require("firebase-admin");
const functions = require("firebase-functions");
const {excluded} = require("./prize_integrity");

const kReferralBonusEmailSubject = "🎉 Bravo, ton parrainage a fonctionné !";
const kReferralBonusEmailText = [
  "🎉 Bravo, ton parrainage a fonctionné !",
  "",
  "Ton filleul s'est inscrit grâce à toi !",
  "Tu peux maintenant jouer à tous les jeux jusqu'à minuit.",
  "Profite de ton bonus !",
  "",
  "L'équipe ProxiPlay",
].join("\n");

const kEmailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

async function processReferralBonusEmail(db, eventId, {send, nowMs = () => Date.now()}) {
  const eventRef = db.doc(`reward_events/${eventId}`);
  const stamp = () => admin.firestore.FieldValue.serverTimestamp();
  const claim = await db.runTransaction(async (tx) => {
    const event = (await tx.get(eventRef)).data();
    if (!event) return {status: "missing_event"};
    if (event.email_status) return {status: `already_${event.email_status}`};
    const skip = (reason) => {
      tx.update(eventRef, {email_status: "skipped", email_reason: reason, email_updated_at: stamp()});
      return {status: "skipped", reason};
    };
    if (event.type !== "all_games_until_midnight") return skip("not_all_games_bonus");
    const [userSnap, referralSnap] = await Promise.all([
      tx.get(db.doc(`users/${event.uid}`)),
      tx.get(db.doc(`referrals/${event.referralId}`)),
    ]);
    const user = userSnap.data();
    const referral = referralSnap.data();
    // Recipient: the inviter of this very referral, a player account.
    if (!referral || referral.inviterUid !== event.uid || referral.rewardStatus !== "granted") {
      return skip("referral_mismatch");
    }
    if (!user || excluded(user)) return skip("inviter_ineligible");
    const role = String(user.user_role || user.userRole || "").trim();
    if (role !== "joueur") return skip("not_a_player");
    const access = user.allGamesAccessUntil;
    if (typeof access?.toMillis !== "function" || access.toMillis() <= nowMs()) {
      return skip("bonus_expired");
    }
    const to = String(user.email || "").trim().toLowerCase();
    if (!kEmailPattern.test(to) || to.length > 254) return skip("no_valid_email");
    tx.update(eventRef, {email_status: "sending", email_updated_at: stamp()});
    return {status: "claimed", to};
  });
  if (claim.status !== "claimed") return claim;
  try {
    await send(claim.to, kReferralBonusEmailSubject, kReferralBonusEmailText);
  } catch (error) {
    const code = String(error?.code || error?.responseCode || "smtp_error").slice(0, 60);
    functions.logger.error("REFERRAL_BONUS_EMAIL_FAILED", {eventId, code});
    await eventRef.update({email_status: "failed", email_reason: code, email_updated_at: stamp()});
    return {status: "failed", reason: code};
  }
  await eventRef.update({email_status: "sent", email_updated_at: stamp()});
  return {status: "sent"};
}

module.exports = {
  processReferralBonusEmail,
  kReferralBonusEmailSubject,
  kReferralBonusEmailText,
};
