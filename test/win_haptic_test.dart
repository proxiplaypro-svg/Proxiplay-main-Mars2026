import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/haptics.dart';

// Win haptic (26/10/2026): two medium pulses 120 ms apart when a won instant
// prize is revealed; nothing on a loss, a replayed result or a rebuild.
void main() {
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') calls.add('${call.arguments}');
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  testWidgets('two medium pulses, 120 ms apart', (tester) async {
    expect(kWinHapticGap, const Duration(milliseconds: 120));
    final done = triggerWinHaptic();
    await tester.pump();
    expect(calls, ['HapticFeedbackType.mediumImpact']);
    await tester.pump(const Duration(milliseconds: 119));
    expect(calls, hasLength(1), reason: 'the second pulse waits the gap');
    await tester.pump(const Duration(milliseconds: 1));
    await done;
    expect(calls, ['HapticFeedbackType.mediumImpact', 'HapticFeedbackType.mediumImpact']);
  });

  testWidgets('a device without haptics or a failing channel is ignored', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      throw PlatformException(code: 'unavailable');
    });
    final done = triggerWinHaptic();
    await tester.pump(const Duration(milliseconds: 200));
    await done; // completes without throwing
  });

  testWidgets('leaving the screen during the pulses is harmless', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('jeu')));
    final done = triggerWinHaptic();
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Text('accueil'))); // screen left
    await tester.pump(const Duration(milliseconds: 150));
    await done;
    expect(calls, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  group('wiring (source checks)', () {
    String compact(String path) => File(path).readAsStringSync().replaceAll(RegExp(r'\s+'), '');
    final page = compact('lib/pages/joueur/play_joueur_page/play_joueur_page_widget.dart');

    test('played only in the won branch of the reveal, once, without delaying it', () {
      expect('triggerWinHaptic('.allMatches(page).length, 1);
      final win = page.indexOf('?.isWin==true){_model.isWin=true;safeSetState((){});');
      final haptic = page.indexOf('if(!_winHapticPlayed){_winHapticPlayed=true;unawaited(triggerWinHaptic());}');
      final sound = page.indexOf('await_stopScratchSound();', haptic);
      final loss = page.indexOf('_model.isWin=false;');
      expect(win, isNot(-1));
      expect(haptic, greaterThan(win));
      expect(sound, greaterThan(haptic), reason: 'not awaited, before the win sound');
      expect(loss, greaterThan(haptic), reason: 'never in the losing branch');
      expect(page, contains('bool_winHapticPlayed=false;'));
    });

    test('a replayed result has no scratch reveal, the reveal itself happens once', () {
      // The replay block (already played) is shown without the scratch card.
      final replay = page.indexOf('elseif(isAlreadyPlayedStatus)');
      final scratch = page.indexOf('.ScratchCardWidget(');
      expect(replay, isNot(-1));
      expect(scratch, greaterThan(replay));
      final card = compact('lib/custom_code/widgets/scratch_card_widget.dart');
      expect(card, contains('if(!_hasScratchStarted||!_hasReachedThreshold||_isRevealed){'));
      expect(card.indexOf('_isRevealed=true;'), lessThan(card.indexOf('widget.setCardRevealed();')));
    });
  });
}
