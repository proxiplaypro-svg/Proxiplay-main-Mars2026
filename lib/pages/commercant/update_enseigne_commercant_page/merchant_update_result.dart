import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

/// Maximum wait for Firestore to confirm the update. Without network the
/// write would otherwise wait indefinitely on "Enregistrement...".
const Duration kMerchantUpdateTimeout = Duration(seconds: 20);

const String kMerchantUpdateGenericError =
    'Impossible de mettre à jour vos informations. Réessayez.';

/// Explicit message after a failed update; the page stays open.
String merchantUpdateErrorMessage(Object error) {
  if (error is TimeoutException) {
    return 'Connexion trop lente : vos modifications ne sont pas confirmées. '
        'Vérifiez votre connexion et réessayez.';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Vous n’avez pas l’autorisation de modifier cet établissement.';
      case 'not-found':
        return 'Cet établissement est introuvable. Il a peut-être été supprimé.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Connexion impossible : vos modifications ne sont pas '
            'enregistrées. Vérifiez votre connexion et réessayez.';
    }
  }
  return kMerchantUpdateGenericError;
}
