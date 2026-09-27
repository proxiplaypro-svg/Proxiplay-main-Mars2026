import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
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

  bool get hasRows => rowCount > 0;
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
      return "Vous n'êtes pas autorisé à exporter les gagnants de ce jeu.";
    case 'not-found':
      return 'Jeu introuvable.';
    case 'unimplemented':
      return "Ce format d'export n'est pas encore disponible.";
    case 'unauthenticated':
      return 'Reconnectez-vous pour exporter les gagnants.';
    default:
      return "Impossible d'exporter les gagnants. Réessayez.";
  }
}

/// Exports one row per awarded prize through the existing
/// `exportGameParticipants` callable (its historical name is preserved).
/// Ownership and winner contact authorization are enforced by the backend.
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
    final fileName = (data['fileName'] ?? 'proxiplay_gagnants.csv').toString();
    final rowCount = (data['rowCount'] as num?)?.toInt() ?? 0;
    if (csvBase64.isEmpty) {
      // A game with zero winners still returns a header-only CSV with
      // a non-empty csvBase64 -- an empty string here means the response
      // shape itself is unexpected, not "no winners".
      throw const GamePlayersExportException('Fichier vide reçu du serveur.');
    }
    return GamePlayersExportResult(
      fileName: fileName,
      bytes: base64Decode(csvBase64),
      rowCount: rowCount,
    );
  } on FirebaseFunctionsException catch (error) {
    if (kDebugMode) {
      debugPrint('[WinnerExport] callable failed code=${error.code}');
    }
    throw GamePlayersExportException(_messageForCode(error.code));
  }
}

/// Cancellation is a normal outcome, never a failed save.
enum GamePlayersSaveDestination { selectedLocation, cancelled, shared }

class GamePlayersSaveResult {
  const GamePlayersSaveResult(this.destination);
  final GamePlayersSaveDestination destination;
}

/// Native save diagnostics are intentionally verbose in debug builds only.
/// They are never shown to the merchant and are omitted from release builds.
Future<void> _logSaveFailure(Object error, StackTrace stackTrace) async {
  if (!kDebugMode) return;
  var androidVersion = 'not_android';
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      final info = await DeviceInfoPlugin()
          .androidInfo
          .timeout(const Duration(seconds: 2));
      androidVersion = '${info.version.release}/sdk${info.version.sdkInt}';
    } catch (_) {
      androidVersion = 'unavailable';
    }
  }
  final kind = error is PlatformException
      ? 'platform_exception'
      : error is FileSystemException
          ? 'write_error'
          : 'unexpected_error';
  debugPrint('[WinnerExportSave] kind=$kind runtimeType=${error.runtimeType} '
      'platform=${defaultTargetPlatform.name} android=$androidVersion '
      'method=FilePicker.saveFile destination=system_selected_document');
  if (error is PlatformException) {
    debugPrint('[WinnerExportSave] code=${error.code} '
        'message=${error.message} details=${error.details}');
  } else {
    debugPrint('[WinnerExportSave] error=$error');
  }
  debugPrintStack(
      label: '[WinnerExportSave] stackTrace', stackTrace: stackTrace);
}

/// Mobile: the system document picker saves the supplied bytes itself.
/// Android uses ACTION_CREATE_DOCUMENT; iOS uses UIDocumentPicker export.
/// Never treat the Android returned document identifier as a filesystem path.
Future<GamePlayersSaveResult> saveGamePlayersCsv(
  GamePlayersExportResult export, {
  required String shareSubject,
}) async {
  try {
    if (export.bytes.isEmpty) throw StateError('Empty export bytes');
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      // Keep only a basename even if a malformed backend response contains a path.
      final fileName = export.fileName.replaceAll('\\', '/').split('/').last;
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer les gagnants',
        fileName: fileName.isEmpty ? 'proxiplay_gagnants.csv' : fileName,
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: export.bytes,
      );
      return GamePlayersSaveResult(destination == null
          ? GamePlayersSaveDestination.cancelled
          : GamePlayersSaveDestination.selectedLocation);
    }

    // Preserve the existing fallback for non-mobile platforms only.
    final tempDir = await getTemporaryDirectory();
    final name = export.fileName.replaceAll('\\', '/').split('/').last;
    final tempFile = File(
        '${tempDir.path}/${name.isEmpty ? 'proxiplay_gagnants.csv' : name}');
    await tempFile.writeAsBytes(export.bytes, flush: true);
    await Share.shareXFiles([XFile(tempFile.path, mimeType: 'text/csv')],
        subject: shareSubject);
    return const GamePlayersSaveResult(GamePlayersSaveDestination.shared);
  } catch (error, stackTrace) {
    await _logSaveFailure(error, stackTrace);
    throw const GamePlayersExportException(
        "Impossible d'enregistrer le fichier.");
  }
}
