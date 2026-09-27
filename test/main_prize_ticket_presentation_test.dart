import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/main_prize_ticket_presentation.dart';

void main() {
  test('shows a validated ticket only for a game with a main prize', () {
    expect(shouldShowMainPrizeTicket(hasMainPrize: true), isTrue);
  });

  test('hides the validated ticket for instant-win-only and legacy games', () {
    expect(shouldShowMainPrizeTicket(hasMainPrize: false), isFalse);
    expect(shouldShowMainPrizeTicket(hasMainPrize: null), isFalse);
  });
}
