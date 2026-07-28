import 'package:flutter/foundation.dart';

import '/backend/backend.dart';

/// Fetches the winner's user document only if the game/prize data doesn't
/// already carry a denormalized first name (written by the Cloud Functions
/// that draw winners — see participate_in_game_transaction.js,
/// pickMainPrizeWinners, drawWinnerForAnimation). This avoids an
/// unconditional cross-user read of users/{winner_id}, which the Firestore
/// rules restrict to the user themselves or an admin. Any read failure
/// (permission-denied on old/un-backfilled data, network error, ...)
/// degrades to no user data rather than throwing, so the caller falls back
/// to whatever extractWinnerDisplayFromGameData can already show.
Future<UsersRecord?> fetchWinnerUserIfNeeded({
  required Map<String, dynamic> gameData,
  required DocumentReference? winnerRef,
}) async {
  final alreadyDenormalized =
      extractWinnerDisplayFromGameData(gameData)['firstName']
              ?.trim()
              .isNotEmpty ==
          true;
  if (alreadyDenormalized || winnerRef == null) {
    return null;
  }
  try {
    return await UsersRecord.getDocumentOnce(winnerRef);
  } catch (error) {
    debugPrint(
      '[winner_identity] fetchWinnerUserIfNeeded failed '
      'ref=${winnerRef.path} error=$error',
    );
    return null;
  }
}

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

String _capitalizeFirst(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
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
  final formattedFirstName = _capitalizeFirst(firstName);
  final formattedCity = _capitalizeFirst(city);

  if (formattedFirstName.isNotEmpty && formattedCity.isNotEmpty) {
    return 'Gagné par $formattedFirstName - $formattedCity';
  }

  if (formattedFirstName.isNotEmpty) {
    return 'Gagné par $formattedFirstName';
  }

  if (formattedCity.isNotEmpty) {
    return 'Gagné par un joueur de $formattedCity';
  }

  return fallback;
}

String buildWinnerCongratulationsFromSources({
  required Map<String, dynamic> gameData,
  UsersRecord? user,
  String fallback = 'Félicitations !',
}) {
  final gameDisplay = extractWinnerDisplayFromGameData(gameData);
  final firstName = gameDisplay['firstName']?.trim().isNotEmpty == true
      ? gameDisplay['firstName']!.trim()
      : extractWinnerFirstName(user);
  final city = gameDisplay['city']?.trim().isNotEmpty == true
      ? gameDisplay['city']!.trim()
      : (user?.city ?? '').trim();
  final formattedFirstName = _capitalizeFirst(firstName);
  final formattedCity = _capitalizeFirst(city);

  if (formattedFirstName.isEmpty) {
    return fallback;
  }

  return formattedCity.isNotEmpty
      ? 'Félicitations à $formattedFirstName de $formattedCity !'
      : 'Félicitations à $formattedFirstName !';
}
