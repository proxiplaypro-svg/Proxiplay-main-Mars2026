import 'package:cloud_functions/cloud_functions.dart';

/// Parrainage commercant (50 EUR en bons cadeaux pour le parrain).
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

  /// Inscription commercant avec un code de parrainage ou partenaire : le
  /// serveur verifie le code, cree le compte et enregistre le rattachement
  /// (aucune recompense a ce stade). [requestId] identique a chaque nouvelle
  /// tentative : une reprise ne cree ni second compte ni second rattachement.
  Future<void> createMerchantAccountWithReferral({
    required String email,
    required String password,
    required String code,
    required String requestId,
  }) async {
    await _functions.httpsCallable('createMerchantAccountWithReferral').call({
      'email': email,
      'password': password,
      'code': code,
      'requestId': requestId,
    });
  }

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
