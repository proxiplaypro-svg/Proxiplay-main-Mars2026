import 'package:cloud_functions/cloud_functions.dart';
import '/backend/backend.dart';

class MerchantGamesPage {
  const MerchantGamesPage(this.games, this.cursor, this.hasMore);
  final List<GamesRecord> games;
  final String cursor;
  final bool hasMore;
}

Future<MerchantGamesPage> loadMerchantGamesPage({String cursor = ''}) async {
  final result = await FirebaseFunctions.instanceFor(region: 'europe-west1')
      .httpsCallable('getMerchantGames')
      .call({'cursor': cursor});
  final data = Map<String, dynamic>.from(result.data as Map);
  final ids = List<String>.from(data['ids'] as List);
  final snapshots = await Future.wait(ids.map(
      (id) => FirebaseFirestore.instance.collection('games').doc(id).get()));
  return MerchantGamesPage(
    snapshots.where((doc) => doc.exists).map(GamesRecord.fromSnapshot).toList(),
    data['cursor'] as String,
    data['hasMore'] == true,
  );
}

/// Aggregates and account checks must not silently truncate at 15 or 500.
Future<List<GamesRecord>> loadAllMerchantGames() async {
  final games = <GamesRecord>[];
  var cursor = '';
  while (true) {
    final page = await loadMerchantGamesPage(cursor: cursor);
    games.addAll(page.games);
    if (!page.hasMore) return games;
    cursor = page.cursor;
  }
}
