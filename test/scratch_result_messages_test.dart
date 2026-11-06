import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/game_daily_play.dart';
import 'package:proxi_play/utils/scratch_result_messages.dart';

// Messages under a losing scratch (validated 26/10/2026) and the rule for
// the shop QR invitation.
void main() {
  String compact(String path) =>
      File(path).readAsStringSync().replaceAll(RegExp(r'\s+'), '');

  test('the six validated final-draw messages', () {
    expect(kDrawLossMessages, [
      "C'est joué ! Rendez-vous au tirage final.",
      'Ta participation est enregistrée. Bonne chance !',
      'Pas de gain immédiat, mais tout reste possible !',
      'Ton ticket est dans la course. Croise les doigts !',
      "Le suspense continue jusqu'au tirage final !",
      "Une chance de gagner au tirage final, c'est déjà ça !",
    ]);
  });

  test('the six validated messages of a game without final draw', () {
    expect(kInstantLossMessages, [
      'Pas cette fois… mais demain est un autre jour !',
      "La chance n'était pas au rendez-vous. À demain !",
      "Raté pour aujourd'hui, mais garde le sourire !",
      "Ce n'est pas gagné… pour cette fois !",
      "Merci d'avoir joué ! Reviens tenter ta chance demain.",
      "Pas de lot aujourd'hui, mais le jeu continue !",
    ]);
    for (final message in kInstantLossMessages) {
      expect(message.toLowerCase(), isNot(contains('tirage')));
    }
  });

  test('draw messages only for a game known to have a final draw', () {
    expect(lossMessagePool(hasMainPrize: true), kDrawLossMessages);
    expect(lossMessagePool(hasMainPrize: false), kInstantLossMessages);
    expect(lossMessagePool(hasMainPrize: null), kInstantLossMessages);
  });

  test('the shop QR invitation follows every new, losing classic play independently of QR availability', () {
    expect(mayInviteToShopQr(isClassicPlay: true, isWin: false, isReplay: false), isTrue);
    expect(mayInviteToShopQr(isClassicPlay: false, isWin: false, isReplay: false), isFalse,
        reason: 'the QR play itself never receives the invitation');
    expect(mayInviteToShopQr(isClassicPlay: true, isWin: true, isReplay: false), isFalse);
    expect(mayInviteToShopQr(isClassicPlay: true, isWin: false, isReplay: true), isFalse,
        reason: 'a replayed result keeps its classic message only');
  });

  test('a used QR play never suppresses a later classic-loss invitation', () {
    final state = dailyPlayState(
      ticketIds: ['20261026_uid', '20261026_uid_qr'],
      lastPlay: DateTime(2026, 10, 26, 15),
      now: DateTime(2026, 10, 26, 15),
    );
    expect(state.shopPlayedToday, isTrue);
    expect(mayInviteToShopQr(isClassicPlay: true, isWin: false, isReplay: false), isTrue);
  });

  test('the result page picks the draw pool from the stored main-prize flag only', () {
    final page = compact('lib/pages/joueur/play_joueur_page/play_joueur_page_widget.dart');
    expect(page, contains('finalmainPrize=game!=null&&game.hasHasMainPrize()&&game.hasMainPrize;'));
    expect(page, contains('lossMessagePool(hasMainPrize:mainPrize)'));
    expect(page, contains('this.isClassicPlay=false'));
  });

  test('the game page allows the invitation only for a classic play', () {
    final detail = compact('lib/pages/joueur/jeu_detail_joueur_page/jeu_detail_joueur_page_widget.dart');
    // Both public buttons: never for the shop play itself, regardless of
    // whether the QR part was already consumed.
    expect(RegExp(r'_isClassicPlayAfterPlay=!shopPlay;').allMatches(detail).length, 2);
    // QR-only plays reset it.
    expect(detail, contains('_currentAttemptId=id;//QR-onlyplays:noclassicplay,sonoshopQRinvitation._isClassicPlayAfterPlay=false;'));
    // Not for a replay nor when the server says it was the shop play.
    expect(detail, contains("isClassicPlay:_isClassicPlayAfterPlay&&!outcome.alreadyParticipatedToday&&!(response.jsonBodyisMap&&(response.jsonBodyasMap)['shopPlay']==true),"));
  });

  test('all participation callers identify classic versus QR plays', () {
    final share = compact(
        'lib/pages/joueur/share_jeu_page/share_jeu_page_widget.dart');
    expect(share, contains('_isClassicPlayAfterPlay=!shopPlay;'));
    expect(share, contains("isClassicPlay:_isClassicPlayAfterPlay&&!outcome.alreadyParticipatedToday&&!(response.jsonBodyisMap&&(response.jsonBodyasMap)['shopPlay']==true),"));
    final route = compact('lib/flutter_flow/nav/nav.dart');
    expect(route, isNot(contains('isClassicPlay:')),
        reason: 'a direct route has no participation mode to classify');
  });
}
