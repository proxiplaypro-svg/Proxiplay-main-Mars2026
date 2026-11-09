import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/partner_play_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixedRandom implements Random {
  _FixedRandom(this.values);

  final List<int> values;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => values.removeAt(0) % max;
}

void main() {
  test(
      'exactly the three validated shop QR invitations, without unlimited promise',
      () {
    expect(kPartnerPlayMessages, [
      'Et si vous alliez faire les boutiques ?',
      'Un QR code en boutique, une chance en plus !',
      'Et si vous découvriez de nouveaux commerces ?',
    ]);
    for (final message in kPartnerPlayMessages) {
      final lower = message.toLowerCase();
      expect(lower, isNot(contains('illimit')));
      expect(lower, isNot(contains('gratuit')));
    }
  });

  test('a last index stored by an older version never blocks a message', () {
    final random = Random(11);
    for (var i = 0; i < 200; i++) {
      final index = pickPartnerPlayMessageIndex(random, lastIndex: 4);
      if (index != null) expect(index, inInclusiveRange(0, 2));
    }
  });

  test(
      'about one losing scratch out of three, never the same message twice in a row',
      () {
    final random = Random(42);
    int? last;
    var shown = 0;
    const draws = 30000;
    for (var i = 0; i < draws; i++) {
      final index = pickPartnerPlayMessageIndex(random, lastIndex: last);
      if (index == null) continue;
      shown++;
      expect(index, isNot(last));
      last = index;
    }
    expect(shown / draws, closeTo(1 / 3, 0.02));
  });

  test('can appear on the first eligible loss without a play counter', () {
    // The first draw opens the independent one-in-three gate; the second
    // selects a message. No previous play is required.
    expect(pickPartnerPlayMessageIndex(_FixedRandom([0, 0])), 0);

    // Each eligible loss starts a fresh random draw rather than advancing a
    // shared counter.
    expect(pickPartnerPlayMessageIndex(_FixedRandom([0, 1])), 1);
  });

  test('every message can appear', () {
    final random = Random(7);
    final seen = <int>{};
    int? last;
    for (var i = 0; i < 2000; i++) {
      final index = pickPartnerPlayMessageIndex(random, lastIndex: last);
      if (index != null) {
        seen.add(index);
        last = index;
      }
    }
    expect(seen, {0, 1, 2});
  });

  test('local USB override always selects a validated message', () {
    for (var seed = 0; seed < 20; seed++) {
      final index = pickPartnerPlayMessageIndex(Random(seed), force: true);
      expect(index, inInclusiveRange(0, kPartnerPlayMessages.length - 1));
    }
  });

  test('the last message is remembered on the device across scratches',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final random = Random(3);
    String? previous;
    for (var i = 0; i < 300; i++) {
      final message =
          await nextPartnerPlayMessage(random: random, prefs: prefs);
      if (message == null) continue;
      expect(message, isNot(previous));
      previous = message;
    }
  });

  test('shown only in the revealed scratch bonus slot of a real losing scratch',
      () {
    final page =
        File('lib/pages/joueur/play_joueur_page/play_joueur_page_widget.dart')
            .readAsStringSync()
            .replaceAll('\r\n', '\n');
    // Chosen in the losing branch of the reveal, never for a replay.
    final losing = page.indexOf('_model.isWin = false;\n');
    final chosen = page.indexOf('await nextPartnerPlayMessage()');
    expect(chosen, greaterThan(losing));
    final gate = page.substring(losing, chosen).replaceAll(RegExp(r'\s+'), '');
    expect(gate, contains('finalinvitationEligible=mayInviteToShopQr('));
    expect(gate, contains('isClassicPlay:widget.isClassicPlay'));
    expect(gate, contains('isReplay:isAlreadyPlayedStatus'));
    expect(page, contains('if (invitationEligible)'));
    // Reuse the ScratchCardWidget bonus slot. A real server bonus always wins
    // over the invitation, so an invitation has no prize/bonus side effect.
    expect(page,
        contains('final secondaryRevealText = rewardTextBonus.isNotEmpty'));
    expect(page, contains('? rewardTextBonus'));
    expect(
        page,
        contains(
            ': (_model.cardReveal ? _partnerPlayMessage ?? \'\' : \'\');'));
    expect(
        page,
        contains(
            'rewardTextBonus:\n                                                      secondaryRevealText'));
    expect(page, isNot(contains("'partner-play-message'")));
    expect(
        page,
        isNot(contains(
            'showDialog(context: context, builder: (_) => Text(_partnerPlayMessage')));
  });
}
