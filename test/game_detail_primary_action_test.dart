import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/flutter_flow/flutter_flow_theme.dart';
import 'package:proxi_play/flutter_flow/flutter_flow_widgets.dart';
import 'package:proxi_play/utils/main_prize_ticket_presentation.dart';

void main() {
  FFButtonWidget buildPrimaryAction({
    required bool hasPlayedToday,
    required VoidCallback onLaunch,
  }) {
    return FFButtonWidget(
      text: hasPlayedToday ? 'Vous avez déjà joué aujourd\'hui' : 'Jouer',
      onPressed: isGameDetailPrimaryActionEnabled(
        gameEnded: false,
        noRemainingParts: false,
        hasPlayedToday: hasPlayedToday,
        isLaunchingGame: false,
      )
          ? onLaunch
          : null,
      showLoadingIndicator: false,
      options: FFButtonOptions(
        width: 240,
        height: 56,
        color: Colors.blue,
        textStyle: const TextStyle(color: Colors.white),
      ),
    );
  }

  Widget host(Widget child) => MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('a playable game keeps its existing launch action',
      (tester) async {
    var launches = 0;
    await tester.pumpWidget(host(buildPrimaryAction(
      hasPlayedToday: false,
      onLaunch: () => launches++,
    )));

    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull);
    await tester.tap(find.text('Jouer'));
    expect(launches, 1);
  });

  testWidgets('an already-played status cannot launch or react to a tap',
      (tester) async {
    var launches = 0;
    await tester.pumpWidget(host(buildPrimaryAction(
      hasPlayedToday: true,
      onLaunch: () => launches++,
    )));

    expect(find.text('Vous avez déjà joué aujourd\'hui'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);
    await tester.tap(find.text('Vous avez déjà joué aujourd\'hui'));
    expect(launches, 0);
  });

  test('a main-prize game presents validated tickets', () {
    expect(shouldShowMainPrizeTicket(hasMainPrize: true), isTrue);
    expect(mainPrizeTicketLabel(1), startsWith('🎫 1 ticket'));
    expect(mainPrizeTicketLabel(2), startsWith('🎫 2 tickets'));
  });

  test('a game without a main prize hides validated tickets', () {
    expect(shouldShowMainPrizeTicket(hasMainPrize: false), isFalse);
    expect(shouldShowMainPrizeTicket(hasMainPrize: null), isFalse);
  });
}
