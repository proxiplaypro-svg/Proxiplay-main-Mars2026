import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

/// Where an exported CSV ended up after [saveGamePlayersCsv].
enum GamePlayersSaveDestination {
  /// Written directly to the device's public Downloads folder (Android).
  downloads,

  /// Handed to the OS share sheet for the user to pick a destination (iOS
  /// and any other non-Android platform).
  shared,
}

class GamePlayersSaveResult {
  const GamePlayersSaveResult(this.destination);
  final GamePlayersSaveDestination destination;
}

bool _mediaStoreInitialized = false;

/// Saves an already-exported CSV to disk.
///
/// On Android this writes straight to the public Downloads folder via
/// MediaStore (Scoped Storage, no storage permission needed on API 29+) and
/// never opens the share sheet. On every other platform (iOS in
/// particular, which has no equivalent app-writable public folder) the
/// existing share-sheet flow is preserved unchanged.
///
/// Throws [GamePlayersExportException] if the file could not be saved --
/// callers must not report success in that case.
Future<GamePlayersSaveResult> saveGamePlayersCsv(
  GamePlayersExportResult export, {
  required String shareSubject,
}) async {
  final tempDir = await getTemporaryDirectory();
  final tempFile = File('${tempDir.path}/${export.fileName}');
  await tempFile.writeAsBytes(export.bytes, flush: true);

  if (Platform.isAndroid) {
    try {
      if (!_mediaStoreInitialized) {
        await MediaStore.ensureInitialized();
        MediaStore.appFolder = 'Proxiplay';
        _mediaStoreInitialized = true;
      }
      final saveInfo = await MediaStore().saveFile(
        tempFilePath: tempFile.path,
        dirType: DirType.download,
        dirName: DirType.download.defaults,
        relativePath: FilePath.root,
      );
      if (saveInfo == null) {
        throw const GamePlayersExportException(
            "Impossible d'enregistrer le fichier.");
      }
    } on GamePlayersExportException {
      rethrow;
    } catch (error) {
      debugPrint('[GamePlayersExport] MediaStore save failed: $error');
      throw const GamePlayersExportException(
          "Impossible d'enregistrer le fichier.");
    }
    return const GamePlayersSaveResult(GamePlayersSaveDestination.downloads);
  }

  await Share.shareXFiles(
    [XFile(tempFile.path, mimeType: 'text/csv')],
    subject: shareSubject,
  );
  return const GamePlayersSaveResult(GamePlayersSaveDestination.shared);
}
