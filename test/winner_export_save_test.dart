import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/game_players_export.dart';

class _Picker extends FilePicker {
  String? result = '/document/test';
  Object? error;
  Uint8List? receivedBytes;
  String? receivedName;
  int calls = 0;
  @override
  Future<String?> saveFile(
      {String? dialogTitle,
      String? fileName,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Uint8List? bytes,
      bool lockParentWindow = false}) async {
    calls++;
    receivedBytes = bytes;
    receivedName = fileName;
    expect(type, FileType.custom);
    expect(allowedExtensions, ['csv']);
    expect(initialDirectory, isNull);
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Picker picker;
  final export = GamePlayersExportResult(
      fileName: 'winners.csv',
      bytes:
          Uint8List.fromList(utf8.encode('\uFEFFPrénom;Nom\r\nTEST;TEST\r\n')),
      rowCount: 1);
  setUp(() {
    picker = _Picker();
    FilePicker.platform = picker;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/device_info'),
            (_) async => {});
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
        '$platform forwards exact bytes, supports same name twice and cancellation',
        () async {
      debugDefaultTargetPlatformOverride = platform;
      for (var i = 0; i < 2; i++) {
        final result =
            await saveGamePlayersCsv(export, shareSubject: 'unused on mobile');
        expect(result.destination, GamePlayersSaveDestination.selectedLocation);
        expect(picker.receivedBytes, orderedEquals(export.bytes));
        expect(picker.receivedName, 'winners.csv');
      }
      picker.result = null;
      expect((await saveGamePlayersCsv(export, shareSubject: '')).destination,
          GamePlayersSaveDestination.cancelled);
      expect(picker.calls, 3);
    });

    test('$platform logs PlatformException details in debug only', () async {
      debugDefaultTargetPlatformOverride = platform;
      picker.error = PlatformException(
          code: 'Error while saving file',
          message: 'PRIVATE_NAME PRIVATE_EMAIL PRIVATE_CODE',
          details: 'PRIVATE_CSV');
      final messages = <String>[];
      final originalPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
      try {
        await expectLater(
            saveGamePlayersCsv(export, shareSubject: ''),
            throwsA(isA<GamePlayersExportException>().having((e) => e.message,
                'message', "Impossible d'enregistrer le fichier.")));
        expect(messages.join(), contains('kind=platform_exception'));
        expect(messages.join(), contains('code=Error while saving file'));
        expect(messages.join(),
            contains('PRIVATE_NAME PRIVATE_EMAIL PRIVATE_CODE'));
        expect(messages.join(), contains('PRIVATE_CSV'));
        expect(messages.join(), contains('stackTrace'));
      } finally {
        debugPrint = originalPrint;
      }
    });
  }
  test('empty bytes never open a save dialog', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await expectLater(
        saveGamePlayersCsv(
            GamePlayersExportResult(
                fileName: 'test.csv', bytes: Uint8List(0), rowCount: 0),
            shareSubject: ''),
        throwsA(isA<GamePlayersExportException>()));
    expect(picker.calls, 0);
  });

  test('zero winners is identifiable before opening the save dialog', () {
    final noWinnerExport = GamePlayersExportResult(
      fileName: 'winners.csv',
      bytes: Uint8List.fromList(utf8.encode('Prénom;Nom\r\n')),
      rowCount: 0,
    );

    expect(noWinnerExport.hasRows, isFalse);
    expect(export.hasRows, isTrue);
  });

  test('unexpected errors are classified separately from platform errors',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    picker.error = StateError('test write failure');
    final messages = <String>[];
    final originalPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
    try {
      await expectLater(
        saveGamePlayersCsv(export, shareSubject: ''),
        throwsA(isA<GamePlayersExportException>()),
      );
      expect(messages.join(), contains('kind=unexpected_error'));
      expect(messages.join(), contains('Bad state: test write failure'));
    } finally {
      debugPrint = originalPrint;
    }
  });

  test('write errors are classified separately from unexpected errors',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    picker.error = FileSystemException('disk unavailable');
    final messages = <String>[];
    final originalPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
    try {
      await expectLater(
        saveGamePlayersCsv(export, shareSubject: ''),
        throwsA(isA<GamePlayersExportException>()),
      );
      expect(messages.join(), contains('kind=write_error'));
      expect(messages.join(), contains('FileSystemException: disk unavailable'));
    } finally {
      debugPrint = originalPrint;
    }
  });
}
