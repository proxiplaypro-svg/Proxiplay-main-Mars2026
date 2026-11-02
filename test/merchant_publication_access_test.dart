import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/merchant_publication_access.dart';

void main() {
  test('le message attendu est affiché mot pour mot', () {
    expect(
      kSubscriptionRequiredMessage,
      'Un abonnement ProxiPlay actif est nécessaire pour publier un jeu. '
      'Rendez-vous sur www.proxiplay.fr/espace-commercant/ pour découvrir les offres.',
    );
  });

  test('refus uniquement si le contrôle est activé ET l’accès refusé', () {
    expect(isPublicationRefusedResponse({'enforced': true, 'allowed': false}), isTrue);
    expect(isPublicationRefusedResponse({'enforced': false, 'allowed': false}), isFalse);
    expect(isPublicationRefusedResponse({'enforced': true, 'allowed': true}), isFalse);
    expect(isPublicationRefusedResponse({'enforced': false, 'allowed': true, 'status': 'legacy'}), isFalse);
    expect(isPublicationRefusedResponse(null), isFalse);
    expect(isPublicationRefusedResponse('refused'), isFalse);
  });

  test('seul le refus serveur pour abonnement déclenche le message', () {
    FirebaseFunctionsException error(String code, Object? details) =>
        FirebaseFunctionsException(message: 'x', code: code, details: details);
    expect(isSubscriptionRequiredError(error('failed-precondition', {'reason': 'subscription_required'})), isTrue);
    expect(isSubscriptionRequiredError(error('failed-precondition', {'reason': 'game_ended'})), isFalse);
    expect(isSubscriptionRequiredError(error('failed-precondition', null)), isFalse);
    expect(isSubscriptionRequiredError(error('permission-denied', {'reason': 'subscription_required'})), isFalse);
    expect(isSubscriptionRequiredError(Exception('réseau')), isFalse);
  });

  testWidgets('la boîte de dialogue affiche le message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showSubscriptionRequiredDialog(context),
          child: const Text('ouvrir'),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('Abonnement requis'), findsOneWidget);
    expect(find.text(kSubscriptionRequiredMessage), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text(kSubscriptionRequiredMessage), findsNothing);
  });
}
