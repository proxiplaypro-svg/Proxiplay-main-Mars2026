import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/components/merchant_prize_claim_success_dialog.dart';

void main() {
  testWidgets('shows a clear confirmation after a successful claim',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: MerchantPrizeClaimSuccessDialog()),
    ));

    expect(find.text('Lot validé ✓'), findsOneWidget);
    expect(find.text('Le lot a bien été marqué comme retiré.'), findsOneWidget);
    expect(find.text('Terminer'), findsOneWidget);
  });
}
