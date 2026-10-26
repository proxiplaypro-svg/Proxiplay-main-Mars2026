/// Congratulation shown on the player home once a referral bonus ("all games
/// until midnight") is granted. The server returns it only while the bonus
/// lasts and until it is acknowledged (acknowledgeReferralBonusNotice), for
/// every device of the account; the app checks the deadline again at display.
class ReferralBonusNotice {
  const ReferralBonusNotice({required this.referralId, required this.expiresAt});

  final String referralId;
  final DateTime expiresAt;

  static ReferralBonusNotice? fromMap(Object? map) {
    if (map is! Map) return null;
    final referralId = map['referralId'];
    final expiresAtMs = map['expiresAtMs'];
    if (referralId is! String || referralId.isEmpty || expiresAtMs is! num) {
      return null;
    }
    return ReferralBonusNotice(
      referralId: referralId,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMs.toInt()),
    );
  }

  bool isActiveAt(DateTime now) => expiresAt.isAfter(now);
}

const String referralBonusNoticeTitle = '🎉 Bravo, ton parrainage a fonctionné !';
const String referralBonusNoticeBody = 'Ton filleul s\'est inscrit grâce à toi !\n'
    'Tu peux maintenant jouer à tous les jeux jusqu\'à minuit.\n'
    'Profite de ton bonus !';
const String referralBonusNoticeButton = 'Découvrir les jeux';

/// Ticket of a referral game granted to the inviter (instead of the classic
/// bonus while a referral game runs). Returned by the server until it is
/// acknowledged (kind "ticket") and while the game is not drawn.
class ReferralTicketNotice {
  const ReferralTicketNotice({
    required this.referralId,
    required this.gameId,
    required this.gameTitle,
    required this.ticketCount,
  });

  final String referralId;
  final String gameId;
  final String gameTitle;
  final int ticketCount;

  static ReferralTicketNotice? fromMap(Object? map) {
    if (map is! Map) return null;
    final referralId = map['referralId'];
    final gameId = map['gameId'];
    final count = map['ticketCount'];
    if (referralId is! String || referralId.isEmpty || gameId is! String ||
        gameId.isEmpty || count is! num || count < 1) {
      return null;
    }
    final title = map['gameTitle'];
    return ReferralTicketNotice(
      referralId: referralId,
      gameId: gameId,
      gameTitle: title is String ? title.trim() : '',
      ticketCount: count.toInt(),
    );
  }
}

const String referralTicketNoticeTitle = '🎟️ Ton filleul s\'est inscrit !';
const String referralTicketNoticeButton = 'Voir le jeu de parrainage';

String referralTicketNoticeBody(ReferralTicketNotice notice) {
  final count = notice.ticketCount;
  final game = notice.gameTitle.isEmpty ? 'du jeu de parrainage' : '« ${notice.gameTitle} »';
  return 'Tu gagnes 1 ticket pour le tirage $game.\n'
      'Tu as maintenant $count ${count > 1 ? 'tickets' : 'ticket'}.';
}

/// Whether the ticket window must be presented now, and records it.
bool takeReferralTicketNotice(String accountId, ReferralTicketNotice? notice) {
  if (notice == null || accountId.isEmpty) return false;
  return _presentedNotices.add('$accountId/ticket/${notice.referralId}');
}

/// "Bonus parrainage actif" on the home while the access read by the
/// participation server (allGamesAccessUntil) lasts, chances left or not.
bool shouldShowReferralBonusBanner(DateTime? allGamesAccessUntil, DateTime now) =>
    allGamesAccessUntil != null && allGamesAccessUntil.isAfter(now);

// Presented in this app session (per account and bonus), so a slow or failed
// acknowledgement never shows the window twice on this device.
final Set<String> _presentedNotices = {};

/// Whether the window must be presented now, and records it as presented.
bool takeReferralBonusNotice(
  String accountId,
  ReferralBonusNotice? notice,
  DateTime now,
) {
  if (notice == null || accountId.isEmpty || !notice.isActiveAt(now)) {
    return false;
  }
  return _presentedNotices.add('$accountId/${notice.referralId}');
}
