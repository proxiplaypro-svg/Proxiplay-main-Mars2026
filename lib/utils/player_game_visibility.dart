/// Publication rule for games, mirrored in firebase/functions/game_publication.js
/// and the Admin (lib/admin/gamePublication.ts). Keep the three in sync.
///
/// A missing visibility field belongs to a legacy public game. Draft flags
/// (`visible_public: false`, status `brouillon`) can be stale: a game proven
/// launched by the server-maintained player counters stays visible, while a
/// draft without that evidence, a cancelled game and a game hidden again by an
/// admin are hidden from player-facing lists.
enum GamePublicationState {
  disabled,
  hidden,
  published,
  publishedInconsistent,
  draft,
}

const _closedStatuses = {
  'cancelled',
  'canceled',
  'annule',
  'annulé',
  'disabled',
  'desactive',
  'désactivé',
  'deleted',
  'supprime',
  'supprimé',
};
const _draftStatuses = {'brouillon', 'draft'};
const minLaunchUniquePlayers = 10;
const minLaunchParticipations = 20;

bool _hasLaunchEvidence(Map<String, dynamic> data) {
  final uniquePlayers = data['unique_players_count'];
  if (uniquePlayers is num) return uniquePlayers >= minLaunchUniquePlayers;
  final participations = data['participations'];
  return participations is num && participations >= minLaunchParticipations;
}

GamePublicationState gamePublicationState(Map<String, dynamic> data) {
  final status = (data['status'] is String ? data['status'] as String : '')
      .trim()
      .toLowerCase();
  if (data['deleted'] == true || _closedStatuses.contains(status)) {
    return GamePublicationState.disabled;
  }
  final visiblePublic = data['visible_public'];
  if (visiblePublic == false && data['visible_public_auto_published'] == true) {
    return GamePublicationState.hidden;
  }
  final draftFlagged =
      visiblePublic == false || _draftStatuses.contains(status);
  if (!draftFlagged) return GamePublicationState.published;
  return _hasLaunchEvidence(data)
      ? GamePublicationState.publishedInconsistent
      : GamePublicationState.draft;
}

/// Whether a game must be kept out of player-facing lists.
bool isGameHiddenFromPlayer(Map<String, dynamic> data) {
  final state = gamePublicationState(data);
  return state != GamePublicationState.published &&
      state != GamePublicationState.publishedInconsistent;
}
