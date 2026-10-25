import 'share_links.dart';

/// Daily participation rule of a public game (1.1.2): one classic play,
/// which costs a chance, plus at most one free play from the shop QR,
/// before or after the classic one. A QR-only game keeps a single daily
/// play. The server stays the authority; this only decides which play the
/// buttons offer and what they send.
///
/// Server ticket ids (games/{game}/participants): `<day>_<uid>` for the
/// classic play, `<day>_<uid>_qr` for the shop QR play.
const String shopQrTicketSuffix = '_qr';

/// Button label of the free shop play.
const String shopPlayButtonLabel = 'Jouer ma partie offerte';

String localDayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

class DailyPlayState {
  const DailyPlayState({
    required this.classicPlayedToday,
    required this.shopPlayedToday,
  });

  final bool classicPlayedToday;
  final bool shopPlayedToday;
}

/// [ticketIds]: the player's ticket ids for this game. [lastPlay]: the
/// participants_details last play; a play today without any ticket today is
/// an older record and counts as the classic play, as on the server.
DailyPlayState dailyPlayState({
  required Iterable<String> ticketIds,
  required DateTime? lastPlay,
  required DateTime now,
}) {
  final today = '${localDayKey(now)}_';
  final todays = ticketIds.where((id) => id.startsWith(today)).toList();
  final shop = todays.any((id) => id.endsWith(shopQrTicketSuffix));
  final classic = todays.any((id) => !id.endsWith(shopQrTicketSuffix));
  final playedToday = lastPlay != null && localDayKey(lastPlay) == localDayKey(now);
  return DailyPlayState(
    classicPlayedToday: classic || (playedToday && !shop),
    shopPlayedToday: shop,
  );
}

// In memory, like the scan token: the shop play known as used today, and a
// shop play whose answer was lost (network cut, timeout), kept with its
// attempt id so a new tap replays it instead of starting a paid play.
final Map<String, String> _shopPlayUsedDay = {};
final Map<String, String> _pendingShopPlayAttempts = {};

bool shopPlayUsedToday(String gameId, DateTime now) =>
    _shopPlayUsedDay[gameId] == localDayKey(now);

void markShopPlayUsedToday(String gameId, DateTime now) {
  _shopPlayUsedDay[gameId] = localDayKey(now);
}

String? pendingShopPlayAttempt(String gameId) =>
    _pendingShopPlayAttempts[gameId];

/// Whether the free shop play is offered now for a public game.
bool offersShopPlay({
  required String gameId,
  required DailyPlayState state,
  required DateTime now,
}) {
  if (gameQrToken(gameId) == null) {
    return false;
  }
  if (pendingShopPlayAttempt(gameId) != null) {
    return true;
  }
  return !state.shopPlayedToday && !shopPlayUsedToday(gameId, now);
}

/// Attempt id of a shop play: the pending one if its answer was lost.
String shopPlayAttemptId(String gameId, String Function() create) =>
    _pendingShopPlayAttempts[gameId] ??= create();

/// Error codes the server itself returns; any other failure (unavailable,
/// deadline-exceeded, internal, client timeout) may hide a committed play.
const Set<String> _serverAnswerCodes = {
  'failed-precondition',
  'not-found',
  'invalid-argument',
  'permission-denied',
  'unauthenticated',
  'already-exists',
  'resource-exhausted',
};

/// Records the answer to a shop play. [shopPlayDone]: the server accepted
/// it, replayed it, or reports it already used today.
void settleShopPlayAttempt(
  String gameId, {
  required bool succeeded,
  required DateTime now,
  String? errorCode,
  bool shopPlayDone = false,
}) {
  if (succeeded || _serverAnswerCodes.contains(errorCode)) {
    _pendingShopPlayAttempts.remove(gameId);
  }
  if (succeeded && shopPlayDone) {
    markShopPlayUsedToday(gameId, now);
  }
}

/// The server refused the scan token (expired or replaced poster): it is
/// dropped, so the button offers the normal play again.
void forgetRefusedShopQr(String gameId, Object? errorDetails) {
  if (errorDetails is Map && errorDetails['reason'] == 'invalid_shop_qr') {
    forgetGameQrToken(gameId);
  }
}

/// Payload fields of a public game play: the token goes only with the
/// shop play, so a classic play never depends on a stale scan.
Map<String, dynamic> dailyPlayPayloadFields(String gameId,
        {required bool shopPlay}) =>
    {
      'participation_mode': shopPlay ? 'qr' : 'classic',
      'qr_token': shopPlay ? gameQrToken(gameId) : null,
    };
