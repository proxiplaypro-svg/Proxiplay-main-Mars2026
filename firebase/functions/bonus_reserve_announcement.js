// Notification push unique annoncant la reserve de parties bonus (1.1.4).
//
// PREPAREE, JAMAIS ENVOYEE AUTOMATIQUEMENT : aucun declencheur ni tache
// planifiee n'appelle queueBonusReserveAnnouncement. L'envoi se fait a la
// main, apres publication sur les stores, avec
// scripts/queue_bonus_reserve_announcement.js (voir
// docs/bonus-reserve-announcement-1.1.4.md).
//
// Unicite : le document ff_push_notifications a un identifiant fixe et il
// est cree avec create(), qui echoue s'il existe deja. Un second lancement
// ne renvoie donc jamais la notification.
//
// Cible : le groupe "Players" (role joueur seulement), traite par
// matchesTargetUserGroup. Il faut que sendPushNotificationsTrigger connaisse
// ce groupe AVANT l'envoi : l'ancienne version traite un groupe inconnu
// comme "All" (commercants et administrateurs compris).
const admin = require("firebase-admin");

const kBonusReserveAnnouncementDocId = "announcement_bonus_reserve_1_1_4";
const kPlayersUserGroup = "Players";

const kBonusReserveAnnouncement = Object.freeze({
  title: "🎁 Vos parties bonus ne disparaissent plus !",
  body: "Conservez vos parties bonus et utilisez-les quand vous voulez. " +
    "Mettez ProxiPlay à jour pour en profiter !",
  // Un appui ouvre l'accueil joueur, qui existe dans toutes les versions.
  initialPageName: "HomeJoueurPage",
});

/**
 * Groupe cible d'une notification groupee (sendPushNotifications).
 * Les groupes existants sont inchanges ; "Players" ne vise que les joueurs.
 */
function matchesTargetUserGroup(targetUserGroup, role) {
  const isAdmin = role === "admin";
  const isProfessional = role === "commercant";
  switch (targetUserGroup) {
    case "Admins":
      return isAdmin;
    case "Professionals":
      return isProfessional;
    case "NormalUsers":
      return !isAdmin;
    case kPlayersUserGroup:
      return role === "joueur";
    default:
      return true;
  }
}

function buildBonusReserveAnnouncementRequest({createdBy}) {
  return {
    notification_title: kBonusReserveAnnouncement.title,
    notification_text: kBonusReserveAnnouncement.body,
    notification_image_url: "",
    notification_sound: "",
    parameter_data: "",
    initial_page_name: kBonusReserveAnnouncement.initialPageName,
    target_audience: "All",
    target_user_group: kPlayersUserGroup,
    user_refs: "",
    status: "started",
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    created_by: createdBy || "script/queue_bonus_reserve_announcement",
    announcement: "bonus_reserve_1_1_4",
  };
}

/**
 * Met la notification en file une seule fois. Renvoie "queued" ou
 * "already_queued" (document deja present : rien n'est renvoye).
 */
async function queueBonusReserveAnnouncement(db, {createdBy} = {}) {
  const ref = db.collection("ff_push_notifications").doc(kBonusReserveAnnouncementDocId);
  try {
    await ref.create(buildBonusReserveAnnouncementRequest({createdBy}));
    return {status: "queued", path: ref.path};
  } catch (error) {
    // ALREADY_EXISTS (gRPC 6).
    if (error && (error.code === 6 || /already exists/i.test(String(error.message)))) {
      return {status: "already_queued", path: ref.path};
    }
    throw error;
  }
}

module.exports = {
  buildBonusReserveAnnouncementRequest,
  kBonusReserveAnnouncement,
  kBonusReserveAnnouncementDocId,
  kPlayersUserGroup,
  matchesTargetUserGroup,
  queueBonusReserveAnnouncement,
};
