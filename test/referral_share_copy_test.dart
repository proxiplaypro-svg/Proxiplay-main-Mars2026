import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/models/share_promo_models.dart';
import 'package:proxi_play/utils/referral_share_copy.dart';

void main() {
  group('referral wording follows the referral game state', () {
    test('without a referral game the "until midnight" promise is kept', () {
      expect(referralInviteHeadline(referralGameActive: false),
          'Invitez un ami et jouez à tous les jeux jusqu’à minuit !');
      final message =
          buildReferralInviteMessage(referralGameActive: false, referralCode: 'ABC123');
      expect(message, contains('jouer à tous les jeux jusqu’à minuit'));
      expect(message, isNot(contains('ticket')));
      expect(message, contains('Code parrainage : ABC123'));
      expect(message, contains('ref=ABC123'));
    });

    test('during a referral game only the inviter ticket is promised', () {
      expect(referralInviteHeadline(referralGameActive: true),
          'Invitez un ami et gagnez un ticket pour le tirage au sort !');
      for (final message in [
        buildReferralInviteMessage(referralGameActive: true, referralCode: 'ABC123'),
        buildReferralReminderMessage(referralGameActive: true, referralCode: 'ABC123'),
      ]) {
        // The friend is told the inviter (not the friend) gets the ticket,
        // once the signup is validated.
        expect(message,
            contains('Quand ton inscription est validée, c’est moi qui gagne un ticket'));
        expect(message, isNot(contains('minuit')));
        expect(message, isNot(contains('lot bonus')));
      }
    });

    test('an unknown state promises nothing rather than a wrong reward', () {
      expect(referralInviteHeadline(referralGameActive: null), isNull);
      final message =
          buildReferralInviteMessage(referralGameActive: null, referralCode: 'ABC123');
      expect(message, isNot(contains('minuit')));
      expect(message, isNot(contains('ticket')));
      expect(message, contains('ABC123'));
    });

    test('the server flag is read from callable responses, absent means classic', () {
      expect(referralGameActiveFrom({'referralGameActive': true}), isTrue);
      expect(referralGameActiveFrom({'referralGameActive': false}), isFalse);
      expect(referralGameActiveFrom(<String, dynamic>{}), isFalse);
      expect(referralGameActiveFrom(null), isFalse);
      expect(
          SharePromoStateViewModel.fromMap({'showBanner': false, 'referralGameActive': true})
              .referralGameActive,
          isTrue);
      expect(SharePromoStateViewModel.fromMap({'showBanner': true}).referralGameActive,
          isFalse);
    });
  });
}
