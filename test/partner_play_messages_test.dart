import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/partner_play_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('exactly the five validated messages, without unlimited or same-game promise', () {
    expect(kPartnerPlayMessages, [
      'Pas gagné ? Retentez votre chance chez un partenaire !',
      'Des parties supplémentaires chez nos partenaires !',
      'Plus de chances ? Jouez encore chez nos partenaires !',
      'Scannez un QR code partenaire pour jouer gratuitement !',
      'Vos 3 chances sont épuisées ? Scannez chez un partenaire !',
    ]);
    for (final message in kPartnerPlayMessages) {
      final lower = message.toLowerCase();
      expect(lower, isNot(contains('illimit')));
      expect(lower, isNot(contains('ce jeu')));
      expect(lower, isNot(contains("aujourd'hui")));
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
    expect(seen, {0, 1, 2, 3, 4});
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
    expect(page.substring(losing, chosen), contains('if (!isAlreadyPlayedStatus)'));
    // Displayed inside the existing result panel, never after a win, no popup.
    final display = page.indexOf("ValueKey(\n                                                  'partner-play-message')");
    expect(display, greaterThan(page.indexOf('if (_model.cardReveal)\n                                  Container(')));
    expect(page.substring(display - 300, display), contains('?.isWin !=\n                                                  true'));
    expect(page, isNot(contains('showDialog(context: context, builder: (_) => Text(_partnerPlayMessage')));
  });
}
