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
      );

      expect(target, AuthenticatedHomeTarget.joueurHome);
    });

    test('routes new Apple player to player home once profile is complete', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.joueur,
        playerSignals: const ['remaining_part'],
        accountStatus: null,
      );

      expect(target, AuthenticatedHomeTarget.joueurHome);
    });

    test('routes merchant to merchant home', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.commercant,
        playerSignals: const [],
        accountStatus: null,
      );

      expect(target, AuthenticatedHomeTarget.commercantHome);
    });

    test('routes admin to admin home', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.admin,
        playerSignals: const [],
        accountStatus: null,
      );

      expect(target, AuthenticatedHomeTarget.adminHome);
    });

    test('missing role stays in controlled routing issue', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: null,
        playerSignals: const ['remaining_part'],
        accountStatus: null,
      );

      expect(target, AuthenticatedHomeTarget.routingIssue);
    });

    test('invalid role stays in controlled routing issue', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: null,
        playerSignals: const [],
        accountStatus: null,
      );

      expect(target, AuthenticatedHomeTarget.routingIssue);
    });

    test('merchant role with player signals is blocked', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.commercant,
        playerSignals: const ['remaining_part'],
        accountStatus: null,
      );

      expect(target, AuthenticatedHomeTarget.routingIssue);
    });

    test('missing document is blocked', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: false,
        effectiveRole: Roles.joueur,
        playerSignals: const ['remaining_part'],
        accountStatus: null,
      );

      expect(target, AuthenticatedHomeTarget.routingIssue);
    });

    test('merchant pending validation goes to waiting validation', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.commercant,
        playerSignals: const [],
        accountStatus: AccountStatus.pendingValidation,
      );

      expect(target, AuthenticatedHomeTarget.waitingValidation);
    });

    test('incomplete player profile metadata still routes to player home', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.joueur,
        playerSignals: const ['remaining_part'],
        accountStatus: null,
      );

      expect(target, AuthenticatedHomeTarget.joueurHome);
    });

    test('approved merchant with incomplete profile still routes normally', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.commercant,
        playerSignals: const [],
        accountStatus: AccountStatus.approved,
      );

      expect(target, AuthenticatedHomeTarget.commercantHome);
    });

    test('incomplete admin profile still routes normally', () {
      final target = resolveTargetFromResolvedRole(
        documentExists: true,
        effectiveRole: Roles.admin,
        playerSignals: const [],
        accountStatus: null,
      );

      expect(target, AuthenticatedHomeTarget.adminHome);
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

    test('merchant can open merchant route when role is explicit and clean',
        () {
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

    test(
        'logged in user with null document keeps waiting on protected business route',
        () {
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

  group('extractDeepLinkGameId', () {
    test('reads the id from a custom-scheme deep link (game is the host)', () {
      final gameId = extractDeepLinkGameId(
        Uri.parse('proxiplay://game/ABC123'),
        customScheme: 'proxiplay',
      );

      expect(gameId, 'ABC123');
    });

    test('reads the id from a /j/<id> https link (j is the first path segment)', () {
      final gameId = extractDeepLinkGameId(
        Uri.parse('https://play.proxiplay.fr/j/ABC123'),
        customScheme: 'proxiplay',
      );

      expect(gameId, 'ABC123');
    });

    test('reads the id from a /game/<id> https link', () {
      final gameId = extractDeepLinkGameId(
        Uri.parse('https://play.proxiplay.fr/game/ABC123'),
        customScheme: 'proxiplay',
      );

      expect(gameId, 'ABC123');
    });

    test('returns null for a custom-scheme link with no id', () {
      final gameId = extractDeepLinkGameId(
        Uri.parse('proxiplay://game/'),
        customScheme: 'proxiplay',
      );

      expect(gameId, isNull);
    });

    test('returns null for an unrelated https link', () {
      final gameId = extractDeepLinkGameId(
        Uri.parse('https://play.proxiplay.fr/about'),
        customScheme: 'proxiplay',
      );

      expect(gameId, isNull);
    });

    test('returns null for a custom-scheme link with the wrong host', () {
      final gameId = extractDeepLinkGameId(
        Uri.parse('proxiplay://notgame/ABC123'),
        customScheme: 'proxiplay',
      );

      expect(gameId, isNull);
    });
  });

  group('resolveSafePopFallbackHome', () {
    test('sends a merchant to the merchant home', () {
      expect(
        resolveSafePopFallbackHome(Roles.commercant),
        SafePopFallbackHome.commercant,
      );
    });

    test('sends an admin to the admin home', () {
      expect(
        resolveSafePopFallbackHome(Roles.admin),
        SafePopFallbackHome.admin,
      );
    });

    test('sends a player to the player home', () {
      expect(
        resolveSafePopFallbackHome(Roles.joueur),
        SafePopFallbackHome.joueur,
      );
    });

    test('defaults to the player home when the role is unknown', () {
      expect(
        resolveSafePopFallbackHome(null),
        SafePopFallbackHome.joueur,
      );
    });
  });
}
