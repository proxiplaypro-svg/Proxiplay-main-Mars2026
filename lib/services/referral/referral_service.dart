import 'dart:math';

import '/models/share_promo_models.dart';
import '/services/share_promo_service.dart';
import '/utils/share_links.dart' as share_links;

class ReferralService {
  ReferralService({
    SharePromoService? sharePromoService,
  }) : _sharePromoService = sharePromoService ?? SharePromoService();

  final SharePromoService _sharePromoService;

  static final Random _random = Random();

  Future<SharePromoStateViewModel> getSharePromoState() {
    return _sharePromoService.getSharePromoState();
  }

  Future<Map<String, dynamic>> createReferral({
    required String shareChannel,
    String? inviteeContact,
    String? createdFromDeviceId,
    Map<String, dynamic>? metadata,
  }) {
    return _sharePromoService.createReferral(
      shareChannel: shareChannel,
      inviteeContact: inviteeContact,
      createdFromDeviceId: createdFromDeviceId,
      metadata: metadata,
    );
  }

  Future<Map<String, dynamic>> validateReferralCode({
    required String inviteCode,
  }) {
    return _sharePromoService.validateReferralCode(
      inviteCode: inviteCode,
    );
  }

  Future<Map<String, dynamic>> registerReferralAcceptance({
    required String inviteCode,
    String? acceptedFromDeviceId,
  }) {
    return _sharePromoService.registerReferralAcceptance(
      inviteCode: inviteCode,
      acceptedFromDeviceId: acceptedFromDeviceId,
    );
  }

  Future<void> adminUpsertSharePromo(SharePromoCampaignModel campaign) {
    return _sharePromoService.adminUpsertSharePromo(campaign);
  }

  Future<SharePromoAdminStatsModel> adminGetSharePromoStats() {
    return _sharePromoService.adminGetSharePromoStats();
  }

  Future<SharePromoCampaignModel> loadCurrentCampaign() {
    return _sharePromoService.loadCurrentCampaign();
  }

  String buildReferralShareLink([String? referralCode]) {
    return share_links.buildReferralShareLink(referralCode);
  }

  String buildAppShareText({
    String? title,
    String? description,
    String? referralCode,
  }) {
    return share_links.buildAppShareText(
      title: title,
      description: description,
      referralCode: referralCode,
    );
  }

  String? extractReferralCodeFromUri(Uri? uri) {
    return share_links.extractReferralCodeFromUri(uri);
  }

  String resolveShareLink(Map<String, dynamic> response) {
    final inviteCode = (response['inviteCode'] as String?)?.trim();
    final responseShareLink = (response['shareLink'] as String?)?.trim();
    final responseReferralCode =
        extractReferralCodeFromUri(Uri.tryParse(responseShareLink ?? ''));
    return buildReferralShareLink(inviteCode ?? responseReferralCode);
  }

  String buildRandomShareMessage({
    required String shareLink,
    required int rewardValue,
    String? referralCode,
  }) {
    final normalizedReferralCode = referralCode?.trim();
    final referralCodeText =
        normalizedReferralCode == null || normalizedReferralCode.isEmpty
            ? ''
            : "\n\nCode de parrainage : $normalizedReferralCode\n"
                "Si le code ne se remplit pas automatiquement après l'installation, "
                "saisis-le manuellement lors de l'inscription.";
    final templates = <String>[
      "J'utilise ProxiPlay et je t'invite à découvrir l'app.\n"
          "Télécharge-la ici :\n"
          "$shareLink"
          "$referralCodeText\n\n"
          "Si tu t'inscris avec mon lien, je débloque l'accès à tous les jeux jusqu'à minuit.",
      "J'ai une invitation ProxiPlay pour toi.\n"
          "Télécharge l'application ici :\n"
          "$shareLink"
          "$referralCodeText\n\n"
          "Ton inscription avec mon lien me permet de jouer à tous les jeux jusqu'à minuit.",
      "Envie de tester ProxiPlay ?\n"
          "Voici mon lien d'invitation :\n"
          "$shareLink"
          "$referralCodeText\n\n"
          "Si tu rejoins l'app avec mon lien, je récupère l'accès à tous les jeux jusqu'à minuit.",
      "Rejoins-moi sur ProxiPlay.\n"
          "Tu peux télécharger l'app ici :\n"
          "$shareLink"
          "$referralCodeText\n\n"
          "En t'inscrivant avec mon lien, tu m'aides à débloquer l'accès à tous les jeux jusqu'à minuit.",
      "Je te partage mon invitation ProxiPlay.\n"
          "Télécharge l'app ici :\n"
          "$shareLink"
          "$referralCodeText\n\n"
          "Si tu t'inscris avec mon lien, je profite de l'accès à tous les jeux jusqu'à minuit.",
      "Découvre ProxiPlay avec mon lien.\n"
          "Télécharge l'application ici :\n"
          "$shareLink"
          "$referralCodeText\n\n"
          "Ton inscription avec mon lien me débloque l'accès à tous les jeux jusqu'à minuit.",
    ];
    return templates[_random.nextInt(templates.length)];
  }

  Future<Map<String, String>> buildSharePromoPayload({
    required String channel,
    required int rewardValue,
  }) async {
    final response = await createReferral(
      shareChannel: channel,
    );
    final shareLink = resolveShareLink(response);
    final referralCode = extractReferralCodeFromUri(Uri.tryParse(shareLink));
    return {
      'shareLink': shareLink,
      'shareText': buildRandomShareMessage(
        shareLink: shareLink,
        rewardValue: rewardValue,
        referralCode: referralCode,
      ),
    };
  }
}
