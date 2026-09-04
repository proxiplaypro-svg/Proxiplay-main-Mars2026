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
    if (accountStatus == AccountStatus.pendingInfo) {
      return AuthenticatedHomeTarget.pendingInfo;
    }
    if (accountStatus == AccountStatus.rejected) {
      return AuthenticatedHomeTarget.rejected;
    }
    if (accountStatus == AccountStatus.pendingValidation) {
      return AuthenticatedHomeTarget.waitingValidation;
    }
    return AuthenticatedHomeTarget.commercantHome;
  }
  if (accountStatus == AccountStatus.pendingInfo) {
    return AuthenticatedHomeTarget.pendingInfo;
  }
  if (accountStatus == AccountStatus.rejected) {
    return AuthenticatedHomeTarget.rejected;
  }
  return AuthenticatedHomeTarget.joueurHome;
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
  routingIssue,
}
