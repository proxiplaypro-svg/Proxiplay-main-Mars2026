import '/backend/schema/enums/enums.dart';

const loginRoutePath = '/loginPage';
const homeJoueurRoutePath = '/homeJoueurPage';
const homeAdminRoutePath = '/homeAdminPage';

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
    if (accountStatus == AccountStatus.pendingValidation ||
        accountStatus == AccountStatus.pendingIdentityCard ||
        accountStatus == AccountStatus.pendingIdentityPhoto) {
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
