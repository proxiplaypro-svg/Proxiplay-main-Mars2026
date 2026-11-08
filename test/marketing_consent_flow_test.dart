import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/marketing_consent_state.dart';

void main() {
  final now = DateTime(2026, 11, 8);
  final adult = DateTime(1990, 5, 1);
  final under15 = DateTime(2013, 1, 1);
  const granted = {'enabled': true, 'text_version': 'marketing-player-v1'};
  const withdrawn = {'enabled': false, 'text_version': 'marketing-player-v1'};

  group('inscription : case marketing', () {
    bool offer({bool merchant = false, DateTime? birthday, Map<String, dynamic>? stored}) =>
        shouldOfferSignupMarketingConsent(
            isMerchant: merchant, birthday: birthday, storedConsent: stored, now: now);

    test('proposée à un joueur sans préférence (date pas encore saisie ou ≥ 15 ans)', () {
      expect(offer(), isTrue);
      expect(offer(birthday: adult), isTrue);
      expect(offer(stored: const {}), isTrue, reason: 'champ illisible = sans réponse');
    });

    test('jamais pour un commerçant ni un joueur de moins de 15 ans', () {
      expect(offer(merchant: true, birthday: adult), isFalse);
      expect(offer(birthday: under15), isFalse);
    });

    test('compte existant : une préférence enregistrée n’est jamais redemandée', () {
      expect(offer(birthday: adult, stored: granted), isFalse);
      expect(offer(birthday: adult, stored: withdrawn), isFalse);
    });
  });

  group('inscription : appel serveur', () {
    bool send({bool checked = true, DateTime? birthday, Map<String, dynamic>? stored, bool merchant = false}) =>
        shouldSendSignupMarketingConsent(
            isMerchant: merchant,
            checked: checked,
            birthday: birthday,
            storedConsent: stored,
            now: now);

    test('sans consentement (case décochée) : aucun appel, pas de refus enregistré', () {
      expect(send(checked: false, birthday: adult), isFalse);
    });

    test('avec consentement : un seul accord, pour un joueur éligible', () {
      expect(send(birthday: adult), isTrue);
    });

    test('aucun appel sans date de naissance, sous 15 ans, ou pour un commerçant', () {
      expect(send(birthday: null), isFalse);
      expect(send(birthday: under15), isFalse);
      expect(send(birthday: adult, merchant: true), isFalse);
    });

    test('compte existant déjà inscrit : pas de second accord', () {
      expect(send(birthday: adult, stored: granted), isFalse);
      expect(send(birthday: adult, stored: withdrawn), isFalse,
          reason: 'un retrait se change depuis le profil, pas à l’inscription');
    });
  });

  group('profil : contrôle avant activation', () {
    test('date absente et âge insuffisant sont distingués', () {
      expect(marketingConsentAgreementPrecheck(null, now: now),
          contains('date de naissance n’est pas renseignée'));
      expect(marketingConsentAgreementPrecheck(under15, now: now),
          marketingConsentErrorMessage('failed-precondition'));
      expect(marketingConsentAgreementPrecheck(adult, now: now), isNull);
    });

    test('Callable absente : not-found donne le message « pas encore disponible »', () {
      expect(marketingConsentErrorMessage('not-found'),
          'Ce réglage n’est pas encore disponible. Réessayez plus tard.');
      expect(marketingConsentErrorMessage('unavailable'), contains('réseau'));
    });
  });

  test('les écrans utilisent ces règles et le profil ne contrôle pas le retrait', () {
    final signup = File(
            'lib/pages/auth/inscription_informations_page/inscription_informations_page_widget.dart')
        .readAsStringSync();
    final profile =
        File('lib/pages/joueur/profil_joueur_page/profil_joueur_page_widget.dart')
            .readAsStringSync();
    expect(signup.contains('shouldOfferSignupMarketingConsent('), isTrue);
    expect(signup.contains('shouldSendSignupMarketingConsent('), isTrue);
    expect(signup.contains("'enabled': false"), isFalse,
        reason: 'l’inscription n’envoie jamais de refus');
    expect(
        profile.contains('final precheck = value\n') ||
            profile.contains('final precheck = value\r\n'),
        isTrue,
        reason: 'contrôle uniquement pour un accord');
    expect(profile.contains("marketing_consent'"), isFalse,
        reason: 'aucune écriture directe du champ protégé');
  });
}
