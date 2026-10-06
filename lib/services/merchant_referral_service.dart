import 'package:cloud_functions/cloud_functions.dart';

/// Parrainage commercant (recompense de 100 EUR), chantier paiement Stripe.
/// Programme distinct du parrainage joueur existant (voir
/// share_promo_service.dart) : code et recompense geres par un espace
/// Firestore separe (merchant_referral_codes / merchant_referrals), jamais
/// melanges au bonus de jeu. Les Cloud Functions appelees ici vivent dans
/// le backend canonique, region us-central1 (pas europe-west1).
class MerchantReferralService {
  MerchantReferralService({
    FirebaseFunctions? functions,
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  /// Recupere le code de parrainage commercant du joueur courant, en le
  /// creant cote serveur s'il n'existe pas encore. Idempotent : un meme
  /// joueur recoit toujours le meme code (jamais genere uniquement cote
  /// telephone).
  Future<String?> generateMerchantReferralCode() async {
    final response =
        await _functions.httpsCallable('generateMerchantReferralCode').call();
    final data = response.data;
    if (data is Map) {
      return (data['code'] as String?)?.trim();
    }
    return null;
  }
}
