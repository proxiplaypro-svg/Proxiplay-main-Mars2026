import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/merchant_referral_utils.dart';

void main() {
  group('buildMerchantReferralLink', () {
    test('1. ajoute le code en parametre ref sur la page de compte commercant', () {
      final link = buildMerchantReferralLink('AB3DE7G2');
      expect(link, 'https://www.proxiplay.fr/commercant/compte/?ref=AB3DE7G2');
    });

    test('2. code vide -> lien nu, sans parametre', () {
      expect(buildMerchantReferralLink(''), merchantReferralSignupUrl);
    });

    test('3. espaces autour du code retires', () {
      final link = buildMerchantReferralLink('  AB3DE7G2  ');
      expect(link, 'https://www.proxiplay.fr/commercant/compte/?ref=AB3DE7G2');
    });
  });

  group('buildMerchantReferralShareText', () {
    test('4. contient le code et le lien exact, jamais une promesse de gain garanti', () {
      final text = buildMerchantReferralShareText('AB3DE7G2');
      expect(text, contains('AB3DE7G2'));
      expect(text, contains('https://www.proxiplay.fr/commercant/compte/?ref=AB3DE7G2'));
      expect(text.toLowerCase(), isNot(contains('garanti')));
      expect(text.toLowerCase(), isNot(contains('automatiquement')));
    });
  });

  group('merchantReferralStatusLabel (jamais de nom technique affiché)', () {
    test('5. linked -> En attente', () {
      expect(merchantReferralStatusLabel('linked'), 'En attente');
    });
    test('6. eligible -> À valider', () {
      expect(merchantReferralStatusLabel('eligible'), 'À valider');
    });
    test('7. approved -> Validé', () {
      expect(merchantReferralStatusLabel('approved'), 'Validé');
    });
    test('8. paid -> Payé', () {
      expect(merchantReferralStatusLabel('paid'), 'Payé');
    });
    test('9. rejected -> Refusé', () {
      expect(merchantReferralStatusLabel('rejected'), 'Refusé');
    });
    test('10. cancelled -> Refusé', () {
      expect(merchantReferralStatusLabel('cancelled'), 'Refusé');
    });
    test('11. statut inconnu/absent -> En attente (jamais un crash ni un texte technique)', () {
      expect(merchantReferralStatusLabel(null), 'En attente');
      expect(merchantReferralStatusLabel('n_importe_quoi'), 'En attente');
    });
  });
}
