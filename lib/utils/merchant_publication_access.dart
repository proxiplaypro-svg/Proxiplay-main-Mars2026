import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:webviewx_plus/webviewx_plus.dart';

/// Message affiché quand un commerçant sans droit de publication tente de
/// créer ou publier un jeu (contrôle des abonnements activé côté serveur).
const String kSubscriptionRequiredMessage =
    'Un abonnement ProxiPlay actif est nécessaire pour publier un jeu. '
    'Rendez-vous sur www.proxiplay.fr/espace-commercant/ pour découvrir les offres.';

/// Raison renvoyée par generateInstantWinnersForGame quand la publication
/// est refusée faute d'abonnement (voir merchant_publication_access.js).
const String kSubscriptionRequiredReason = 'subscription_required';

/// Réponse de la Callable getMerchantPublicationAccess : "refusé" uniquement
/// si le contrôle est activé ET l'accès effectivement refusé.
bool isPublicationRefusedResponse(Object? data) {
  if (data is! Map) return false;
  return data['enforced'] == true && data['allowed'] == false;
}

/// Erreur de publication renvoyée par le serveur pour défaut d'abonnement.
bool isSubscriptionRequiredError(Object error) {
  if (error is! FirebaseFunctionsException) return false;
  final details = error.details;
  return error.code == 'failed-precondition' &&
      details is Map &&
      details['reason'] == kSubscriptionRequiredReason;
}

/// Interroge le serveur. Toute erreur (réseau, fonction non déployée...)
/// renvoie false : le comportement actuel est conservé, les règles Firestore
/// et le serveur restant seuls juges du droit de publier.
Future<bool> isMerchantPublicationRefused({FirebaseFunctions? functions}) async {
  try {
    final result = await (functions ?? FirebaseFunctions.instance)
        .httpsCallable('getMerchantPublicationAccess')
        .call(<String, dynamic>{});
    return isPublicationRefusedResponse(result.data);
  } catch (e) {
    debugPrint('getMerchantPublicationAccess indisponible: $e');
    return false;
  }
}

Future<void> showSubscriptionRequiredDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => WebViewAware(
      child: AlertDialog(
        title: const Text('Abonnement requis'),
        content: const Text(kSubscriptionRequiredMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}
