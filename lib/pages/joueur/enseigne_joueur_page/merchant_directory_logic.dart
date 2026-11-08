import '/utils/player_game_visibility.dart';

/// Display data of one merchant in the player directory. [record] keeps the
/// original Firestore record for navigation; the directory never reads it.
class DirectoryMerchant {
  const DirectoryMerchant({
    required this.id,
    this.name = '',
    this.description = '',
    this.city = '',
    this.categories = const [],
    this.googleRating,
    this.googleReviewsCount,
    this.record,
  });

  final String id;
  final String name;
  final String description;
  final String city;
  final List<String> categories;
  final double? googleRating;
  final int? googleReviewsCount;
  final Object? record;

  String get displayName => name.trim().isEmpty ? 'Commerçant' : name.trim();

  /// Same bounds as MerchantRating: an invalid stored value is not shown.
  String? get ratingLabel {
    final rating = googleRating;
    if (rating == null || !rating.isFinite || rating < 0 || rating > 5) {
      return null;
    }
    return rating.toStringAsFixed(1).replaceAll('.', ',');
  }
}

const _accents = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'œ': 'oe',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  '’': "'",
};

/// Lower case, without accents, with collapsed spaces.
String normalizeDirectoryText(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Every word of the query must appear in the name, a category or the city.
bool merchantMatchesQuery(DirectoryMerchant merchant, String query) {
  final words = normalizeDirectoryText(query)
      .split(' ')
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return true;
  final haystack = normalizeDirectoryText(
      [merchant.name, merchant.city, ...merchant.categories].join(' '));
  return words.every(haystack.contains);
}

/// Known categories first in their usual order, then any other category that
/// is actually present, alphabetically. Only categories with a merchant.
List<String> availableDirectoryCategories(
  Iterable<DirectoryMerchant> merchants,
  List<String> knownCategories,
) {
  final present = <String>{
    for (final merchant in merchants)
      ...merchant.categories.map((c) => c.trim()).where((c) => c.isNotEmpty),
  };
  final known = knownCategories.where(present.contains).toList();
  final others = present.difference(knownCategories.toSet()).toList()
    ..sort((a, b) =>
        normalizeDirectoryText(a).compareTo(normalizeDirectoryText(b)));
  return [...known, ...others];
}

/// One game as needed by [activeMerchantIdsFromGames].
typedef DirectoryGame = ({
  String? merchantPath,
  Map<String, dynamic> data,
  DateTime? startDate,
  DateTime? endDate,
});

/// Exactly the rule of the merchant page ("jeux en cours"): published for
/// players (player_game_visibility.dart), started and not ended.
bool isDirectoryGameOngoing(DirectoryGame game, DateTime now) {
  if (isGameHiddenFromPlayer(game.data)) return false;
  final end = game.endDate;
  if (end == null || !end.isAfter(now)) return false;
  final start = game.startDate;
  return start == null || !now.isBefore(start);
}

/// Merchant ids (enseignes/{id}) with at least one ongoing game.
Set<String> activeMerchantIdsFromGames(
    Iterable<DirectoryGame> games, DateTime now) {
  final ids = <String>{};
  for (final game in games) {
    final match = RegExp(r'^enseignes/([^/]+)$')
        .firstMatch((game.merchantPath ?? '').replaceFirst(RegExp(r'^/'), ''));
    if (match != null && isDirectoryGameOngoing(game, now)) {
      ids.add(match.group(1)!);
    }
  }
  return ids;
}

/// Result of the single page-level query on ongoing games. When [complete] is
/// false the query hit its limit: a listed id is still a confirmed game, but
/// absence proves nothing, so the directory must not rank by it.
class ActiveGamesResult {
  const ActiveGamesResult({required this.merchantIds, required this.complete});
  static const unavailable =
      ActiveGamesResult(merchantIds: {}, complete: false);
  final Set<String> merchantIds;
  final bool complete;
}
