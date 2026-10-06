// Parrainage commercant (recompense de 100 EUR) : liens de partage et
// libelles de statut affiches au joueur. Fonctions pures, testables sans
// Firebase -- voir test/merchant_referral_utils_test.dart.

/// Parcours commercant de Proxiplay.fr (audite avant d'etre reference ici :
/// voir commercant/compte/index.html). Jamais un lien d'installation d'app
/// (onelink) -- ce programme amene un COMMERCANT vers le site, pas un
/// joueur vers l'app.
const String merchantReferralSignupUrl =
    'https://www.proxiplay.fr/commercant/compte/';

/// Explication factuelle du fonctionnement du programme (pas un reglement
/// juridique definitif -- voir rapport final, ACTION REQUISE pour Pascal).
const String merchantReferralConditionsUrl =
    'https://www.proxiplay.fr/parrainage-commercant/conditions/';

String buildMerchantReferralLink(String code) {
  final normalized = code.trim();
  if (normalized.isEmpty) {
    return merchantReferralSignupUrl;
  }
  final uri = Uri.parse(merchantReferralSignupUrl);
  return uri.replace(queryParameters: {'ref': normalized}).toString();
}

String buildMerchantReferralShareText(String code) {
  final normalized = code.trim();
  final link = buildMerchantReferralLink(normalized);
  if (normalized.isEmpty) {
    return 'Je vous recommande ProxiPlay pour faire connaître votre commerce '
        'auprès des joueurs du Dunkerquois.\n\n'
        'Découvrez l\'offre commerçant sur Proxiplay.fr :\n$link';
  }
  return 'Je vous recommande ProxiPlay pour faire connaître votre commerce '
      'auprès des joueurs du Dunkerquois.\n\n'
      'Découvrez l\'offre commerçant sur Proxiplay.fr et utilisez mon code '
      '$normalized lors de votre inscription :\n$link';
}

/// Traduit un statut technique backend (merchant_referrals.status) en un
/// libelle comprehensible pour un joueur. Ne jamais afficher les noms
/// techniques ('pending', 'eligible'...) directement dans l'UI -- voir
/// section 6 du chantier parrainage commercant.
String merchantReferralStatusLabel(String? status) {
  switch (status) {
    case 'eligible':
      return 'À valider';
    case 'approved':
      return 'Validé';
    case 'paid':
      return 'Payé';
    case 'rejected':
    case 'cancelled':
      return 'Refusé';
    case 'linked':
    default:
      return 'En attente';
  }
}

String merchantReferralStatusDescription(String? status) {
  switch (status) {
    case 'eligible':
      return 'Le paiement qualifiant a été détecté et le dossier est en cours de validation.';
    case 'approved':
      return 'La récompense a été approuvée.';
    case 'paid':
      return 'Les 100 € ont été versés.';
    case 'rejected':
    case 'cancelled':
      return 'Ce parrainage ne remplit pas les conditions du programme.';
    case 'linked':
    default:
      return 'Le commerçant n\'est pas encore devenu client éligible.';
  }
}
