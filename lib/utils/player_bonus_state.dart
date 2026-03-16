import '/backend/backend.dart';

enum PlayerAccessState {
  normal,
  lowParts,
  noParts,
  bonusActive,
}

bool hasActiveReferralBonus(
  UsersRecord? user, {
  DateTime? now,
}) {
  if (user == null) {
    return false;
  }
  final currentTime = now ?? DateTime.now();
  final bonusExpiry = user.bonusExpiresAt ?? user.allGamesAccessUntil;
  final bonusMode = user.bonusMode.trim();
  final bonusSource = user.bonusSource.trim();

  if (bonusExpiry == null || !bonusExpiry.isAfter(currentTime)) {
    return false;
  }

  if (bonusMode.isEmpty) {
    return true;
  }

  return bonusMode == 'all_games_until_midnight' &&
      (bonusSource.isEmpty || bonusSource == 'referral');
}

PlayerAccessState resolvePlayerAccessState(
  UsersRecord? user, {
  DateTime? now,
}) {
  if (user == null) {
    return PlayerAccessState.normal;
  }
  if (hasActiveReferralBonus(user, now: now)) {
    return PlayerAccessState.bonusActive;
  }
  final remainingPart = user.remainingPart;
  if (remainingPart <= 0) {
    return PlayerAccessState.noParts;
  }
  if (remainingPart <= 1) {
    return PlayerAccessState.lowParts;
  }
  return PlayerAccessState.normal;
}
