// Single publication rule for games, mirrored in the app
// (lib/utils/player_game_visibility.dart) and the Admin
// (lib/admin/gamePublication.ts). Keep the three in sync.
//
// Draft flags can be stale: some games created as drafts were played by
// hundreds of players before 1.1.2 started enforcing them. Such a game keeps
// running when the server-maintained counters prove it was really launched;
// a draft without that evidence stays unavailable, and an explicit
// cancellation always wins.

const kClosedStatuses = new Set([
  "cancelled", "canceled", "annule", "annulé", "disabled", "desactive",
  "désactivé", "deleted", "supprime", "supprimé",
]);
const kDraftStatuses = new Set(["brouillon", "draft"]);
// Counters are written only by participateInGameTransaction (merchants
// cannot modify them), so a handful of test plays never reaches them.
const kMinLaunchUniquePlayers = 10;
const kMinLaunchParticipations = 20; // only when unique players are not tracked

function normalizedStatus(game) {
  return String((game && game.status) || "").trim().toLowerCase();
}

function hasLaunchEvidence(game) {
  const uniquePlayers = Number(game.unique_players_count);
  if (Number.isFinite(uniquePlayers) && game.unique_players_count != null) {
    return uniquePlayers >= kMinLaunchUniquePlayers;
  }
  return (Number(game.participations) || 0) >= kMinLaunchParticipations;
}

// Returns {state, playable}. States:
//  - disabled: explicitly cancelled/deactivated/deleted
//  - hidden: published by the server, then hidden again by an admin
//  - published: normally published (true or legacy missing visible_public)
//  - published_inconsistent: draft flags, but really launched
//  - draft: never published
function gamePublicationState(game) {
  const data = game || {};
  const status = normalizedStatus(data);
  if (data.deleted === true || kClosedStatuses.has(status)) {
    return {state: "disabled", playable: false};
  }
  if (data.visible_public === false && data.visible_public_auto_published === true) {
    return {state: "hidden", playable: false};
  }
  const draftFlagged = data.visible_public === false || kDraftStatuses.has(status);
  if (!draftFlagged) return {state: "published", playable: true};
  if (hasLaunchEvidence(data)) return {state: "published_inconsistent", playable: true};
  return {state: "draft", playable: false};
}

module.exports = {
  gamePublicationState,
  hasLaunchEvidence,
  kMinLaunchUniquePlayers,
  kMinLaunchParticipations,
};
