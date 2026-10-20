// Merchant "no active game" relaunch (scheduled daily from index.js).
//
// The production version queried only games with enseigne_id == shop ref,
// end_date > now and visible_public == true. A game still being played
// whose stale flags said visible_public:false / status:"brouillon" was
// therefore missed, and the merchant was told it had no active game.
// Here a game counts unless it is explicitly cancelled, whatever its
// visibility flag or draft status, and any doubt prevents the relaunch.

const ms7d = 7 * 24 * 60 * 60 * 1000;
const ms21d = 21 * 24 * 60 * 60 * 1000;
const kClosedStatuses = ["cancelled", "canceled", "annule", "annulé", "disabled", "deleted", "supprime", "supprimé"];

// Every field the app or the backend uses to attach a game to a shop.
function gameLinkQueries(db, shopRef) {
  return [
    ["enseigne_id", shopRef],
    ["enseigne_id", shopRef.path],
    ["enseigne_ref", shopRef],
    ["merchantRef", shopRef],
    ["merchant_id", shopRef.id],
    ["merchantId", shopRef.id],
  ].map(([field, value]) => db.collection("games").where(field, "==", value));
}

function millis(value) {
  return value && typeof value.toMillis === "function" ? value.toMillis() : null;
}

// Returns the reason a game prevents the relaunch, or null when it does not.
// A game without a readable end date is treated as possibly running.
function blockingReason(game, nowMs) {
  const status = String(game.status || "").trim().toLowerCase();
  if (kClosedStatuses.includes(status) || game.deleted === true) return null;
  const endMs = millis(game.end_date) ?? millis(game.endDate);
  if (endMs == null) return "game_without_end_date";
  if (endMs <= nowMs) return null;
  const startMs = millis(game.start_date) ?? millis(game.startDate);
  return startMs != null && startMs > nowMs ? "upcoming_game" : "active_game";
}

// Throws on any read error so that the caller never relaunches by default.
async function findBlockingGame(db, shopRef, nowMs) {
  const snaps = await Promise.all(gameLinkQueries(db, shopRef).map((q) => q.get()));
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      const reason = blockingReason(doc.data() || {}, nowMs);
      if (reason) return {gameId: doc.id, reason};
    }
  }
  return null;
}

function relaunchTier(shop, nowMs, {delay7dEnabled, delay21dEnabled}) {
  const lastGameMs = millis(shop.last_game_created_at) ??
    millis(shop.created_time || shop.created_at) ?? 0;
  const ageMs = nowMs - lastGameMs;
  if (delay21dEnabled && ageMs >= ms21d) return "21d";
  if (delay7dEnabled && ageMs >= ms7d && ageMs < ms21d) return "7d";
  return null;
}

function relaunchMessages(tier, enseigneName, ownerFirstName) {
  if (tier === "7d") {
    return {
      title: "Votre vitrine ProxiPlay vous attend \u{1F3AF}",
      body: `${enseigneName} n'a pas de jeu actif depuis 7 jours. Créez un nouveau jeu pour attirer vos clients !`,
      emailSubject: `[${ownerFirstName}], vos joueurs vous attendent sur ProxiPlay`,
      emailBody: `Bonjour ${ownerFirstName},\n\nVotre enseigne ${enseigneName} n'a pas de jeu actif en ce moment sur ProxiPlay.\n\nVos joueurs passent chaque jour sur l'application - sans jeu actif, ils ne voient pas votre enseigne et jouent chez vos concurrents.\n\nCréer un jeu prend moins de 5 minutes. C'est le moyen le plus simple de garder votre vitrine visible et d'attirer du trafic en boutique.\n\nConnectez-vous et créez votre prochain jeu dès aujourd'hui.\n\nÀ très vite,\nL'équipe ProxiPlay`,
    };
  }
  return {
    title: "Vos joueurs vous cherchent ! \u{1F514}",
    body: `Cela fait 21 jours que ${enseigneName} n'a pas publié de jeu. Votre abonnement ne travaille pas pour vous - revenez !`,
    emailSubject: `[${ownerFirstName}], votre abonnement ProxiPlay ne travaille pas pour vous`,
    emailBody: `Bonjour ${ownerFirstName},\n\nCela fait plus de 3 semaines que ${enseigneName} n'a pas publié de jeu sur ProxiPlay.\n\nPendant ce temps, votre abonnement court - mais vos joueurs ne vous voient plus. D'autres commerçants publient des jeux et captent leur attention.\n\nProxiPlay fonctionne quand vous jouez le jeu. Un nouveau jeu aujourd'hui, c'est du trafic en boutique dès demain.\n\nReprenez votre place sur ProxiPlay maintenant.\n\nOn est là si vous avez besoin d'aide.\nL'équipe ProxiPlay`,
  };
}

