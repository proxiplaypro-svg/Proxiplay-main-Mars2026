import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/main_prize_presentation.dart';

void main() {
  test(
      'main prize with title and description presents both without duplication',
      () {
    final prize = mainPrizePresentation(
      hasMainPrize: true,
      title: 'Panier gourmand',
      description: 'À retirer en boutique.',
    );
    expect(prize.hasContent, isTrue);
    expect(prize.title, 'Panier gourmand');
    expect(prize.hasDistinctDescription, isTrue);
  });

  test('main prize with a title only is presented', () {
    final prize = mainPrizePresentation(
      hasMainPrize: true,
      title: 'Panier gourmand',
    );
    expect(prize.hasContent, isTrue);
    expect(prize.title, 'Panier gourmand');
    expect(prize.hasDistinctDescription, isFalse);
  });

  test('main prize with a description only is presented', () {
    final prize = mainPrizePresentation(
      hasMainPrize: true,
      description: 'Un panier gourmand à retirer en boutique.',
    );
    expect(prize.hasContent, isTrue);
    expect(prize.title, isEmpty);
    expect(prize.description, 'Un panier gourmand à retirer en boutique.');
  });

  test('duplicated title and description are rendered only once', () {
    final prize = mainPrizePresentation(
      hasMainPrize: true,
      title: 'Panier gourmand',
      description: 'Panier gourmand',
    );
    expect(prize.hasContent, isTrue);
    expect(prize.hasDistinctDescription, isFalse);
  });

  test('instant-win-only and no-main-prize games do not present a main prize',
      () {
    final prize = mainPrizePresentation(
      hasMainPrize: false,
      title: 'Lot principal résiduel',
      description: 'Description résiduelle',
    );
    expect(prize.hasContent, isFalse);
  });

  test('QR games use the same dedicated prize fields', () {
    final prize = mainPrizePresentation(hasMainPrize: true, title: 'Lot QR');
    expect(prize.hasContent, isTrue);
    expect(prize.title, 'Lot QR');
  });

  test('the general game description is never a fallback', () {
    final prize = mainPrizePresentation(hasMainPrize: true);
    expect(prize.hasContent, isFalse);
  });
}
