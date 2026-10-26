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

  /// Records the referral bonus congratulation as presented, for every
  /// device of the account (idempotent on the server).
  Future<void> acknowledgeReferralBonusNotice(String referralId) async {
    await _call('acknowledgeReferralBonusNotice', {'referralId': referralId});
  }

  /// Same, for a referral game ticket confirmation.
  Future<void> acknowledgeReferralTicketNotice(String referralId) async {
    await _call('acknowledgeReferralBonusNotice',
        {'referralId': referralId, 'kind': 'ticket'});
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

  Future<void> createReferralEmailAccount({
    required String email,
    required String password,
    required String inviteCode,
    required String requestId,
  }) async {
    await _call('createReferralEmailAccount', {
      'email': email,
      'password': password,
      'inviteCode': inviteCode,
      'requestId': requestId,
    });
  }

  /// Google signup with a referral code, called with the Google ID token
  /// before the Firebase sign-in. Returns the server status: accepted,
  /// existing_account or refused.
  Future<String> createReferralGoogleAccount({
    required String idToken,
    required String inviteCode,
  }) async {
    final data = await _call('createReferralGoogleAccount', {
      'idToken': idToken,
      'inviteCode': inviteCode,
    });
    return '${data['status'] ?? ''}';
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
