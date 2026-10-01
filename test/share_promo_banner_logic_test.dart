import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/models/share_promo_models.dart';
import 'package:proxi_play/pages/joueur/home_joueur_page/share_promo_banner_logic.dart';

SharePromoStateViewModel _state(bool showBanner) => SharePromoStateViewModel(
      showBanner: showBanner,
      kind: showBanner ? 'lowRemainingPlaysInvite' : null,
      title: null,
      message: null,
      ctaText: null,
      action: null,
      animationId: null,
      rewardType: null,
      rewardValue: null,
    );

void main() {
  group('shouldShowHomeInviteBanner (fail-closed)', () {
    test('1. showBanner=true confirmé par le serveur -> affichée', () {
      expect(shouldShowHomeInviteBanner(_state(true)), isTrue);
    });

    test('2. showBanner=false confirmé par le serveur -> masquée', () {
      expect(shouldShowHomeInviteBanner(_state(false)), isFalse);
    });

    test('3. état null (config pas encore chargée, chargement en cours ou '
        'échec réseau) -> masquée par défaut (fail-closed)', () {
      expect(shouldShowHomeInviteBanner(null), isFalse);
    });
  });
}
