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
      debugPrint('[GlobalTicker] stats/global missing, falling back to one-time legacy load');
      return _fetchLegacyFallback();
    }

    final data = snapshot.data();
    if (data == null) {
      debugPrint('[GlobalTicker] stats/global empty payload, falling back to one-time legacy load');
      return _fetchLegacyFallback();
    }

    final parsed = GlobalTickerSnapshot.fromMap(data);
    if (parsed.messages.isEmpty) {
      debugPrint('[GlobalTicker] stats/global has no ticker messages, falling back to one-time legacy load');
      return _fetchLegacyFallback();
    }
    debugPrint(
      '[GlobalTicker] loaded updatedAt=${parsed.updatedAt?.toIso8601String() ?? 'null'} '
      'players=${parsed.totalPlayers} games=${parsed.totalGamesPlayed} '
      'merchants=${parsed.totalMerchants} tickerMessages=${parsed.messages.length}',
    );
    return parsed;
  }

  Future<GlobalTickerSnapshot?> _fetchLegacyFallback() async {
    try {
      final prizesSnapshot = await FirebaseFirestore.instance
          .collection('prizes')
          .orderBy('win_date', descending: true)
          .limit(12)
          .get();

      final messages = <String>[];
      final userCache = <String, Map<String, dynamic>?>{};

      for (final prizeDoc in prizesSnapshot.docs) {
        if (messages.length >= 8) {
          break;
        }

        final prizeData = prizeDoc.data();
        final prizeName = (prizeData['name'] ?? '').toString().trim();
        final enseigneName = (prizeData['enseigne_name'] ?? '').toString().trim();
        final winnerRef = prizeData['winner_id'];
        if (prizeName.isEmpty || winnerRef is! DocumentReference) {
          continue;
        }

        Map<String, dynamic>? winnerData = userCache[winnerRef.path];
        if (!userCache.containsKey(winnerRef.path)) {
          final winnerSnap = await winnerRef.get();
          winnerData = winnerSnap.data() as Map<String, dynamic>?;
          userCache[winnerRef.path] = winnerData;
        }

        final firstName = _normalizeFirstName(
          [
            winnerData?['first_name'],
            winnerData?['firstName'],
            winnerData?['display_name'],
            winnerData?['displayName'],
            winnerData?['pseudo'],
          ]
              .map((value) => value?.toString().trim() ?? '')
              .firstWhere((value) => value.isNotEmpty, orElse: () => ''),
        );

        final message = enseigneName.isNotEmpty
            ? '${firstName.isNotEmpty ? firstName : 'Un joueur'} a gagne $prizeName chez $enseigneName'
            : '${firstName.isNotEmpty ? firstName : 'Un joueur'} a gagne $prizeName';
        messages.add(message);
      }

      debugPrint(
        '[GlobalTicker] legacy fallback loaded tickerMessages=${messages.length} '
        'estimatedReads=${1 + userCache.length}',
      );

      return GlobalTickerSnapshot(
        totalPlayers: 0,
        totalGamesPlayed: 0,
        totalMerchants: 0,
        messages: messages,
        updatedAt: null,
      );
    } catch (error) {
      debugPrint('[GlobalTicker] legacy fallback failed error=$error');
      return null;
    }
  }

  String _normalizeFirstName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.split(RegExp(r'\s+')).first;
  }
}
