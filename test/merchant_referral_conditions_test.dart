import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/pages/joueur/parrainage_commercant_page/merchant_referral_conditions.dart';

void main() {
  testWidgets(
      'les conditions indiquent la prime actuelle et les droits historiques',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MerchantReferralConditionsDialog())));
    expect(find.text('Conditions du programme'), findsOneWidget);
    expect(find.textContaining('bon cadeau de 50 €'), findsOneWidget);
    expect(find.textContaining('joueur ProxiPlay'), findsOneWidget);
    expect(find.textContaining('abonnement éligible'), findsOneWidget);
    expect(find.textContaining('parrainage est validé'), findsOneWidget);
    expect(
        find.textContaining(
            'modalités de remise du bon cadeau restent à préciser'),
        findsOneWidget);
    expect(find.textContaining('conditions qui leur étaient applicables'),
        findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
