import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/auth/firebase_auth/account_routing_logic.dart';
import 'package:proxi_play/backend/schema/enums/enums.dart';

void main() {
  group('resolveTargetFromResolvedRole', () {
    test('routes new email player to player home', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.joueur,
        playerSignals: const ['remaining_part'],
        accountStatus: null,
        requiresProfileCompletion: false,
      );

      expect(target, AuthenticatedHomeTarget.joueurHome);
    });

    test('routes new Google player to player home', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.joueur,
        playerSignals: const ['remaining_part'],
        accountStatus: AccountStatus.pendingInfo,
        requiresProfileCompletion: false,
      );

      expect(target, AuthenticatedHomeTarget.pendingInfo);
    });

    test('routes new Apple player to player home once profile is complete', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.joueur,
        playerSignals: const ['remaining_part'],
        accountStatus: null,
        requiresProfileCompletion: false,
      );

      expect(target, AuthenticatedHomeTarget.joueurHome);
    });

    test('routes merchant to merchant home', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.commercant,
        playerSignals: const [],
        accountStatus: null,
        requiresProfileCompletion: false,
      );

      expect(target, AuthenticatedHomeTarget.commercantHome);
    });

    test('routes admin to admin home', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.admin,
        playerSignals: const [],
        accountStatus: null,
        requiresProfileCompletion: false,
      );

      expect(target, AuthenticatedHomeTarget.adminHome);
    });

    test('missing role stays in controlled routing issue', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: null,
        playerSignals: const ['remaining_part'],
        accountStatus: null,
        requiresProfileCompletion: false,
      );

      expect(target, AuthenticatedHomeTarget.routingIssue);
    });

    test('invalid role stays in controlled routing issue', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: null,
        playerSignals: const [],
        accountStatus: null,
        requiresProfileCompletion: false,
      );

      expect(target, AuthenticatedHomeTarget.routingIssue);
    });

    test('merchant role with player signals is blocked', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.commercant,
        playerSignals: const ['remaining_part'],
        accountStatus: null,
        requiresProfileCompletion: false,
      );

      expect(target, AuthenticatedHomeTarget.routingIssue);
    });

    test('missing document is blocked', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: false,
        effectiveRole: Roles.joueur,
        playerSignals: const ['remaining_part'],
        accountStatus: null,
        requiresProfileCompletion: false,
      );

      expect(target, AuthenticatedHomeTarget.routingIssue);
    });

    test('merchant pending validation goes to waiting validation', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.commercant,
        playerSignals: const [],
        accountStatus: AccountStatus.pendingValidation,
        requiresProfileCompletion: false,
      );

      expect(target, AuthenticatedHomeTarget.waitingValidation);
    });

    test('new player requiring profile completion goes to pending info', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.joueur,
        playerSignals: const ['remaining_part'],
        accountStatus: null,
        requiresProfileCompletion: true,
      );

      expect(target, AuthenticatedHomeTarget.pendingInfo);
    });

    test('new merchant requiring profile completion goes to pending info', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.commercant,
        playerSignals: const [],
        accountStatus: AccountStatus.pendingValidation,
        requiresProfileCompletion: true,
      );

      expect(target, AuthenticatedHomeTarget.pendingInfo);
    });
  });

  group('resolveCachedRoleGuardRedirectPathForRole', () {
    test('player cannot open merchant route', () {
      final redirect = resolveCachedRoleGuardRedirectPathForRole(
        requireAdmin: false,
        requireMerchant: true,
        role: Roles.joueur,
        hasMerchantConflict: false,
      );

      expect(redirect, '/homeJoueurPage');
    });

    test('admin cannot open merchant route', () {
      final redirect = resolveCachedRoleGuardRedirectPathForRole(
        requireAdmin: false,
        requireMerchant: true,
        role: Roles.admin,
        hasMerchantConflict: false,
      );

      expect(redirect, '/homeAdminPage');
    });

    test('merchant with player conflict cannot open merchant route', () {
      final redirect = resolveCachedRoleGuardRedirectPathForRole(
        requireAdmin: false,
        requireMerchant: true,
        role: Roles.commercant,
        hasMerchantConflict: true,
      );

      expect(redirect, '/loginPage');
    });

    test('merchant can open merchant route when role is explicit and clean', () {
      final redirect = resolveCachedRoleGuardRedirectPathForRole(
        requireAdmin: false,
        requireMerchant: true,
        role: Roles.commercant,
        hasMerchantConflict: false,
      );

      expect(redirect, isNull);
    });

    test('non admin cannot open admin route', () {
      final redirect = resolveCachedRoleGuardRedirectPathForRole(
        requireAdmin: true,
        requireMerchant: false,
        role: Roles.commercant,
        hasMerchantConflict: false,
      );

      expect(redirect, '/loginPage');
    });
  });

  group('resolveProtectedRouteGuardRedirectPath', () {
    test('unauthenticated user is redirected to login on protected route', () {
      final redirect = resolveProtectedRouteGuardRedirectPath(
        hasResolvedAuthState: true,
        loggedIn: false,
        requireAuth: true,
        requireAdmin: false,
        requireMerchant: false,
        hasUserDocument: false,
        role: null,
        hasMerchantConflict: false,
        isDeepLinkRoute: false,
        currentPath: '/homeJoueurPage',
      );

      expect(redirect, '/loginPage');
    });

    test('logged in user with null document keeps waiting on protected business route', () {
      final redirect = resolveProtectedRouteGuardRedirectPath(
        hasResolvedAuthState: true,
        loggedIn: true,
        requireAuth: true,
        requireAdmin: false,
        requireMerchant: true,
        hasUserDocument: false,
        role: null,
        hasMerchantConflict: false,
        isDeepLinkRoute: false,
        currentPath: '/homeCommercantPage',
      );

      expect(redirect, isNull);
    });
  });

  group('hasMerchantPlayerSignalConflict', () {
    test('detects conflict only for merchant role', () {
      expect(
        hasMerchantPlayerSignalConflict(
          role: Roles.commercant,
          playerSignals: const ['remaining_part'],
        ),
        isTrue,
      );
      expect(
        hasMerchantPlayerSignalConflict(
          role: Roles.joueur,
          playerSignals: const ['remaining_part'],
        ),
        isFalse,
      );
    });
  });
}
