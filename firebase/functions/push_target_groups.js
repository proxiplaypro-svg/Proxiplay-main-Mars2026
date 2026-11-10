// Groupes cibles des notifications groupees (sendPushNotifications).
//
// Groupes historiques inchanges : "All", "Admins", "Professionals",
// "NormalUsers" (tous sauf administrateurs, commercants compris).
//
// "Players" (1.1.4) : joueurs seulement, avec des conditions strictes.
//  - Le role est lu dans le profil users/{uid}, jamais dans le document du
//    jeton (champ user_role eventuel, qui peut etre perime).
//  - Profil absent, supprime, suspendu ou refuse : exclu.
//  - Un jeton porte par plusieurs comptes (telephone partage) n'est retenu
//    que si TOUS ces comptes sont des joueurs eligibles : un commercant ou
//    un administrateur ne recoit jamais un envoi "Players".
//  - Pas de jeton = pas d'envoi : le jeton n'existe que si le joueur a
//    autorise les notifications sur son telephone, et il est retire a la
//    deconnexion (fcm_device_detach.dart) et a la suppression du compte.
const kPlayersUserGroup = "Players";

function text(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

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

/** Profil eligible au groupe "Players". */
function isPlayersGroupRecipient(userData) {
  if (!userData || typeof userData !== "object") return false;
  if (userData.user_role !== "joueur") return false;
  if (userData.deleted === true || userData.auto_deleted === true) return false;
  if (["rejected", "suspended"].includes(text(userData.account_status))) return false;
  if (["suspended", "suspendu"].includes(text(userData.player_status_cached))) return false;
  return true;
}

/**
 * entries : [{token, ref, eligible}] (un par document de jeton).
 * Renvoie [{token, refs}] pour les jetons dont tous les porteurs sont
 * eligibles.
 */
function selectPlayersGroupTokens(entries) {
  const byToken = new Map();
  for (const entry of entries) {
    if (!entry || !entry.token) continue;
    const current = byToken.get(entry.token) || {token: entry.token, refs: [], eligible: true};
    current.refs.push(entry.ref);
    current.eligible = current.eligible && entry.eligible === true;
    byToken.set(entry.token, current);
  }
  return [...byToken.values()]
    .filter((item) => item.eligible)
    .map(({token, refs}) => ({token, refs}));
}

module.exports = {
  isPlayersGroupRecipient,
  kPlayersUserGroup,
  matchesTargetUserGroup,
  selectPlayersGroupTokens,
};
