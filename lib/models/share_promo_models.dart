import 'package:cloud_firestore/cloud_firestore.dart';

class SharePromoCampaignModel {
  const SharePromoCampaignModel({
    required this.enabled,
    required this.kind,
    required this.title,
    required this.message,
    required this.ctaText,
    required this.startAt,
    required this.endAt,
    required this.rewardType,
    required this.rewardValue,
    required this.maxRewardsPerUser,
    required this.maxRewardsPerInvitee,
    required this.requireInviteeSignup,
    required this.audience,
    required this.isDraft,
    required this.priority,
    required this.updatedBy,
  });

  factory SharePromoCampaignModel.fromMap(Map<String, dynamic> map) {
    return SharePromoCampaignModel(
      enabled: map['enabled'] == true,
      kind: (map['kind'] as String?) ?? 'defaultInvite',
      title: (map['title'] as String?) ?? '',
      message: (map['message'] as String?) ?? '',
      ctaText: (map['ctaText'] as String?) ?? 'Inviter un ami',
      startAt: _readTimestamp(map['startAt']),
      endAt: _readTimestamp(map['endAt']),
      rewardType:
          (map['rewardType'] as String?) ?? 'all_games_until_midnight',
      rewardValue: (map['rewardValue'] as num?)?.toInt() ?? 0,
      maxRewardsPerUser: (map['maxRewardsPerUser'] as num?)?.toInt() ?? 10,
      maxRewardsPerInvitee:
          (map['maxRewardsPerInvitee'] as num?)?.toInt() ?? 1,
      requireInviteeSignup: map['requireInviteeSignup'] != false,
      audience: (map['audience'] as String?) ?? 'all',
      isDraft: map['isDraft'] != false,
      priority: (map['priority'] as num?)?.toInt() ?? 0,
      updatedBy: (map['updatedBy'] as String?) ?? '',
    );
  }

  final bool enabled;
  final String kind;
  final String title;
  final String message;
  final String ctaText;
  final Timestamp? startAt;
  final Timestamp? endAt;
  final String rewardType;
  final int rewardValue;
  final int maxRewardsPerUser;
  final int maxRewardsPerInvitee;
  final bool requireInviteeSignup;
  final String audience;
  final bool isDraft;
  final int priority;
  final String updatedBy;

  Map<String, dynamic> toCallableMap() {
    return {
      'enabled': enabled,
      'kind': kind,
      'title': title,
      'message': message,
      'ctaText': ctaText,
      'startAt': startAt?.toDate().toIso8601String(),
      'endAt': endAt?.toDate().toIso8601String(),
      'rewardType': rewardType,
      'rewardValue': rewardValue,
      'maxRewardsPerUser': maxRewardsPerUser,
      'maxRewardsPerInvitee': maxRewardsPerInvitee,
      'requireInviteeSignup': requireInviteeSignup,
      'audience': audience,
      'isDraft': isDraft,
      'priority': priority,
    };
  }

