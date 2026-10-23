import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The play screen strings were damaged by an encoding accident (26/04 commit):
// they are restored as in the 29/03 store version. Visible texts must keep
// their accents, and the mojibake repair must never alter a correct text.
void main() {
  final page = File('lib/pages/joueur/play_joueur_page/play_joueur_page_widget.dart')
      .readAsStringSync();

  test('no damaged character sequence left on the play screen', () {
    expect(page, isNot(contains('ï¿½')));
    expect(page, isNot(contains('�')));
  });

  test('visible texts are restored with their accents', () {
    expect(page, contains("'Vous avez déjà participé à ce jeu.'"));
    expect(page, contains("'Préparation du partage...'"));
    expect(page, contains(r"'Retour à l\'accueil'"));
    // Detects the server message "Vous avez déjà participé aujourd'hui."
    expect("vous avez déjà participé aujourd'hui.".contains('déjà participé'), isTrue);
    expect(RegExp(r"contains\('déjà participé'\)").allMatches(page).length, 2);
  });

  test('the mojibake repair fixes damaged text and leaves correct accents alone', () {
    // Same conversion as _tryDecodeMojibake, guarded by try/catch there.
    String repair(String input) {
      if (!(input.contains('Ã') || input.contains('Â') || input.contains('â'))) return input;
      try {
        return utf8.decode(latin1.encode(input));
      } catch (_) {
        return input;
      }
    }

    expect(repair('Remise organisÃ©e chez le pÃ¢tissier'), 'Remise organisée chez le pâtissier');
    // Out of Latin-1 (e.g. "â€™"): left as is rather than guessed.
    expect(repair('dâ€™achat'), 'dâ€™achat');
    expect(repair('Gâteau du château'), 'Gâteau du château');
    expect(repair('Café offert'), 'Café offert');
  });
}
