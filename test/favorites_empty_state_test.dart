import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/components/favorites_empty_state.dart';

void main() {
  Future<void> pumpEmptyState(
    WidgetTester tester, {
    required String title,
    required String description,
    VoidCallback? onDiscoverMerchants,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FavoritesEmptyState(
            title: title,
            description: description,
            onDiscoverMerchants: onDiscoverMerchants,
          ),
        ),
      ));

  testWidgets('favorites empty state is compact and opens the directory action',
      (tester) async {
    var discoverCalls = 0;
    await pumpEmptyState(
      tester,
      title: 'Aucun favori pour le moment',
      description: 'Retrouvez ici les commerçants que vous aimez.',
      onDiscoverMerchants: () => discoverCalls++,
    );

    final card = find.byKey(const ValueKey('favorites-empty-card'));
    expect(card, findsOneWidget);
    expect(tester.getSize(card).height, lessThan(230.0));
    expect(find.text('Aucun favori pour le moment'), findsOneWidget);
    expect(find.text('Retrouvez ici les commerçants que vous aimez.'),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('favorites-discover-merchants')));
    expect(discoverCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'favorite games empty state stays compact without a directory action',
      (tester) async {
    await pumpEmptyState(
      tester,
      title: 'Aucun jeu favori pour le moment',
      description: 'Vos jeux favoris apparaîtront ici.',
    );

    expect(
        tester
            .getSize(find.byKey(const ValueKey('favorites-empty-card')))
            .height,
        lessThan(170.0));
    expect(find.byKey(const ValueKey('favorites-discover-merchants')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
