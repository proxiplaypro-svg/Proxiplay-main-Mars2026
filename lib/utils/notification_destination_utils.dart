// Resolution pure (sans Firestore ni navigation) de la destination d'une
// notification push, a partir des deux champs deja transportes par le
// pipeline FCM existant : initialPageName + parameterData (decode).
//
// Doit rester synchronise avec :
// - firebase/functions/notification_destination.js (cote serveur, source de
//   verite pour ce qui est autorise a etre envoye) ;
// - parametersBuilderMap dans push_notifications_handler.dart (cote client,
//   qui resout effectivement les documents Firestore et navigue).

/// Nom de page sentinelle pour une destination "URL externe" -- ce n'est pas
/// une route go_router reelle, seulement un marqueur intercepte avant toute
/// navigation (voir push_notifications_handler.dart).
const String kExternalUrlRedirectPageName = 'ExternalUrlRedirectPage';

/// Ecrans internes ne necessitant aucun parametre pour s'ouvrir. Doit rester
/// synchronise avec kInternalDestinations cote serveur.
const Set<String> kNoParamInternalPages = {
  'HomeJoueurPage',
  'FavorisJoueurPage',
  'ProfilJoueurPage',
  'LotsJoueurPage',
  'ParrainageJoueurPage',
  'ParrainageCommercantPage',
};

enum NotificationDestinationKind { none, navigate, launchUrl }

class NotificationDestinationAction {
  const NotificationDestinationAction._({
    required this.kind,
    this.pageName,
    this.parameterData = const {},
    this.url,
  });

  const NotificationDestinationAction.none()
      : this._(kind: NotificationDestinationKind.none);

  const NotificationDestinationAction.navigate(
    String pageName, {
    Map<String, dynamic> parameterData = const {},
  }) : this._(
          kind: NotificationDestinationKind.navigate,
          pageName: pageName,
          parameterData: parameterData,
        );

  const NotificationDestinationAction.launchUrl(String url)
      : this._(kind: NotificationDestinationKind.launchUrl, url: url);

  final NotificationDestinationKind kind;
  final String? pageName;
  final Map<String, dynamic> parameterData;
  final String? url;
}

bool isHttpsUrl(String? value) {
  if (value == null || value.trim().isEmpty) {
    return false;
  }
  final uri = Uri.tryParse(value.trim());
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

/// Decide quoi faire a partir des deux champs bruts d'une notification,
/// sans acceder a Firestore : "naviguer vers une page" (avec les parametres
/// deja fournis), "ouvrir une URL", ou "ne rien faire" (none/legacy/invalide).
///
/// Ne verifie PAS que gameDoc/enseigneDoc pointent vers un document qui
/// existe encore : cette verification est asynchrone et reste a la charge
/// de l'appelant (voir push_notifications_handler.dart), qui retombe alors
/// sur HomeJoueurPage plutot que de naviguer vers une fiche introuvable.
NotificationDestinationAction resolveNotificationAction(
  String? initialPageName,
  Map<String, dynamic> parameterData,
) {
  final pageName = initialPageName?.trim() ?? '';
  if (pageName.isEmpty) {
    // Notification legacy (sans destination) ou destination_type: none.
    return const NotificationDestinationAction.none();
  }

  if (pageName == kExternalUrlRedirectPageName) {
    final url = parameterData['url'] as String?;
    if (!isHttpsUrl(url)) {
      return const NotificationDestinationAction.none();
    }
    return NotificationDestinationAction.launchUrl(url!.trim());
  }

  if (kNoParamInternalPages.contains(pageName)) {
    return NotificationDestinationAction.navigate(pageName);
  }

  if (pageName == 'JeuDetailJoueurPage') {
    final gameDoc = parameterData['gameDoc'] as String?;
    if (gameDoc == null || gameDoc.trim().isEmpty) {
      return const NotificationDestinationAction.none();
    }
    return NotificationDestinationAction.navigate(
      pageName,
      parameterData: parameterData,
    );
  }

  if (pageName == 'EnseigneDetailJoueurPage') {
    final enseigneDoc = parameterData['enseigneDoc'] as String?;
    if (enseigneDoc == null || enseigneDoc.trim().isEmpty) {
      return const NotificationDestinationAction.none();
    }
    return NotificationDestinationAction.navigate(
      pageName,
      parameterData: parameterData,
    );
  }

  // Page inconnue : whitelist non synchronisee ou notification malformee.
  // On ne tente jamais de naviguer vers une route non reconnue.
  return const NotificationDestinationAction.none();
}
