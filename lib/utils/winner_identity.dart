import '/backend/backend.dart';

String _firstNonEmptyString(
  Map<String, dynamic> data,
  List<String> keys,
) {
  for (final key in keys) {
    final raw = data[key];
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
  }
  return '';
}

String extractWinnerFirstName(UsersRecord? user) {
  final candidates = <String>[
    user?.firstName ?? '',
    user?.displayName ?? '',
    user?.pseudo ?? '',
  ];
  for (final candidate in candidates) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    return trimmed.split(RegExp(r'\s+')).first;
  }
  return '';
}

String extractWinnerFirstNameFromValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return trimmed.split(RegExp(r'\s+')).first;
}

Map<String, String> extractWinnerDisplayFromGameData(
  Map<String, dynamic> gameData,
) {
  final firstName = extractWinnerFirstNameFromValue(
    _firstNonEmptyString(gameData, [
      'winnerFirstName',
      'winner_first_name',
      'winnerName',
      'winner_name',
      'winner_name_first',
    ]),
  );
  final city = _firstNonEmptyString(gameData, [
    'winnerCity',
    'winner_city',
    'winnerVille',
    'winner_ville',
    'winnerTown',
    'winner_town',
  ]);

  return {
    'firstName': firstName,
    'city': city,
  };
}

String buildWinnerLabelFromSources({
  required Map<String, dynamic> gameData,
  UsersRecord? user,
  String fallback = 'Gagnant annonce',
}) {
  final gameDisplay = extractWinnerDisplayFromGameData(gameData);
  final firstName = gameDisplay['firstName']?.trim().isNotEmpty == true
      ? gameDisplay['firstName']!.trim()
      : extractWinnerFirstName(user);
  final city = gameDisplay['city']?.trim().isNotEmpty == true
      ? gameDisplay['city']!.trim()
      : (user?.city ?? '').trim();

  if (firstName.isNotEmpty && city.isNotEmpty) {
    return 'Gagne par $firstName - $city';
  }

  if (firstName.isNotEmpty) {
    return 'Gagne par $firstName';
  }

  if (city.isNotEmpty) {
    return 'Gagne par un joueur de $city';
  }

  return fallback;
}

String buildWinnerCongratulationsFromSources({
  required Map<String, dynamic> gameData,
  UsersRecord? user,
  String fallback = 'Felicitations !',
}) {
  final gameDisplay = extractWinnerDisplayFromGameData(gameData);
  final firstName = gameDisplay['firstName']?.trim().isNotEmpty == true
      ? gameDisplay['firstName']!.trim()
      : extractWinnerFirstName(user);
  final city = gameDisplay['city']?.trim().isNotEmpty == true
      ? gameDisplay['city']!.trim()
      : (user?.city ?? '').trim();

  if (firstName.isEmpty) {
    return fallback;
  }

  return city.isNotEmpty
      ? 'Felicitations a $firstName de $city !'
      : 'Felicitations a $firstName !';
}
