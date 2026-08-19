import 'package:cloud_firestore/cloud_firestore.dart';

class MonthlyChallengeStateViewModel {
  const MonthlyChallengeStateViewModel({
    required this.showCard,
    required this.enabled,
    required this.month,
    required this.monthLabel,
    required this.title,
    required this.description,
    required this.targetDays,
    required this.prizeTitle,
    required this.prizeDescription,
    required this.prizeValue,
    required this.imageUrl,
    required this.drawDate,
    required this.activeDaysCount,
    required this.activeDates,
    required this.remainingDays,
    required this.qualified,
    required this.qualifiedAt,
    required this.drawEntryCreated,
    required this.winner,
    required this.wonAt,
  });

  factory MonthlyChallengeStateViewModel.fromMap(Map<String, dynamic> map) {
    return MonthlyChallengeStateViewModel(
      showCard: map['showCard'] == true,
      enabled: map['enabled'] == true,
      month: (map['month'] as String?) ?? '',
      monthLabel: (map['monthLabel'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      targetDays: (map['targetDays'] as num?)?.toInt() ?? 0,
      prizeTitle: (map['prizeTitle'] as String?) ?? '',
      prizeDescription: (map['prizeDescription'] as String?) ?? '',
      prizeValue: (map['prizeValue'] as num?)?.toInt() ?? 0,
      imageUrl: (map['imageUrl'] as String?) ?? '',
      drawDate: _readTimestamp(map['drawDate']),
      activeDaysCount: (map['activeDaysCount'] as num?)?.toInt() ?? 0,
      activeDates: (map['activeDates'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      remainingDays: (map['remainingDays'] as num?)?.toInt() ?? 0,
      qualified: map['qualified'] == true,
      qualifiedAt: _readTimestamp(map['qualifiedAt']),
      drawEntryCreated: map['drawEntryCreated'] == true,
      winner: map['winner'] == true,
      wonAt: _readTimestamp(map['wonAt']),
    );
  }

  final bool showCard;
  final bool enabled;
  final String month;
  final String monthLabel;
  final String title;
  final String description;
  final int targetDays;
  final String prizeTitle;
  final String prizeDescription;
  final int prizeValue;
  final String imageUrl;
  final Timestamp? drawDate;
  final int activeDaysCount;
  final List<String> activeDates;
  final int remainingDays;
  final bool qualified;
  final Timestamp? qualifiedAt;
  final bool drawEntryCreated;
  final bool winner;
  final Timestamp? wonAt;
}

class MonthlyChallengeConfigModel {
  const MonthlyChallengeConfigModel({
    required this.enabled,
    required this.month,
    required this.title,
    required this.description,
    required this.targetDays,
    required this.prizeTitle,
    required this.prizeDescription,
    required this.prizeValue,
    required this.imageUrl,
    required this.drawDate,
  });

  factory MonthlyChallengeConfigModel.fromMap(Map<String, dynamic> map) {
    return MonthlyChallengeConfigModel(
      enabled: map['enabled'] == true,
      month: (map['month'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      targetDays: (map['target_days'] as num?)?.toInt() ??
          (map['targetDays'] as num?)?.toInt() ??
          15,
      prizeTitle: (map['prize_title'] as String?) ??
          (map['prizeTitle'] as String?) ??
          '',
      prizeDescription: (map['prize_description'] as String?) ??
          (map['prizeDescription'] as String?) ??
          '',
      prizeValue: (map['prize_value'] as num?)?.toInt() ??
          (map['prizeValue'] as num?)?.toInt() ??
          0,
      imageUrl: (map['image_url'] as String?) ?? (map['imageUrl'] as String?) ?? '',
      drawDate: _readTimestamp(map['draw_date'] ?? map['drawDate']),
    );
  }

  final bool enabled;
  final String month;
  final String title;
  final String description;
  final int targetDays;
  final String prizeTitle;
  final String prizeDescription;
  final int prizeValue;
  final String imageUrl;
  final Timestamp? drawDate;

  Map<String, dynamic> toCallableMap() {
    return {
      'enabled': enabled,
      'month': month,
      'title': title,
      'description': description,
      'target_days': targetDays,
      'prize_title': prizeTitle,
      'prize_description': prizeDescription,
      'prize_value': prizeValue,
      'image_url': imageUrl,
      'draw_date': drawDate?.toDate().toIso8601String(),
    };
  }

  MonthlyChallengeConfigModel copyWith({
    bool? enabled,
    String? month,
    String? title,
    String? description,
    int? targetDays,
    String? prizeTitle,
    String? prizeDescription,
    int? prizeValue,
    String? imageUrl,
    Timestamp? drawDate,
  }) {
    return MonthlyChallengeConfigModel(
      enabled: enabled ?? this.enabled,
      month: month ?? this.month,
      title: title ?? this.title,
      description: description ?? this.description,
      targetDays: targetDays ?? this.targetDays,
      prizeTitle: prizeTitle ?? this.prizeTitle,
      prizeDescription: prizeDescription ?? this.prizeDescription,
      prizeValue: prizeValue ?? this.prizeValue,
      imageUrl: imageUrl ?? this.imageUrl,
      drawDate: drawDate ?? this.drawDate,
    );
  }

  static MonthlyChallengeConfigModel empty() => const MonthlyChallengeConfigModel(
        enabled: false,
        month: '',
        title: '',
        description: '',
        targetDays: 15,
        prizeTitle: '',
        prizeDescription: '',
        prizeValue: 0,
        imageUrl: '',
        drawDate: null,
      );
}

class MonthlyChallengeAdminStatsModel {
  const MonthlyChallengeAdminStatsModel({
    required this.config,
    required this.startedCount,
    required this.qualifiedCount,
    required this.qualificationRate,
    required this.averageActiveDays,
    required this.medianActiveDays,
    required this.progressAverageLabel,
    required this.distribution,
    required this.timeline,
    required this.drawStatus,
    required this.eligibleCount,
    required this.winnerUid,
    required this.drawnAt,
  });

  factory MonthlyChallengeAdminStatsModel.fromMap(Map<String, dynamic> map) {
    final configMap = map['config'] is Map<String, dynamic>
        ? map['config'] as Map<String, dynamic>
        : <String, dynamic>{};
    final statsMap = map['stats'] is Map<String, dynamic>
        ? map['stats'] as Map<String, dynamic>
        : <String, dynamic>{};
    return MonthlyChallengeAdminStatsModel(
      config: MonthlyChallengeConfigModel.fromMap(configMap),
      startedCount: (statsMap['startedCount'] as num?)?.toInt() ?? 0,
      qualifiedCount: (statsMap['qualifiedCount'] as num?)?.toInt() ?? 0,
      qualificationRate:
          (statsMap['qualificationRate'] as num?)?.toDouble() ?? 0,
      averageActiveDays:
          (statsMap['averageActiveDays'] as num?)?.toDouble() ?? 0,
      medianActiveDays:
          (statsMap['medianActiveDays'] as num?)?.toDouble() ?? 0,
      progressAverageLabel: (statsMap['progressAverageLabel'] as String?) ?? '',
      distribution:
          (statsMap['distribution'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (item) => MonthlyChallengeDistributionBucket.fromMap(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(),
      timeline: (statsMap['timeline'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => MonthlyChallengeTimelinePoint.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      drawStatus: (statsMap['drawStatus'] as String?) ?? '',
      eligibleCount: (statsMap['eligibleCount'] as num?)?.toInt() ?? 0,
      winnerUid: (statsMap['winnerUid'] as String?) ?? '',
      drawnAt: _readTimestamp(statsMap['drawnAt']),
    );
  }

  final MonthlyChallengeConfigModel config;
  final int startedCount;
  final int qualifiedCount;
  final double qualificationRate;
  final double averageActiveDays;
  final double medianActiveDays;
  final String progressAverageLabel;
  final List<MonthlyChallengeDistributionBucket> distribution;
  final List<MonthlyChallengeTimelinePoint> timeline;
  final String drawStatus;
  final int eligibleCount;
  final String winnerUid;
  final Timestamp? drawnAt;
}

class MonthlyChallengeDistributionBucket {
  const MonthlyChallengeDistributionBucket({
    required this.label,
    required this.min,
    required this.max,
    required this.count,
  });

  factory MonthlyChallengeDistributionBucket.fromMap(Map<String, dynamic> map) {
    return MonthlyChallengeDistributionBucket(
      label: (map['label'] as String?) ?? '',
      min: (map['min'] as num?)?.toInt() ?? 0,
      max: (map['max'] as num?)?.toInt(),
      count: (map['count'] as num?)?.toInt() ?? 0,
    );
  }

  final String label;
  final int min;
  final int? max;
  final int count;
}

class MonthlyChallengeTimelinePoint {
  const MonthlyChallengeTimelinePoint({
    required this.day,
    required this.dateKey,
    required this.participants,
    required this.qualified,
  });

  factory MonthlyChallengeTimelinePoint.fromMap(Map<String, dynamic> map) {
    return MonthlyChallengeTimelinePoint(
      day: (map['day'] as num?)?.toInt() ?? 0,
      dateKey: (map['dateKey'] as String?) ?? '',
      participants: (map['participants'] as num?)?.toInt() ?? 0,
      qualified: (map['qualified'] as num?)?.toInt() ?? 0,
    );
  }

  final int day;
  final String dateKey;
  final int participants;
  final int qualified;
}

Timestamp? _readTimestamp(dynamic value) {
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
