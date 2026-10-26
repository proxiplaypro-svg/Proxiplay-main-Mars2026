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
