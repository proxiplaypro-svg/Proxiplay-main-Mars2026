/// Presentation data for a main prize in the player game-detail page.
///
/// The game's general `description` is deliberately not considered here: it
/// describes the game, not its prize. A prize is shown only when the game is
/// explicitly configured with a main prize and at least one dedicated prize
/// field is available.
class MainPrizePresentation {
  const MainPrizePresentation({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  bool get hasContent => title.isNotEmpty || description.isNotEmpty;

  /// Avoids displaying the same text twice when legacy data duplicated it.
  bool get hasDistinctDescription =>
      description.isNotEmpty && description != title;
}

MainPrizePresentation mainPrizePresentation({
  required bool hasMainPrize,
  String? title,
  String? description,
}) {
  if (!hasMainPrize) {
    return const MainPrizePresentation(title: '', description: '');
  }
  return MainPrizePresentation(
    title: title?.trim() ?? '',
    description: description?.trim() ?? '',
  );
}
