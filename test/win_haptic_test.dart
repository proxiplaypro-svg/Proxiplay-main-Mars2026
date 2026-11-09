import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/haptics.dart';

// Positive-result haptic: one native success notification when a won instant
// prize or a server-confirmed bonus is revealed; never on an ordinary loss,
// replay or rebuild.
void main() {
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add('${call.arguments}');
      }
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  testWidgets('one short native success notification', (tester) async {
    final done = triggerWinHaptic();
    await tester.pump();
    expect(calls, ['HapticFeedbackType.successNotification']);
    await tester.pump(const Duration(milliseconds: 300));
    await done;
    expect(calls, hasLength(1), reason: 'no repeated positive vibration');
  });

  testWidgets('a device without haptics or a failing channel is ignored',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      throw PlatformException(code: 'unavailable');
    });
    final done = triggerWinHaptic();
    await tester.pump(const Duration(milliseconds: 200));
    await done; // completes without throwing
  });

  test('debug traces keep the native success request observable', () {
    final source = File('lib/utils/haptics.dart').readAsStringSync();
    expect(source, contains('HapticFeedback.successNotification()'));
    expect(source, contains('event=success_notification_requested'));
    expect(source, contains('event=success_notification_completed'));
    expect(source, contains('event=pulse_failed'));
  });

  testWidgets('leaving the screen during the pulses is harmless',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('jeu')));
    final done = triggerWinHaptic();
    await tester.pump();
    await tester
        .pumpWidget(const MaterialApp(home: Text('accueil'))); // screen left
    await tester.pump(const Duration(milliseconds: 150));
    await done;
    expect(calls, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  group('wiring (source checks)', () {
    String compact(String path) =>
        File(path).readAsStringSync().replaceAll(RegExp(r'\s+'), '');
    final page = compact(
        'lib/pages/joueur/play_joueur_page/play_joueur_page_widget.dart');

    test(
        'played once for a prize win or positive bonus, without changing win UI',
        () {
      expect('triggerWinHaptic('.allMatches(page).length, 1);
      final bonus = page
          .indexOf('finalhasPositiveBonus=rewardTextBonus.trim().isNotEmpty;');
      final win =
          page.indexOf('?.isWin==true){_model.isWin=true;safeSetState((){});');
      final haptic = page.indexOf(
          'if((widget.resultParticipation?.isWin==true||hasPositiveBonus)&&!_winHapticPlayed){');
      final hapticRequest =
          page.indexOf('unawaited(triggerWinHaptic());', haptic);
      final sound = page.indexOf('await_stopScratchSound();', haptic);
      final loss = page.indexOf('_model.isWin=false;');
      expect(bonus, isNot(-1));
      expect(win, isNot(-1));
      expect(haptic, greaterThan(bonus));
      expect(hapticRequest, greaterThan(haptic));
      expect(win, greaterThan(haptic));
      expect(sound, greaterThan(haptic),
          reason: 'not awaited, before the win sound');
      expect(loss, greaterThan(haptic),
          reason: 'ordinary losses have no bonus');
      expect(page, contains('bool_winHapticPlayed=false;'));
    });

    test(
        'a replayed result has no scratch reveal, the reveal itself happens once',
        () {
      // The replay block (already played) is shown without the scratch card.
      final replay = page.indexOf('elseif(isAlreadyPlayedStatus)');
      final scratch = page.indexOf('.ScratchCardWidget(');
      expect(replay, isNot(-1));
      expect(scratch, greaterThan(replay));
      final card = compact('lib/custom_code/widgets/scratch_card_widget.dart');
      expect(
          card,
          contains(
              'if(!_hasScratchStarted||!_hasReachedThreshold||_isRevealed){'));
      expect(card.indexOf('_isRevealed=true;'),
          lessThan(card.indexOf('widget.setCardRevealed();')));
    });
  });
}
