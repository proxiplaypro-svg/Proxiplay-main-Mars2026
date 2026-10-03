import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/main_prize_ticket_presentation.dart';

/// Regression guard for the "🎫 N ticket(s) validé(s)" call site in
/// play_joueur_page_widget.dart (the "déjà joué aujourd'hui" block). Bug:
/// that Text was shown whenever ticketCount > 0, with no check on whether
/// the game actually has a main prize - a purely instant-win game falsely
/// implied a final draw entry existed.
///
/// shouldShowMainPrizeTicket/mainPrizeTicketLabel are already fully
/// unit-tested in isolation (main_prize_ticket_presentation_test.dart). The
/// only thing that was actually broken was the WIRING at this one call
/// site, which never called them at all. Widget-testing this FutureBuilder
/// would require mocking Firebase/GamesRecord/FirebaseAuth for no extra
/// protection against that real risk (silently dropping the gate, or
/// reverting to the old hardcoded string) - so, same convention as
/// test/merchant_signup_entry_point_test.dart's static source-content
/// checks, this guards the call site directly from the source text instead.
void main() {
  final source = File(
    'lib/pages/joueur/play_joueur_page/play_joueur_page_widget.dart',
  ).readAsStringSync();

  // Isolate the exact ticket-count block so a match elsewhere in this
  // 1000+-line file can't give a false pass.
  final blockStart = source.indexOf('final ticketCount =');
  const labelCall = 'mainPrizeTicketLabel(';
  final blockEnd = source.indexOf(labelCall, blockStart);

  setUpAll(() {
    expect(blockStart, greaterThan(-1),
        reason: 'ticket-count block not found - has this call site moved '
            'or been rewritten?');
    expect(blockEnd, greaterThan(blockStart));
  });

  group('play_joueur_page ticket-validé gate (regression)', () {
    test('the call site actually uses shouldShowMainPrizeTicket to decide '
        'whether the block may render', () {
      final block = source.substring(blockStart, blockEnd);
      expect(block, contains('shouldShowMainPrizeTicket('));
    });

    test('hasMainPrize=false: an early return hides the block regardless of '
        'ticketCount', () {
      final block = source.substring(blockStart, blockEnd);
      // showTicketCount is assigned straight from shouldShowMainPrizeTicket,
      // which returns false for hasMainPrize: false/null (see
      // main_prize_ticket_presentation_test.dart) - this guard is the only
      // thing standing between that flag and the widget tree.
      expect(block, contains('if (ticketCount <= 0 ||'));
      expect(block, contains('!showTicketCount)'));
      expect(shouldShowMainPrizeTicket(hasMainPrize: false), isFalse);
    });

    test('hasMainPrize=true and ticketCount>0: the guard above does not '
        'early-return, so the block (built with mainPrizeTicketLabel) can '
        'render', () {
      expect(shouldShowMainPrizeTicket(hasMainPrize: true), isTrue);
      // With showTicketCount==true and ticketCount>0, both operands of
      // "ticketCount <= 0 || !showTicketCount" are false -> no early return,
      // execution reaches the Text built from mainPrizeTicketLabel.
      final block = source.substring(blockStart, blockEnd + labelCall.length);
      expect(block, contains(labelCall));
    });

    test('no regression to the old hardcoded ticket string in this file', () {
      expect(source, isNot(contains("tickets validés' : 'ticket validé'")));
    });
  });
}
