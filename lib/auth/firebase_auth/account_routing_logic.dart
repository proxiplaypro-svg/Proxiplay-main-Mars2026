import '/backend/schema/enums/enums.dart';

const loginRoutePath = '/loginPage';
const homeJoueurRoutePath = '/homeJoueurPage';
const homeAdminRoutePath = '/homeAdminPage';

/// Extrait l'id de jeu d'un deep link, sous ses deux formes :
/// - lien https (https://.../j/<id> ou https://.../game/<id>) : "j"/"game"
///   est le premier segment du CHEMIN ;
/// - lien a schema personnalise (customScheme://game/<id>, voir
///   buildGameDeepLink dans share_links.dart et l'intent-filter
///   scheme=customScheme host="game" de AndroidManifest.xml) : "game" est
///   le HOST de l'URI, pas un segment du chemin -- pathSegments ne contient
///   alors que l'id seul. Les deux formes doivent etre traitees separement.
String? extractDeepLinkGameId(Uri uri, {required String customScheme}) {
  if (uri.scheme == customScheme && uri.host == 'game') {
    final segments = uri.pathSegments;
    if (segments.isEmpty) {
      return null;
    }
    final gameId = segments.first.trim();
    return gameId.isEmpty ? null : gameId;
  }

  final segments = uri.pathSegments;
  if (segments.length >= 2 &&
      (segments.first == 'j' || segments.first == 'game')) {
    final gameId = segments[1].trim();
    return gameId.isEmpty ? null : gameId;
  }
  return null;
}

/// Home de repli quand safePop() ne peut pas depiler (aucune route
/// precedente dans la pile) pour un utilisateur connecte. HomeJoueurPage
/// n'a qu'un garde requireAuth (pas de garde de role), donc y renvoyer
/// systematiquement laisserait un commercant ou un admin atterrir sur le
/// mauvais home.
enum SafePopFallbackHome { joueur, commercant, admin }

SafePopFallbackHome resolveSafePopFallbackHome(Roles? role) {
  switch (role) {
    case Roles.commercant:
      return SafePopFallbackHome.commercant;
    case Roles.admin:
      return SafePopFallbackHome.admin;
    case Roles.joueur:
    case null:
      return SafePopFallbackHome.joueur;
  }
}

/// Pre-selects InscriptionPage's "Professionnel" tab when a prospective
/// merchant is routed there directly via `?role=commercant` (e.g. the
/// "Créer un compte" entry point on the login screen), instead
/// of always defaulting new visitors to the "Joueur" tab. Any other value,
/// including an absent param, keeps the existing default (null -> joueur
/// tab), so the player signup entry point is unaffected.
Roles? resolveInitialSignupRole(String? roleQueryParam) =>
    roleQueryParam == 'commercant' ? Roles.commercant : null;

AuthenticatedHomeTarget resolveTargetFromResolvedRole({
  required bool documentExists,
  required Roles? effectiveRole,
  required List<String> playerSignals,
  required AccountStatus? accountStatus,
}) {
  if (!documentExists) {
    return AuthenticatedHomeTarget.routingIssue;
  }
  if (hasMerchantPlayerSignalConflict(
    role: effectiveRole,
    playerSignals: playerSignals,
  )) {
    return AuthenticatedHomeTarget.routingIssue;
  }
  if (effectiveRole == null) {
    return AuthenticatedHomeTarget.routingIssue;
  }
  if (effectiveRole == Roles.admin) {
    return AuthenticatedHomeTarget.adminHome;
  }
  if (effectiveRole == Roles.commercant) {
    if (accountStatus == AccountStatus.rejected) {
      return AuthenticatedHomeTarget.rejected;
    }
    if (accountStatus == AccountStatus.pendingValidation) {
      return AuthenticatedHomeTarget.waitingValidation;
    }
    return AuthenticatedHomeTarget.commercantHome;
  }
  if (accountStatus == AccountStatus.rejected) {
    return AuthenticatedHomeTarget.rejected;
  }
  return AuthenticatedHomeTarget.joueurHome;
}

