import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/qr_game_presentation.dart';

void main() {
  test('new QR game keeps the presentation separate from its main prize', () {
    final result = resolveQrGamePresentation(
      description: 'test description',
      mainPrizeDescription: 'test lot principale',
      mainPrizeTitle: 'test lot principale',
      isQrOnly: true,
    );

    expect(result.gameDescription, 'test description');
    expect(result.mainPrizeDescription, 'test lot principale');
  });

  test(
    'falls back to the main prize title before the historical description',
    () {
      final result = resolveQrGamePresentation(
        description: 'Présentation',
        mainPrizeDescription: ' ',
        mainPrizeTitle: 'Champagne',
        isQrOnly: true,
      );

      expect(result.gameDescription, 'Présentation');
      expect(result.mainPrizeDescription, 'Champagne');
    },
  );

  test(
    'legacy games keep description as their prize without duplicating it',
    () {
      final result = resolveQrGamePresentation(
        description: 'Champagne',
        mainPrizeDescription: null,
        mainPrizeTitle: null,
        isQrOnly: true,
      );

      expect(result.mainPrizeDescription, 'Champagne');
      expect(result.gameDescription, isEmpty);
    },
  );

  test(
    'does not duplicate a QR description identical to the resolved prize',
    () {
      final result = resolveQrGamePresentation(
        description: ' Champagne ',
        mainPrizeDescription: 'Champagne',
        mainPrizeTitle: null,
        isQrOnly: true,
      );

      expect(result.mainPrizeDescription, 'Champagne');
      expect(result.gameDescription, isEmpty);
    },
  );
}
