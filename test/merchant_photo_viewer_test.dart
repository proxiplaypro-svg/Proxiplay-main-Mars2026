import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/pages/joueur/enseigne_detail_joueur_page/enseigne_detail_joueur_page_widget.dart';

void main() {
  const photoUrls = [
    'https://example.com/merchant-1.jpg',
    'https://example.com/merchant-2.jpg',
    'https://example.com/merchant-3.jpg',
  ];

  Future<void> showViewer(WidgetTester tester, {int initialIndex = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('open-merchant-photo-viewer'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MerchantPhotoViewer(
                    photoUrls: photoUrls,
                    initialIndex: initialIndex,
                  ),
                ),
              ),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-merchant-photo-viewer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('opens on the selected photo with a black full-screen viewer',
      (tester) async {
    await showViewer(tester);

    expect(find.text('2 / 3'), findsOneWidget);
    expect(
        find.byKey(const Key('merchant-photo-viewer-pages')), findsOneWidget);
    expect(
        find.byKey(const Key('merchant-photo-viewer-close')), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
      Colors.black,
    );
  });

  testWidgets('moves between photos horizontally and closes with the button',
      (tester) async {
    await showViewer(tester, initialIndex: 0);

    await tester.drag(
      find.byKey(const Key('merchant-photo-viewer-pages')),
      const Offset(-400, 0),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('merchant-photo-viewer-close')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('open-merchant-photo-viewer')), findsOneWidget);
  });

  testWidgets('closes with Android back navigation', (tester) async {
    await showViewer(tester);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('open-merchant-photo-viewer')), findsOneWidget);
  });

  testWidgets('keeps the close control accessible on a small screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await showViewer(tester);

    expect(
        find.byKey(const Key('merchant-photo-viewer-close')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
