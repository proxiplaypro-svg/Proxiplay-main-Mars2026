import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/pages/joueur/parrainage_commercant_page/merchant_referral_conditions.dart';

void main() {
  testWidgets(
      'les conditions indiquent la récompense en bons cadeaux et les droits historiques',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MerchantReferralConditionsDialog())));
    expect(find.text('Conditions du programme'), findsOneWidget);
    expect(find.textContaining('50 € en bons cadeaux'), findsOneWidget);
    expect(find.textContaining('joueur ou un commerçant ProxiPlay'), findsOneWidget);
    expect(find.textContaining('premier abonnement'), findsOneWidget);
    expect(find.textContaining('parrainage est validé'), findsOneWidget);
    expect(find.textContaining('jamais en espèces'), findsOneWidget);
    expect(find.textContaining('en créant son compte ProxiPlay'), findsOneWidget);
    expect(
        find.textContaining(
            'modalités de remise des bons cadeaux restent à préciser'),
        findsOneWidget);
    expect(find.textContaining('conditions qui leur étaient applicables'),
        findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
