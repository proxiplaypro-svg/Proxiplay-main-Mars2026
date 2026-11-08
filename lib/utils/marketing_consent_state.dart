/// Player marketing preference, read from the server-written
/// `users/{uid}.marketing_consent` (the client never writes it).
enum MarketingConsentState {
  /// No answer yet: excluded from any commercial email.
  unanswered,

  /// Explicit agreement confirmed by the server.
  granted,

  /// Explicit withdrawal (or refusal) confirmed by the server.
  withdrawn,
}

MarketingConsentState marketingConsentStateOf(Map<String, dynamic>? consent) {
  if (consent == null || consent['enabled'] is! bool) {
    return MarketingConsentState.unanswered;
  }
  return consent['enabled'] == true
      ? MarketingConsentState.granted
      : MarketingConsentState.withdrawn;
}

/// Same threshold as the server (marketing_consent.js): an agreement needs a
/// birthday proving at least 15 years. The server remains the authority.
const int kMarketingMinimumAge = 15;

bool isMarketingEligibleBirthday(DateTime? birthday, {DateTime? now}) {
  if (birthday == null) return false;
  final today = now ?? DateTime.now();
  final threshold =
      DateTime(today.year - kMarketingMinimumAge, today.month, today.day);
  final day = DateTime(birthday.year, birthday.month, birthday.day);
  return !day.isAfter(threshold);
}

/// Player-facing message for a failed `setMarketingConsent` call.
String marketingConsentErrorMessage(String? code) {
  switch (code) {
    case 'not-found':
    case 'unimplemented':
      // The Callable is not deployed yet.
      return 'Ce réglage n’est pas encore disponible. Réessayez plus tard.';
    case 'failed-precondition':
      return 'Les e-mails ProxiPlay sont réservés aux joueurs de 15 ans et '
          'plus, d’après la date de naissance de votre profil.';
    case 'unauthenticated':
      return 'Votre session a expiré. Reconnectez-vous puis réessayez.';
    case 'unavailable':
    case 'deadline-exceeded':
      return 'Connexion impossible. Vérifiez votre réseau puis réessayez.';
    default:
      return 'Votre préférence n’a pas été enregistrée. Réessayez.';
  }
}

/// Message before calling the server for an agreement, or null when the
/// call may proceed. A missing birthday is told apart from an age under 15.
String? marketingConsentAgreementPrecheck(DateTime? birthday, {DateTime? now}) {
  if (birthday == null) {
    return 'Votre date de naissance n’est pas renseignée : elle est '
        'nécessaire pour recevoir les e-mails ProxiPlay.';
  }
  return isMarketingEligibleBirthday(birthday, now: now)
      ? null
      : marketingConsentErrorMessage('failed-precondition');
}

/// Signup box of the "Informations" step: players only, and only while no
/// preference is recorded (an existing account already answered from its
/// profile, where the choice is managed). Hidden for a birthday under 15.
bool shouldOfferSignupMarketingConsent({
  required bool isMerchant,
  required DateTime? birthday,
  required Map<String, dynamic>? storedConsent,
  DateTime? now,
}) =>
    !isMerchant &&
    marketingConsentStateOf(storedConsent) == MarketingConsentState.unanswered &&
    (birthday == null || isMarketingEligibleBirthday(birthday, now: now));

/// The signup sends one agreement, only for a checked box, an eligible
/// birthday and no recorded preference. An unchecked box sends nothing: no
/// answer is never stored as a refusal.
bool shouldSendSignupMarketingConsent({
  required bool isMerchant,
  required bool checked,
  required DateTime? birthday,
  required Map<String, dynamic>? storedConsent,
  DateTime? now,
}) =>
    checked &&
    birthday != null &&
    shouldOfferSignupMarketingConsent(
        isMerchant: isMerchant,
        birthday: birthday,
        storedConsent: storedConsent,
        now: now);
