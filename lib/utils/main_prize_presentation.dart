/// Presentation data for a main prize in the player game-detail page.
///
/// Dedicated fields take precedence. Documents using the historical schema
/// can retain the 1.1.1 presentation through [mainPrizeFromGameData].
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

/// Restores the 1.1.1 display for documents without either dedicated field.
/// Key presence matters: null and empty values are explicit modern values.
MainPrizePresentation mainPrizeFromGameData({
  required Map<String, dynamic> data,
  required bool hasMainPrize,
  required num prizeValue,
}) {
  String? text(Object? value) => value is String ? value : null;
  final hasDedicatedFields = data.containsKey('main_prize_title') ||
      data.containsKey('main_prize_description');
  return mainPrizePresentation(
    hasMainPrize: hasMainPrize,
    title: text(data['main_prize_title']),
    description: hasDedicatedFields
        ? text(data['main_prize_description'])
        : prizeValue > 0
            ? text(data['description'])
            : null,
  );
}
