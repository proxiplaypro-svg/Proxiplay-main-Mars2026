// Parrainage commercant (recompense de 50 EUR) : liens de partage et
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
  if (normalized.isEmpty) {
    return 'Je vous recommande ProxiPlay pour faire connaître votre commerce.';
  }
  return 'Je vous recommande ProxiPlay pour faire connaître votre commerce '
      'auprès des joueurs du Dunkerquois.\n\n'
      'Utilisez mon code de parrainage $normalized en créant votre compte '
      'commerçant ProxiPlay.';
}

/// Code saisi a l'inscription commercant : espaces retires, majuscules. Le
/// serveur seul decide s'il s'agit d'un code ambassadeur, d'un futur code
/// partenaire ou d'un code inconnu (jamais un code de parrainage joueur).
String normalizeMerchantSignupCode(String? value) =>
    (value ?? '').replaceAll(RegExp(r'\s+'), '').toUpperCase();

/// Message apres un refus a l'inscription commercant avec code. Dans tous ces
/// cas le compte n'est pas cree ; le code reste saisi pour corriger.
String merchantSignupCodeErrorMessage(String code, Object? details) {
  final data = details is Map ? details : const {};
  switch (data['reason']) {
    case 'partner_code_unavailable':
      return 'Les codes partenaires ne sont pas encore disponibles. '
          'Inscrivez-vous sans code ou contactez ProxiPlay.';
    case 'program_unavailable':
      return 'Le parrainage commerçant est momentanément indisponible. '
          'Inscrivez-vous sans code.';
    case 'code_unavailable':
      return 'Ce code de parrainage n’est plus valable. '
          'Vérifiez-le ou inscrivez-vous sans code.';
    case 'email_exists':
      return 'Cette adresse e-mail possède déjà un compte. '
          'Connectez-vous avec vos identifiants.';
  }
  if (code == 'not-found') {
    return 'Ce code est inconnu. Vérifiez-le ou inscrivez-vous sans code.';
  }
  if (code == 'resource-exhausted') {
    return 'Trop de tentatives. Patientez une minute avant de réessayer.';
  }
  return 'Connexion interrompue. Réessayez avec la même adresse et le même '
      'code : votre parrainage ne sera pas perdu.';
}

bool isValidMerchantReferralCode(String? code) =>
    code != null && RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(code);

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
      return 'Remise enregistrée';
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
      return 'Le bon cadeau a été approuvé.';
    case 'paid':
      return 'La remise du bon cadeau a été enregistrée.';
    case 'rejected':
    case 'cancelled':
      return 'Ce parrainage ne remplit pas les conditions du programme.';
    case 'linked':
    default:
      return 'Le commerçant n\'est pas encore devenu client éligible.';
  }
}
