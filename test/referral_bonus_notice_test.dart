import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/components/referral_bonus_congrats_dialog.dart';
import 'package:proxi_play/models/share_promo_models.dart';
import 'package:proxi_play/utils/referral_bonus_notice.dart';

// Referral bonus congratulation (26/10/2026): window once per granted bonus
// while it lasts, banner while the access lasts, chances left or not.
void main() {
  final now = DateTime(2026, 10, 26, 15);
  final midnight = DateTime(2026, 10, 27);

  test('the server notice is read from getSharePromoState', () {
    final state = SharePromoStateViewModel.fromMap({
      'showBanner': false,
      'referralBonusNotice': {'referralId': 'r1', 'expiresAtMs': midnight.millisecondsSinceEpoch},
    });
    expect(state.referralBonusNotice!.referralId, 'r1');
    expect(state.referralBonusNotice!.expiresAt, midnight);
    for (final bad in [null, 'x', {'referralId': ''}, {'referralId': 'r', 'expiresAtMs': 'soon'}]) {
      expect(ReferralBonusNotice.fromMap(bad), isNull, reason: '$bad');
    }
    expect(SharePromoStateViewModel.fromMap({'showBanner': true}).referralBonusNotice, isNull);
  });

  test('presented once per account and bonus, never once expired', () {
    final notice = ReferralBonusNotice(referralId: 'once-1', expiresAt: midnight);
    expect(takeReferralBonusNotice('player', notice, now), isTrue);
    expect(takeReferralBonusNotice('player', notice, now), isFalse, reason: 'already presented');
    expect(takeReferralBonusNotice('other', notice, now), isTrue, reason: 'another account');
    final next = ReferralBonusNotice(referralId: 'once-2', expiresAt: midnight);
    expect(takeReferralBonusNotice('player', next, now), isTrue, reason: 'a new bonus');
    final expired = ReferralBonusNotice(referralId: 'once-3', expiresAt: now);
    expect(takeReferralBonusNotice('player', expired, now), isFalse);
    expect(takeReferralBonusNotice('player', null, now), isFalse);
    expect(takeReferralBonusNotice('', next, now), isFalse);
  });

  test('the bonus banner follows the access only, chances left or not', () {
    expect(shouldShowReferralBonusBanner(midnight, now), isTrue);
    expect(shouldShowReferralBonusBanner(now, now), isFalse, reason: 'expired at midnight');
    expect(shouldShowReferralBonusBanner(null, now), isFalse);
    final home = File('lib/pages/joueur/home_joueur_page/home_joueur_page_widget.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'\s+'), '');
    final banner = home.indexOf('if(shouldShowReferralBonusBanner(');
    final remainingGate = home.indexOf('if(hasRemainingPart){returnconstSizedBox.shrink();}');
    expect(banner, isNot(-1));
    expect(remainingGate, greaterThan(banner),
        reason: 'the banner is decided before the "chances left" early return');
  });

  test('the home presents it after loading, re-checks the deadline and acknowledges it', () {
    final home = File('lib/pages/joueur/home_joueur_page/home_joueur_page_widget.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'\s+'), '');
    expect(home, contains('_presentReferralBonusNotice(state.referralBonusNotice);'));
    expect(home, contains('if(!takeReferralBonusNotice(currentUserUid,notice,DateTime.now())){return;}'));
    expect(home, contains('if(!mounted||!notice!.isActiveAt(DateTime.now())){return;}'));
    expect(home, contains('.acknowledgeReferralBonusNotice(notice.referralId)'));
    expect(home, contains('builder:(_)=>constReferralBonusCongratsDialog()'));
  });

  testWidgets('the window shows the validated text and closes on its button', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const ReferralBonusCongratsDialog(),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('🎉 Bravo, ton parrainage a fonctionné !'), findsOneWidget);
    expect(
        find.text("Ton filleul s'est inscrit grâce à toi !\n"
            "Tu peux maintenant jouer à tous les jeux jusqu'à minuit.\n"
            'Profite de ton bonus !'),
        findsOneWidget);
    await tester.tap(find.text('Découvrir les jeux'));
    await tester.pumpAndSettle();
    expect(find.byType(ReferralBonusCongratsDialog), findsNothing);
  });
}
