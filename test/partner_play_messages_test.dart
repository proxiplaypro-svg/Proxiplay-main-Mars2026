import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/partner_play_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('exactly the three validated shop QR invitations, without unlimited promise', () {
    expect(kPartnerPlayMessages, [
      'Passe sur place et scanne le QR pour rejouer !',
      "Pas gagné ? Une nouvelle chance t'attend sur place !",
      'Envie de retenter ta chance ? Scanne le QR sur place !',
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

  test('about one losing scratch out of three, never the same message twice in a row', () {
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

  test('the last message is remembered on the device across scratches', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final random = Random(3);
    String? previous;
    for (var i = 0; i < 300; i++) {
      final message = await nextPartnerPlayMessage(random: random, prefs: prefs);
      if (message == null) continue;
      expect(message, isNot(previous));
      previous = message;
    }
  });

  test('shown only in the result panel of a real losing scratch', () {
    final page = File('lib/pages/joueur/play_joueur_page/play_joueur_page_widget.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    // Chosen in the losing branch of the reveal, never for a replay.
    final losing = page.indexOf('_model.isWin = false;\n');
    final chosen = page.indexOf('await nextPartnerPlayMessage()');
    expect(chosen, greaterThan(losing));
    final gate = page.substring(losing, chosen).replaceAll(RegExp(r'\s+'), '');
    expect(gate, contains('if(mayInviteToShopQr('));
    expect(gate, contains('shopQrPlayAvailable:widget.shopQrPlayAvailable'));
    expect(gate, contains('isReplay:isAlreadyPlayedStatus'));
    // Displayed inside the existing result panel, never after a win, no popup.
    final display = page.indexOf("ValueKey(\n                                                  'partner-play-message')");
    expect(display, greaterThan(page.indexOf('if (_model.cardReveal)\n                                  Container(')));
    expect(page.substring(display - 300, display), contains('?.isWin !=\n                                                  true'));
    expect(page, isNot(contains('showDialog(context: context, builder: (_) => Text(_partnerPlayMessage')));
  });
}
