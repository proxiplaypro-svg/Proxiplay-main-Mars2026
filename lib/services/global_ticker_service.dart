import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

String _normalizeTickerText(String value) {
  return value
      .replaceAllMapped(
        RegExp(r'\\u([0-9A-Fa-f]{4})'),
        (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
      )
      .replaceAll('gagnÃƒ©', 'gagné')
      .replaceAll('RÃƒ©', 'Ré')
      .replaceAll('rÃƒ©', 'ré')
      .replaceAll('Ãƒ©', 'é')
      .replaceAll('Ãƒ¨', 'è')
      .replaceAll('Ãƒª', 'ê')
      .replaceAll('Ãƒ«', 'ë')
      .replaceAll('Ãƒ ', 'à')
      .replaceAll('Ãƒ ', 'à')
      .replaceAll('Ãƒ¢', 'â')
      .replaceAll('Ãƒ®', 'î')
      .replaceAll('Ãƒ´', 'ô')
      .replaceAll('Ãƒ¹', 'ù')
      .replaceAll('Ãƒ»', 'û')
      .replaceAll('Ãƒ§', 'ç')
      .replaceAll('Ã¢â‚¬â„¢', "'")
      .replaceAll('Ã¢â‚¬Ëœ', "'")
      .replaceAll('Ã¢â‚¬Å“', '"')
      .replaceAll('Ã¢â‚¬Â', '"')
      .replaceAll('Ã¢â‚¬Â¦', '...')
      .replaceAll('Ã¢â‚¬â€œ', '-')
      .replaceAll('Ã¢â‚¬â€', '-')
      .replaceAll('Ã¢â€š¬', 'â‚¬')
      .replaceAllMapped(
        RegExp(r'\\bdachat\\b', caseSensitive: false),
        (match) => match.group(0)!.startsWith('D') ? "D'achat" : "d'achat",
      )
      .trim();
}

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
              .map((item) => _normalizeTickerText(item?.toString().trim() ?? ''))
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
  static Future<GlobalTickerSnapshot?>? _inFlightFetch;
  static GlobalTickerSnapshot? _cachedSnapshot;

  Future<GlobalTickerSnapshot?> fetchOnce() async {
    final cachedSnapshot = _cachedSnapshot;
    if (cachedSnapshot != null) {
      return cachedSnapshot;
    }

    final inFlightFetch = _inFlightFetch;
    if (inFlightFetch != null) {
      return inFlightFetch;
    }

    final fetchFuture = _fetchOnceInternal();
    _inFlightFetch = fetchFuture;
    try {
      final snapshot = await fetchFuture;
      if (snapshot != null) {
        _cachedSnapshot = snapshot;
      }
      return snapshot;
    } finally {
      if (identical(_inFlightFetch, fetchFuture)) {
        _inFlightFetch = null;
      }
    }
  }

  Future<GlobalTickerSnapshot?> _fetchOnceInternal() async {
    debugPrint(
      '[TickerReads][before_estimate] recent_winners_ticker='
      '1 prizes query + up to 8 user reads => up to '
      '$estimatedTickerReadsBeforePerRefresh reads per reload',
    );

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('stats')
          .doc('global')
          .get();

      debugPrint(
        '[TickerReads][after_estimate] global_ticker='
        '$tickerReadsAfterStartup read at startup, then 0 reads on home rebuild/resume',
      );

      if (!snapshot.exists) {
        debugPrint(
          '[GlobalTicker] stats/global missing, falling back to one-time legacy load',
        );
        return _fetchLegacyFallback();
      }

      final data = snapshot.data();
      if (data == null) {
        debugPrint(
          '[GlobalTicker] stats/global empty payload, falling back to one-time legacy load',
        );
        return _fetchLegacyFallback();
      }

      final parsed = GlobalTickerSnapshot.fromMap(data);
      if (parsed.messages.isEmpty) {
        debugPrint(
          '[GlobalTicker] stats/global has no ticker messages, falling back to one-time legacy load',
        );
        return _fetchLegacyFallback();
      }
      debugPrint(
        '[GlobalTicker] loaded updatedAt=${parsed.updatedAt?.toIso8601String() ?? 'null'} '
        'players=${parsed.totalPlayers} games=${parsed.totalGamesPlayed} '
        'merchants=${parsed.totalMerchants} tickerMessages=${parsed.messages.length}',
      );
      return parsed;
    } catch (error) {
      debugPrint(
        '[GlobalTicker] stats/global read failed, falling back to one-time legacy load error=$error',
      );
      return _fetchLegacyFallback();
    }
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
        if (prizeName.isEmpty) {
          continue;
        }

        // Prefere les champs denormalises ecrits par les Cloud Functions de
        // tirage (voir participate_in_game_transaction.js /
        // pickMainPrizeWinners / drawWinnerForAnimation) : evite une lecture
        // du profil d'un autre utilisateur, desormais restreinte par les
        // regles Firestore a l'utilisateur lui-meme ou un admin.
        final denormalizedFirstName = (prizeData['winnerFirstName'] ??
                prizeData['winner_first_name'] ??
                '')
            .toString()
            .trim();

        var firstName = _normalizeFirstName(denormalizedFirstName);

        final winnerRef = prizeData['winner_id'];
        if (firstName.isEmpty && winnerRef is DocumentReference) {
          Map<String, dynamic>? winnerData = userCache[winnerRef.path];
          if (!userCache.containsKey(winnerRef.path)) {
            try {
              final winnerSnap = await winnerRef.get();
              winnerData = winnerSnap.data() as Map<String, dynamic>?;
            } catch (error) {
              // Anciennes donnees non re-tirees depuis ce correctif : pas de
              // champ denormalise ET lecture refusee. On degrade sur "Un
              // joueur" pour cette seule entree plutot que de faire echouer
              // tout le fallback.
              debugPrint(
                '[GlobalTicker] legacy fallback winner read denied '
                'ref=${winnerRef.path} error=$error',
              );
              winnerData = null;
            }
            userCache[winnerRef.path] = winnerData;
          }

          firstName = _normalizeFirstName(
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
        }

        final message = enseigneName.isNotEmpty
            ? _normalizeTickerText('${firstName.isNotEmpty ? firstName : 'Un joueur'} a gagné $prizeName chez $enseigneName')
            : _normalizeTickerText('${firstName.isNotEmpty ? firstName : 'Un joueur'} a gagné $prizeName');
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




