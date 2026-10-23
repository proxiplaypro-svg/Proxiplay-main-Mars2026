import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/main_prize_draw_presentation.dart';

void main() {
  String? status({bool ended = true, bool prize = true, bool winner = false, Object? draw}) =>
      mainPrizeDrawStatusMessage(ended: ended, hasMainPrize: prize, hasWinner: winner, drawStatus: draw);

  test('finished game with no draw announces the pending draw', () {
    expect(status(), 'Tirage au sort en attente');
  });
  test('terminal draw with no eligible player does not invent a winner', () {
    expect(status(draw: 'no_eligible_entries'), 'Tirage effectué sans gagnant.');
  });
  test('completed draw missing public winner is not called pending', () {
    expect(status(draw: 'completed'), 'Résultat du tirage indisponible.');
  });
  test('does not show a draw status for ongoing games, winners or absent prizes', () {
    expect(status(ended: false), isNull);
    expect(status(winner: true), isNull);
    expect(status(prize: false), isNull);
    expect(status(draw: 'no_main_prize'), isNull);
  });
}
