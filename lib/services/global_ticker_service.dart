import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class GlobalTickerSnapshot {
  const GlobalTickerSnapshot({
    required this.totalPlayers,
    required this.totalGamesPlayed,
    required this.totalMerchants,
    required this.messages,
    required this.updatedAt,
  });

  final int totalPlayers;
  final int totalGamesPlayed;
  final int totalMerchants;
  final List<String> messages;
  final DateTime? updatedAt;

  factory GlobalTickerSnapshot.fromMap(Map<String, dynamic> data) {
    final rawMessages = data['recentWinnerMessages'];
    final updatedAtValue = data['updatedAt'];
    return GlobalTickerSnapshot(
      totalPlayers: _toInt(data['totalPlayers']),
      totalGamesPlayed: _toInt(data['totalGamesPlayed']),
      totalMerchants: _toInt(data['totalMerchants']),
      messages: rawMessages is Iterable
          ? rawMessages
              .map((item) => item?.toString().trim() ?? '')
              .where((item) => item.isNotEmpty)
              .toList()
          : const <String>[],
      updatedAt: updatedAtValue is Timestamp ? updatedAtValue.toDate() : null,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class GlobalTickerService {
  const GlobalTickerService();

  static const int estimatedTickerReadsBeforePerRefresh = 9;
  static const int tickerReadsAfterStartup = 1;

  Future<GlobalTickerSnapshot?> fetchOnce() async {
    debugPrint(
      '[TickerReads][before_estimate] recent_winners_ticker='
      '1 prizes query + up to 8 user reads => up to '
      '$estimatedTickerReadsBeforePerRefresh reads per reload',
    );

    final snapshot = await FirebaseFirestore.instance
        .collection('stats')
        .doc('global')
        .get();

    debugPrint(
      '[TickerReads][after_estimate] global_ticker='
      '$tickerReadsAfterStartup read at startup, then 0 reads on home rebuild/resume',
    );

    if (!snapshot.exists) {
      debugPrint('[GlobalTicker] stats/global missing');
      return null;
    }

    final data = snapshot.data();
    if (data == null) {
      debugPrint('[GlobalTicker] stats/global empty payload');
      return null;
    }

    final parsed = GlobalTickerSnapshot.fromMap(data);
    debugPrint(
      '[GlobalTicker] loaded updatedAt=${parsed.updatedAt?.toIso8601String() ?? 'null'} '
      'players=${parsed.totalPlayers} games=${parsed.totalGamesPlayed} '
      'merchants=${parsed.totalMerchants} tickerMessages=${parsed.messages.length}',
    );
    return parsed;
  }
}
