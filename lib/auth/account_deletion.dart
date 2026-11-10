/// Suppression du compte par le joueur (1.1.4).
///
/// Firebase Auth refuse la suppression quand la derniere connexion est trop
/// ancienne (`requires-recent-login`). Avant la 1.1.4, ce refus affichait un
/// message en anglais puis l'app renvoyait quand meme vers la connexion : le
/// joueur pouvait croire son compte supprime. Toute autre erreur etait
/// ignoree de la meme facon.
///
/// Ici, seule une suppression confirmee par Firebase vaut `deleted` ; le
/// joueur est sinon informe que son compte existe toujours. Les donnees
/// Firestore sont ensuite effacees cote serveur par onUserDeleted.
library;

enum AccountDeletionOutcome {
  /// Firebase Auth a supprime le compte.
  deleted,

  /// Une connexion recente est exigee et la reauthentification n'a pas eu
  /// lieu (methode indisponible ou echec) : le compte existe toujours.
  requiresRecentLogin,

  /// Le joueur a abandonne la reauthentification : compte conserve.
  cancelled,

  /// Mot de passe ou identifiants refuses : compte conserve.
  reauthenticationFailed,

  /// Autre echec (reseau, compte desactive...) : compte conserve.
  failed,

  /// Aucun joueur connecte.
  notSignedIn,
}

/// Mode de reauthentification, deduit des fournisseurs du compte.
enum ReauthMethod { password, google, apple, unsupported }

const String kAccountDeletedMessage = 'Votre compte a été supprimé.';

const String kAccountDeletionCancelledMessage =
    'Suppression annulée : votre compte n’a pas été supprimé.';

const String kAccountDeletionFailedMessage =
    'La suppression a échoué : votre compte n’a pas été supprimé. '
    'Vérifiez votre connexion puis réessayez.';

const String kRecentLoginRequiredTitle = 'Confirmez votre identité';

const String kRecentLoginRequiredMessage =
    'Par sécurité, la suppression du compte exige une connexion récente. '
    'Votre compte n’a pas été supprimé.\n\n'
    'Déconnectez-vous, reconnectez-vous, puis relancez la suppression depuis '
    'votre profil.';

const String kReauthPasswordTitle = 'Confirmez votre mot de passe';

const String kReauthPasswordMessage =
    'Par sécurité, saisissez votre mot de passe pour confirmer la suppression '
    'définitive de votre compte.';

const String kReauthWrongPasswordMessage =
    'Identifiants incorrects : votre compte n’a pas été supprimé.';

bool isWrongCredential(String? code) =>
    code == 'wrong-password' ||
    code == 'invalid-credential' ||
    code == 'invalid-login-credentials';

/// Code Firebase Auth de l'erreur, ou null si ce n'en est pas une.
typedef AuthErrorCode = String? Function(Object error);

ReauthMethod reauthMethodFor(Iterable<String> providerIds) {
  final ids = providerIds.toSet();
  if (ids.contains('password')) return ReauthMethod.password;
  if (ids.contains('google.com')) return ReauthMethod.google;
  if (ids.contains('apple.com')) return ReauthMethod.apple;
  return ReauthMethod.unsupported;
}

bool isRecentLoginRequired(String? code) =>
    code == 'requires-recent-login' || code == 'user-token-expired';

/// Supprime le compte ; si une connexion recente est exigee, lance
/// [reauthenticate] (qui renvoie false si le joueur annule, true si la
/// reauthentification a reussi, et leve une erreur si elle a echoue) puis
/// retente une seule fois.
Future<AccountDeletionOutcome> deleteAccountWithReauth({
  required bool signedIn,
  required Future<void> Function() delete,
  required Future<bool> Function() reauthenticate,
  required AuthErrorCode errorCode,
}) async {
  if (!signedIn) return AccountDeletionOutcome.notSignedIn;
  try {
    await delete();
    return AccountDeletionOutcome.deleted;
  } catch (error) {
    if (!isRecentLoginRequired(errorCode(error))) {
      return AccountDeletionOutcome.failed;
    }
  }

  bool reauthenticated;
  try {
    reauthenticated = await reauthenticate();
  } catch (error) {
    return isWrongCredential(errorCode(error))
        ? AccountDeletionOutcome.reauthenticationFailed
        : AccountDeletionOutcome.requiresRecentLogin;
  }
  if (!reauthenticated) return AccountDeletionOutcome.cancelled;

  try {
    await delete();
    return AccountDeletionOutcome.deleted;
  } catch (error) {
    return isRecentLoginRequired(errorCode(error))
        ? AccountDeletionOutcome.requiresRecentLogin
        : AccountDeletionOutcome.failed;
  }
}
