import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/components/merchant_home_viewport.dart';

void main() {
  for (final height in [180.0, 320.0, 700.0]) {
    testWidgets('code and verify button are reachable at height $height', (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: height,
              child: MerchantHomeViewport(builder: (context, availableHeight) => Column(
                children: [
                  const Text('Vérifier le code gagnant'),
                  const TextField(key: Key('winning-code')),
                  const SizedBox(height: 180),
                  ElevatedButton(key: const Key('verify'), onPressed: () {}, child: const Text('Vérifier')),
                  SizedBox(height: availableHeight > 500 ? availableHeight - 320 : 180),
                ],
              )),
            ),
          ),
        ),
      ));
      await tester.enterText(find.byKey(const Key('winning-code')), 'ABC123');
      await tester.ensureVisible(find.byKey(const Key('verify')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('ABC123'), findsOneWidget);
      expect(find.byKey(const Key('verify')), findsOneWidget);
    });
  }
}
