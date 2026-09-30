import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:proxi_play/components/winner_contact_information_card.dart';
import 'package:proxi_play/utils/prize_winner_contact.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget host(Future<PrizeWinnerContact?> future, VoidCallback onRetry) =>
      MaterialApp(
        home: Scaffold(
          body: WinnerContactInformationCard(
            contactFuture: future,
            onRetry: onRetry,
          ),
        ),
      );

  const contact = PrizeWinnerContact(
    firstName: 'Alice',
    lastName: 'Dupont',
    city: 'Paris',
    email: 'alice@example.com',
    phoneNumber: '0600000000',
  );

  testWidgets('shows an explicit loading state instead of empty fields',
      (tester) async {
    final completer = Completer<PrizeWinnerContact?>();
    await tester.pumpWidget(host(completer.future, () {}));

    expect(find.text('Chargement des informations…'), findsOneWidget);
    expect(find.text('NOM :'), findsNothing);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('shows resolved winner fields', (tester) async {
    await tester.pumpWidget(host(Future.value(contact), () {}));
    await tester.pump();

    expect(find.text('Dupont'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Paris'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('0600000000'), findsOneWidget);
  });

  testWidgets('uses a dash only for a field absent in a resolved response',
      (tester) async {
    await tester.pumpWidget(host(
      Future.value(const PrizeWinnerContact(
        firstName: '',
        lastName: 'Dupont',
        city: '',
        email: '',
        phoneNumber: '',
      )),
      () {},
    ));
    await tester.pump();

    expect(find.text('Dupont'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(4));
  });

  testWidgets('shows an unavailable state and allows a retry', (tester) async {
    var retries = 0;
    await tester.pumpWidget(host(
      Future<PrizeWinnerContact?>.value(),
      () => retries++,
    ));
    await tester.pump();

    expect(find.text('Informations du gagnant indisponibles'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    expect(retries, 1);
  });

  test('classifies a completed callable error as unavailable', () {
    expect(
      winnerContactLoadState(
        connectionState: ConnectionState.done,
        hasError: true,
        contact: contact,
      ),
      WinnerContactLoadState.unavailable,
    );
  });

  test('caches one winner-contact request per prize until retry', () async {
    var calls = 0;
    final cache = PrizeWinnerContactFutureCache(
      fetch: (_) async {
        calls++;
        return contact;
      },
    );

    final first = cache.get('prize-1');
    final second = cache.get('prize-1');
    expect(identical(first, second), isTrue);
    await first;
    expect(calls, 1);

    cache.retry('prize-1');
    await cache.get('prize-1');
    expect(calls, 2);
  });
}
