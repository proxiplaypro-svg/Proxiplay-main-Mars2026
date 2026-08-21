import 'package:cloud_functions/cloud_functions.dart';

import '/models/monthly_challenge_models.dart';

class MonthlyChallengeService {
  MonthlyChallengeService({
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

  Future<MonthlyChallengeStateViewModel> getMonthlyChallengeState() async {
    final data = await _call('getMonthlyChallengeState');
    return MonthlyChallengeStateViewModel.fromMap(data);
  }

  Future<List<MonthlyChallengeStateViewModel>> getMonthlyChallengesState() async {
    final data = await _call('getMonthlyChallengesState');
    return (data['challenges'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => MonthlyChallengeStateViewModel.fromMap(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  Future<MonthlyChallengeConfigModel> adminGetMonthlyChallengeConfig({
    String type = 'attendance',
    String month = '',
  }) async {
    final data = await _call('adminGetMonthlyChallengeConfig', {
      'type': type,
      'month': month,
    });
    return MonthlyChallengeConfigModel.fromMap(data);
  }

  Future<void> adminUpsertMonthlyChallenge(
    MonthlyChallengeConfigModel config,
  ) async {
    await _call('adminUpsertMonthlyChallenge', config.toCallableMap());
  }

  Future<MonthlyChallengeAdminStatsModel> adminGetMonthlyChallengeStats({
    String type = 'attendance',
    String month = '',
  }) async {
    final data = await _call('adminGetMonthlyChallengeStats', {
      'type': type,
      'month': month,
    });
    return MonthlyChallengeAdminStatsModel.fromMap(data);
  }

  Future<Map<String, dynamic>> adminRunMonthlyChallengeDraw({
    String type = 'attendance',
    String month = '',
  }) {
    return _call('adminRunMonthlyChallengeDraw', {'type': type, 'month': month});
  }
}