  SharePromoCampaignModel copyWith({
    bool? enabled,
    String? kind,
    String? title,
    String? message,
    String? ctaText,
    Timestamp? startAt,
    Timestamp? endAt,
    String? rewardType,
    int? rewardValue,
    int? maxRewardsPerUser,
    int? maxRewardsPerInvitee,
    bool? requireInviteeSignup,
    String? audience,
    bool? isDraft,
    int? priority,
    String? updatedBy,
  }) {
    return SharePromoCampaignModel(
      enabled: enabled ?? this.enabled,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      message: message ?? this.message,
      ctaText: ctaText ?? this.ctaText,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      rewardType: rewardType ?? this.rewardType,
      rewardValue: rewardValue ?? this.rewardValue,
      maxRewardsPerUser: maxRewardsPerUser ?? this.maxRewardsPerUser,
      maxRewardsPerInvitee:
          maxRewardsPerInvitee ?? this.maxRewardsPerInvitee,
      requireInviteeSignup:
          requireInviteeSignup ?? this.requireInviteeSignup,
      audience: audience ?? this.audience,
      isDraft: isDraft ?? this.isDraft,
      priority: priority ?? this.priority,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  static SharePromoCampaignModel empty() => const SharePromoCampaignModel(
        enabled: false,
        kind: 'defaultInvite',
        title: 'Inviter un ami',
        message: 'Invite un ami et joue à tous les jeux jusqu’à minuit.',
        ctaText: 'Inviter un ami',
        startAt: null,
        endAt: null,
        rewardType: 'all_games_until_midnight',
        rewardValue: 0,
        maxRewardsPerUser: 10,
        maxRewardsPerInvitee: 1,
        requireInviteeSignup: true,
        audience: 'all',
        isDraft: true,
        priority: 0,
        updatedBy: '',
      );

  static Timestamp? _readTimestamp(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value;
    }
    if (value is DateTime) {
      return Timestamp.fromDate(value);
    }
    if (value is int) {
      return Timestamp.fromMillisecondsSinceEpoch(value);
    }
    if (value is num) {
      return Timestamp.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value.trim());
      if (parsed != null) {
        return Timestamp.fromDate(parsed);
      }
    }
    if (value is Map) {
      final seconds = value['_seconds'] ?? value['seconds'];
      final nanoseconds = value['_nanoseconds'] ?? value['nanoseconds'] ?? 0;
      if (seconds is num && nanoseconds is num) {
        return Timestamp(seconds.toInt(), nanoseconds.toInt());
      }
    }
    return null;
  }
}

class SharePromoStateViewModel {
  const SharePromoStateViewModel({
    required this.showBanner,
    required this.kind,
    required this.title,
    required this.message,
    required this.ctaText,
    required this.action,
    required this.campaignId,
    required this.rewardType,
    required this.rewardValue,
  });

  factory SharePromoStateViewModel.fromMap(Map<String, dynamic> map) {
    final campaign = map['campaign'] is Map<String, dynamic>
        ? map['campaign'] as Map<String, dynamic>
        : <String, dynamic>{};
    return SharePromoStateViewModel(
      showBanner: map['showBanner'] == true,
      kind: map['kind'] as String?,
      title: map['title'] as String?,
      message: map['message'] as String?,
      ctaText: map['ctaText'] as String?,
      action: map['action'] as String?,
      campaignId: campaign['id'] as String?,
      rewardType: campaign['rewardType'] as String?,
      rewardValue: (campaign['rewardValue'] as num?)?.toInt(),
    );
  }

  final bool showBanner;
  final String? kind;
  final String? title;
  final String? message;
  final String? ctaText;
  final String? action;
  final String? campaignId;
  final String? rewardType;
  final int? rewardValue;
}

class SharePromoAdminStatsModel {
  const SharePromoAdminStatsModel({
    required this.pendingReferrals,
    required this.acceptedReferrals,
    required this.grantedRewards,
    required this.activeCampaigns,
    required this.recentReferrals,
    required this.recentRewards,
    required this.topInviters,
  });

  factory SharePromoAdminStatsModel.fromMap(Map<String, dynamic> map) {
    final stats = map['stats'] is Map<String, dynamic>
        ? map['stats'] as Map<String, dynamic>
        : <String, dynamic>{};
    return SharePromoAdminStatsModel(
      pendingReferrals: (stats['pendingReferrals'] as num?)?.toInt() ?? 0,
      acceptedReferrals: (stats['acceptedReferrals'] as num?)?.toInt() ?? 0,
      grantedRewards: (stats['grantedRewards'] as num?)?.toInt() ?? 0,
      activeCampaigns: (stats['activeCampaigns'] as num?)?.toInt() ?? 0,
      recentReferrals: (map['recentReferrals'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      recentRewards: (map['recentRewards'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      topInviters: (map['topInviters'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
    );
  }

  final int pendingReferrals;
  final int acceptedReferrals;
  final int grantedRewards;
  final int activeCampaigns;
  final List<Map<String, dynamic>> recentReferrals;
  final List<Map<String, dynamic>> recentRewards;
  final List<Map<String, dynamic>> topInviters;
}