/// CGV commerçant : un commerçant qui n'a encore accepté aucune version
/// (cgv_accepted_version vide dans users/{uid}) passe d'abord par l'écran
/// CGV, avant son espace, l'attente de validation ou l'écran de refus. Une
/// seule fois : une version déjà acceptée suffit (pas de nouvelle demande à
/// chaque nouvelle version). Sans effet pour les joueurs et l'admin.
AuthenticatedHomeTarget applyMerchantCgvRequirement({
  required AuthenticatedHomeTarget target,
  required Roles? effectiveRole,
  required String? cgvAcceptedVersion,
}) {
  if (effectiveRole != Roles.commercant) {
    return target;
  }
  if ((cgvAcceptedVersion ?? '').trim().isNotEmpty) {
    return target;
  }
  switch (target) {
    case AuthenticatedHomeTarget.commercantHome:
    case AuthenticatedHomeTarget.waitingValidation:
    case AuthenticatedHomeTarget.rejected:
      return AuthenticatedHomeTarget.merchantCgvRequired;
    case AuthenticatedHomeTarget.login:
    case AuthenticatedHomeTarget.joueurHome:
    case AuthenticatedHomeTarget.adminHome:
    case AuthenticatedHomeTarget.pendingInfo:
    case AuthenticatedHomeTarget.merchantCgvRequired:
    case AuthenticatedHomeTarget.routingIssue:
      return target;
  }
}

bool hasMerchantPlayerSignalConflict({
  required Roles? role,
  required List<String> playerSignals,
  List<String> merchantSignals = const <String>[],
}) =>
    role == Roles.commercant &&
    playerSignals.isNotEmpty &&
    merchantSignals.isEmpty;

String? resolveCachedRoleGuardRedirectPathForRole({
  required bool requireAdmin,
  required bool requireMerchant,
  required Roles? role,
  required bool hasMerchantConflict,
}) {
  if (requireAdmin) {
    return role == Roles.admin ? null : loginRoutePath;
  }
  if (!requireMerchant) {
    return null;
  }
  if (hasMerchantConflict) {
    return loginRoutePath;
  }
  if (role == Roles.commercant) {
    return null;
  }
  if (role == Roles.joueur) {
    return homeJoueurRoutePath;
  }
  if (role == Roles.admin) {
    return homeAdminRoutePath;
  }
  return loginRoutePath;
}

String? resolveProtectedRouteGuardRedirectPath({
  required bool hasResolvedAuthState,
  required bool loggedIn,
  required bool requireAuth,
  required bool requireAdmin,
  required bool requireMerchant,
  required bool hasUserDocument,
  required Roles? role,
  required bool hasMerchantConflict,
  required bool isDeepLinkRoute,
  required String currentPath,
}) {
  if (!hasResolvedAuthState) {
    return null;
  }

  const publicPaths = <String>{
    '/',
    '/loginPage',
    '/inscriptionPage',
    '/resetPassword',
    '/legalPage',
    // Player referral link (play.proxiplay.fr/i?ref=CODE): opened signed
    // out, it must reach its page, which then opens the signup.
    '/i',
  };

  if (!loggedIn && !publicPaths.contains(currentPath) && !isDeepLinkRoute) {
    return loginRoutePath;
  }

  if (requireAuth && !loggedIn) {
    return loginRoutePath;
  }

  if ((requireAdmin || requireMerchant) && loggedIn && !hasUserDocument) {
    return null;
  }

  return resolveCachedRoleGuardRedirectPathForRole(
    requireAdmin: requireAdmin,
    requireMerchant: requireMerchant,
    role: role,
    hasMerchantConflict: hasMerchantConflict,
  );
}

enum AuthenticatedHomeTarget {
  login,
  joueurHome,
  commercantHome,
  adminHome,
  pendingInfo,
  waitingValidation,
  rejected,
  merchantCgvRequired,
  routingIssue,
}
