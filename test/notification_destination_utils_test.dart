import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/notification_destination_utils.dart';

// Couvre resolveNotificationAction(), la decision PURE (sans Firestore ni
// navigation) prise a partir des deux champs FCM existants (initialPageName
// decode + parameterData decode). Les deux comportements suivants, eux,
// dependent d'E/S asynchrones (Firestore / FirebaseMessaging.getInitialMessage)
// et vivent dans push_notifications_handler.dart -- ils ne sont PAS
// executables comme tests Dart purs dans ce depot et ne sont donc pas
// couverts ici (prepares pour une verification manuelle/Codex) :
//   - cold-start : la destination en attente est bien recuperee une fois le
//     router pret (getInitialMessage + _handledMessageIds) ;
//   - fallback Home : _documentStillExists() redirige bien vers HomeJoueurPage
//     quand le jeu/commerce vise a disparu entre l'envoi et le clic.
void main() {
  group('resolveNotificationAction - none / legacy', () {
    test('1. aucune destination (initialPageName vide) -> none', () {
      final action = resolveNotificationAction('', const {});
      expect(action.kind, NotificationDestinationKind.none);
    });

    test('2. initialPageName null (notification legacy sans ce champ) -> none', () {
      final action = resolveNotificationAction(null, const {});
      expect(action.kind, NotificationDestinationKind.none);
    });

    test('3. page inconnue (whitelist non synchronisee) -> none, jamais de navigation', () {
      final action = resolveNotificationAction('UnePageQuiNexistePas', const {});
      expect(action.kind, NotificationDestinationKind.none);
    });
  });

  group('resolveNotificationAction - internal (dont Accueil)', () {
    test('4. HomeJoueurPage -> navigate sans parametres', () {
      final action = resolveNotificationAction('HomeJoueurPage', const {});
      expect(action.kind, NotificationDestinationKind.navigate);
      expect(action.pageName, 'HomeJoueurPage');
      expect(action.parameterData, isEmpty);
    });

    test('5. chaque ecran interne whitelisted navigue correctement', () {
      for (final pageName in kNoParamInternalPages) {
        final action = resolveNotificationAction(pageName, const {});
        expect(action.kind, NotificationDestinationKind.navigate, reason: pageName);
        expect(action.pageName, pageName);
      }
    });
  });

  group('resolveNotificationAction - game', () {
    test('6. JeuDetailJoueurPage avec gameDoc -> navigate avec les parametres', () {
      final data = {'gameDoc': 'games/abc123', 'enseigneDoc': 'enseignes/def456'};
      final action = resolveNotificationAction('JeuDetailJoueurPage', data);
      expect(action.kind, NotificationDestinationKind.navigate);
      expect(action.pageName, 'JeuDetailJoueurPage');
      expect(action.parameterData, data);
    });

    test('7. JeuDetailJoueurPage sans gameDoc (ID manquant) -> none', () {
      final action = resolveNotificationAction('JeuDetailJoueurPage', const {});
      expect(action.kind, NotificationDestinationKind.none);
    });

    test('8. JeuDetailJoueurPage avec gameDoc vide -> none', () {
      final action = resolveNotificationAction('JeuDetailJoueurPage', const {'gameDoc': '   '});
      expect(action.kind, NotificationDestinationKind.none);
    });
  });

  group('resolveNotificationAction - merchant', () {
    test('9. EnseigneDetailJoueurPage avec enseigneDoc -> navigate', () {
      final data = {'enseigneDoc': 'enseignes/def456'};
      final action = resolveNotificationAction('EnseigneDetailJoueurPage', data);
      expect(action.kind, NotificationDestinationKind.navigate);
      expect(action.pageName, 'EnseigneDetailJoueurPage');
      expect(action.parameterData, data);
    });

    test('10. EnseigneDetailJoueurPage sans enseigneDoc (ID manquant) -> none', () {
      final action = resolveNotificationAction('EnseigneDetailJoueurPage', const {});
      expect(action.kind, NotificationDestinationKind.none);
    });
  });

  group('resolveNotificationAction - external_url', () {
    test('11. URL https valide -> launchUrl', () {
      final action = resolveNotificationAction(
        kExternalUrlRedirectPageName,
        const {'url': 'https://proxiplay.fr/offres'},
      );
      expect(action.kind, NotificationDestinationKind.launchUrl);
      expect(action.url, 'https://proxiplay.fr/offres');
    });

    test('12. URL http (non https) -> none (destination invalide)', () {
      final action = resolveNotificationAction(
        kExternalUrlRedirectPageName,
        const {'url': 'http://proxiplay.fr'},
      );
      expect(action.kind, NotificationDestinationKind.none);
    });

    test('13. schema javascript: -> none, jamais execute', () {
      final action = resolveNotificationAction(
        kExternalUrlRedirectPageName,
        const {'url': 'javascript:alert(1)'},
      );
      expect(action.kind, NotificationDestinationKind.none);
    });

    test('14. url manquante (ID manquant) -> none', () {
      final action = resolveNotificationAction(kExternalUrlRedirectPageName, const {});
      expect(action.kind, NotificationDestinationKind.none);
    });
  });

  group('isHttpsUrl', () {
    test('15. valide uniquement https:// avec un host', () {
      expect(isHttpsUrl('https://proxiplay.fr'), isTrue);
      expect(isHttpsUrl('http://proxiplay.fr'), isFalse);
      expect(isHttpsUrl('javascript:alert(1)'), isFalse);
      expect(isHttpsUrl(''), isFalse);
      expect(isHttpsUrl(null), isFalse);
      expect(isHttpsUrl('https://'), isFalse);
    });
  });
}
