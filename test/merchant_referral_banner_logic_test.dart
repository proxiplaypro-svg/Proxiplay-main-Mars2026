import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/pages/joueur/home_joueur_page/merchant_referral_banner_logic.dart';

void main() {
  group('shouldShowMerchantReferralBanner (fail-closed)', () {
    test('1. enabled=true confirmé par le serveur -> affiché', () {
      expect(shouldShowMerchantReferralBanner(true), isTrue);
    });

    test('2. enabled=false confirmé par le serveur -> masqué', () {
      expect(shouldShowMerchantReferralBanner(false), isFalse);
    });

    test('3. état null (config pas encore chargée, chargement en cours ou '
        'échec réseau) -> masqué par défaut (fail-closed)', () {
      expect(shouldShowMerchantReferralBanner(null), isFalse);
    });
  });
}
