/// A missing visibility field belongs to a legacy public game. Only an
/// explicit `visible_public: false` is a draft marker and must hide a game
/// from player-facing lists.
bool isGameDraftHiddenFromPlayer({
  required bool hasVisiblePublicField,
  required bool visiblePublic,
}) =>
    hasVisiblePublicField && !visiblePublic;