// deps: {db, admin, now, logger, getOwnerContact(ownerRef) -> {email, firstName, hasPushToken},
//        sendEmail(to, subject, body), pushCollection, toDocRef, getTrimmedString}
async function runMerchantRelaunch(deps) {
  const {db, admin, logger, toDocRef, getTrimmedString} = deps;
  const nowMs = deps.now ?? Date.now();
  const stats = {sent7d: 0, sent21d: 0, skipped: 0, errors: 0};
  const config = (await db.collection("app_config").doc("notifications_auto").get()).data() || {};
  if (config.merchant_relaunch_enabled !== true) {
    logger.log("[relaunchInactiveMerchants] disabled, skipping");
    return {...stats, disabled: true};
  }
  const options = {
    delay7dEnabled: config.merchant_relaunch_delay_7d_enabled !== false,
    delay21dEnabled: config.merchant_relaunch_delay_21d_enabled !== false,
  };
  const shops = await db.collection("enseignes").get();
  for (const shopDoc of shops.docs) {
    const shop = shopDoc.data() || {};
    const ownerRef = toDocRef(shop.owner);
    if (!ownerRef) { stats.skipped++; continue; }

    let blocking;
    try {
      blocking = await findBlockingGame(db, shopDoc.ref, nowMs);
    } catch (error) {
      stats.errors++;
      logger.error(`[relaunchInactiveMerchants] enseigne=${shopDoc.id} decision=skip reason=games_read_failed error=${error.message || error}`);
      continue;
    }
    if (blocking) {
      stats.skipped++;
      logger.log(`[relaunchInactiveMerchants] enseigne=${shopDoc.id} decision=skip reason=${blocking.reason} game=${blocking.gameId}`);
      continue;
    }

    const tier = relaunchTier(shop, nowMs, options);
    if (!tier) { stats.skipped++; continue; }
    const antiDupField = tier === "7d" ? "last_relaunch_notif_7d_at" : "last_relaunch_notif_21d_at";
    const lastNotifMs = millis(shop[antiDupField]);
    if (lastNotifMs != null && nowMs - lastNotifMs < (tier === "7d" ? ms7d : ms21d)) {
      stats.skipped++;
      continue;
    }

    try {
      const owner = await deps.getOwnerContact(ownerRef);
      if (!owner.hasPushToken && !owner.email) { stats.skipped++; continue; }
      const enseigneName = getTrimmedString(shop.name) || "votre enseigne";
      const message = relaunchMessages(tier, enseigneName, getTrimmedString(owner.firstName) || "Bonjour");
      if (owner.hasPushToken) {
        await db.collection(deps.pushCollection)
          .doc(`merchant_relaunch_${shopDoc.id}_${tier}_${nowMs}`)
          .set({
            notification_title: message.title,
            notification_text: message.body,
            notification_image_url: "",
            notification_sound: "",
            parameter_data: "",
            initial_page_name: "",
            target_audience: "All",
            target_user_group: "All",
            user_refs: ownerRef.path,
            status: "started",
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            created_by: "system/merchant_relaunch",
          });
      }
      if (owner.email) {
        try {
          await deps.sendEmail(owner.email, message.emailSubject, message.emailBody);
        } catch (emailError) {
          stats.errors++;
          logger.error(`[relaunchInactiveMerchants] enseigne=${shopDoc.id} email_error=${emailError.message || emailError}`);
        }
      }
      await shopDoc.ref.set({[antiDupField]: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
      if (tier === "7d") stats.sent7d++; else stats.sent21d++;
      logger.log(`[relaunchInactiveMerchants] enseigne=${shopDoc.id} decision=send palier=${tier}`);
    } catch (error) {
      stats.errors++;
      logger.error(`[relaunchInactiveMerchants] enseigne=${shopDoc.id} error=${error.message || error}`);
    }
  }
  return stats;
}

module.exports = {runMerchantRelaunch, findBlockingGame, blockingReason, relaunchTier};
