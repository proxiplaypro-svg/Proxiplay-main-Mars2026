import 'package:cloud_functions/cloud_functions.dart';

import '/models/share_promo_models.dart';

class SharePromoService {
  SharePromoService({
    FirebaseFunctions? functions,
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> _call(
    String name, [
    Map<String, dynamic> data = const {},
  ]) async {
    final response = await _functions.httpsCallable(name).call(data);
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return <String, dynamic>{};
  }

  Future<SharePromoStateViewModel> getSharePromoState() async {
    final data = await _call('getSharePromoState');
    return SharePromoStateViewModel.fromMap(data);
  }

  Future<Map<String, dynamic>> createReferral({
    required String shareChannel,
    String? inviteeContact,
    String? createdFromDeviceId,
    Map<String, dynamic>? metadata,
  }) {
    return _call('createReferral', {
      'shareChannel': shareChannel,
      'inviteeContact': inviteeContact,
      'createdFromDeviceId': createdFromDeviceId,
      'metadata': metadata ?? <String, dynamic>{},
    });
  }

  Future<Map<String, dynamic>> validateReferralCode({
    required String inviteCode,
  }) {
    return _call('validateReferralCode', {
      'inviteCode': inviteCode,
    });
  }

  Future<Map<String, dynamic>> registerReferralAcceptance({
    required String inviteCode,
    String? acceptedFromDeviceId,
  }) {
    return _call('registerReferralAcceptance', {
      'inviteCode': inviteCode,
      'acceptedFromDeviceId': acceptedFromDeviceId,
    });
  }

  Future<void> adminUpsertSharePromo(SharePromoCampaignModel campaign) async {
    await _call('adminUpsertSharePromo', campaign.toCallableMap());
  }

  Future<SharePromoAdminStatsModel> adminGetSharePromoStats() async {
    final data = await _call('adminGetSharePromoStats');
    return SharePromoAdminStatsModel.fromMap(data);
  }

  Future<SharePromoCampaignModel> loadCurrentCampaign() async {
    final data = await _call('adminGetSharePromoConfig');
    return SharePromoCampaignModel.fromMap(data);
  }
}
