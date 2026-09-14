import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// One exported file, decoded and ready to write to disk / share.
class GamePlayersExportResult {
  const GamePlayersExportResult({
    required this.fileName,
    required this.bytes,
    required this.rowCount,
  });
  final String fileName;
  final Uint8List bytes;
  final int rowCount;
}

/// User-facing message for a failed export -- callers should show
/// [message] directly rather than the raw exception.
class GamePlayersExportException implements Exception {
  const GamePlayersExportException(this.message);
  final String message;
  @override
  String toString() => message;
}

String _messageForCode(String? code) {
  switch (code) {
    case 'permission-denied':
      return "Vous n'êtes pas autorisé à exporter les joueurs de ce jeu.";
    case 'not-found':
      return 'Jeu introuvable.';
    case 'unimplemented':
      return "Ce format d'export n'est pas encore disponible.";
    case 'unauthenticated':
      return 'Reconnectez-vous pour exporter les joueurs.';
    default:
      return "Impossible d'exporter les joueurs. Réessayez.";
  }
}

/// Exports the players (participants) of one game as a CSV, through the
/// `exportGameParticipants` Cloud Function. That function verifies
/// server-side that the caller owns this game (or is admin) before joining
/// participant -> user documents, so this client never reads another
/// player's profile directly -- only the returned file bytes are handled
/// here. PDF is not implemented yet (throws with a clear message if ever
/// requested).
Future<GamePlayersExportResult> exportGamePlayersCsv(String gameId) async {
  try {
    final result = await FirebaseFunctions.instance
        .httpsCallable('exportGameParticipants')
        .call({'gameId': gameId, 'format': 'csv'});
    final data = result.data;
    if (data is! Map) {
      throw const GamePlayersExportException('Réponse invalide du serveur.');
    }
    final csvBase64 = (data['csvBase64'] ?? '').toString();
    final fileName = (data['fileName'] ?? 'proxiplay_joueurs.csv').toString();
    final rowCount = (data['rowCount'] as num?)?.toInt() ?? 0;
    if (csvBase64.isEmpty) {
      // A game with zero participants still returns a header-only CSV with
      // a non-empty csvBase64 -- an empty string here means the response
      // shape itself is unexpected, not "no players".
      throw const GamePlayersExportException('Fichier vide reçu du serveur.');
    }
    return GamePlayersExportResult(
      fileName: fileName,
      bytes: base64Decode(csvBase64),
      rowCount: rowCount,
    );
  } on FirebaseFunctionsException catch (error) {
    debugPrint(
      '[GamePlayersExport] failed gameId=$gameId '
      'code=${error.code} message=${error.message}',
    );
    throw GamePlayersExportException(_messageForCode(error.code));
  }
}
