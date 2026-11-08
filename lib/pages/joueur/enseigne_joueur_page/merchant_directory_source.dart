import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import 'merchant_directory_logic.dart';

/// One page of merchants in stable document-id order.
class DirectoryPage {
  const DirectoryPage(
      {required this.merchants, required this.cursor, required this.hasMore});
  final List<DirectoryMerchant> merchants;
  final Object? cursor;
  final bool hasMore;
}

/// Every read and write of the player directory. The page builds one instance;
/// tests substitute a fake that counts calls.
abstract class MerchantDirectorySource {
  /// Next page after [cursor] (null: first page).
  Future<DirectoryPage> fetchPage({Object? cursor, required int limit});

  /// Merchants by document id, in as few queries as Firestore allows.
  Future<List<DirectoryMerchant>> fetchByIds(List<String> ids);

  /// One query: games still running, evaluated like the merchant page.
  Future<ActiveGamesResult> fetchActiveGames(DateTime now);

  /// Merchant id -> favorite documents of the signed-in player; null when no
  /// player can hold favorites (guest).
  Stream<Map<String, List<Object>>>? favorites();

  Future<void> addFavorite(String merchantId);
  Future<void> removeFavorite(List<Object> favoriteHandles);

  /// First photo of the merchant, '' when none.
  Future<String> photoUrl(DirectoryMerchant merchant);
}

DirectoryMerchant directoryMerchantFromRecord(EnseignesRecord record) =>
    DirectoryMerchant(
      id: record.reference.id,
      name: record.name,
      description: record.description,
      city: record.city,
      categories: record.category,
      googleRating: record.googleRating,
      googleReviewsCount:
          record.hasGoogleReviewsCount() ? record.googleReviewsCount : null,
      record: record,
    );

class FirestoreMerchantDirectorySource implements MerchantDirectorySource {
  FirestoreMerchantDirectorySource({this.activeGamesLimit = 200});

  /// Upper bound of the ongoing-games query (single-field index on end_date).
  final int activeGamesLimit;

  @override
  Future<DirectoryPage> fetchPage({Object? cursor, required int limit}) async {
    Query query =
        EnseignesRecord.collection.orderBy(FieldPath.documentId).limit(limit);
    if (cursor is DocumentSnapshot) query = query.startAfterDocument(cursor);
    final snapshot = await query.get();
    return DirectoryPage(
      merchants: snapshot.docs
          .map((doc) =>
              directoryMerchantFromRecord(EnseignesRecord.fromSnapshot(doc)))
          .toList(),
      cursor: snapshot.docs.isEmpty ? cursor : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  @override
  Future<List<DirectoryMerchant>> fetchByIds(List<String> ids) async {
    final unique = ids.toSet().toList();
    final result = <DirectoryMerchant>[];
    for (var start = 0; start < unique.length; start += 30) {
      final chunk = unique.sublist(
          start, start + 30 > unique.length ? unique.length : start + 30);
      final snapshot = await EnseignesRecord.collection
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      result.addAll(snapshot.docs.map((doc) =>
          directoryMerchantFromRecord(EnseignesRecord.fromSnapshot(doc))));
    }
    return result;
  }

  @override
  Future<ActiveGamesResult> fetchActiveGames(DateTime now) async {
    final snapshot = await GamesRecord.collection
        .where('end_date', isGreaterThan: now)
        .orderBy('end_date')
        .limit(activeGamesLimit)
        .get();
    final games = snapshot.docs.map((doc) {
      final game = GamesRecord.fromSnapshot(doc);
      return (
        merchantPath: game.enseigneId?.path,
        data: game.snapshotData,
        startDate: game.startDate,
        endDate: game.endDate,
      );
    });
    return ActiveGamesResult(
      merchantIds: activeMerchantIdsFromGames(games, now),
      complete: snapshot.docs.length < activeGamesLimit,
    );
  }

  @override
  Stream<Map<String, List<Object>>>? favorites() {
    if (currentUserUid.isEmpty || currentUserReference == null) return null;
    return queryFavoriteEnseignesRecord(parent: currentUserReference).map(
      (records) {
        final byMerchant = <String, List<Object>>{};
        for (final record in records) {
          final ref = record.enseigneId;
          if (ref == null || ref.parent.id != 'enseignes') continue;
          byMerchant.putIfAbsent(ref.id, () => []).add(record.reference);
        }
        return byMerchant;
      },
    );
  }

  /// Same transaction as before: the document id is the merchant id, so a
  /// double tap never creates a second favorite.
  @override
  Future<void> addFavorite(String merchantId) async {
    final user = currentUserReference;
    if (user == null) return;
    final merchantRef = EnseignesRecord.collection.doc(merchantId);
    final favoriteRef = FavoriteEnseignesRecord.createDoc(user, id: merchantId);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final favoriteSnap = await transaction.get(favoriteRef);
      if (favoriteSnap.exists) return;
      transaction.set(favoriteRef, {
        ...createFavoriteEnseignesRecordData(enseigneId: merchantRef),
        ...mapToFirestore({'added_at': FieldValue.serverTimestamp()}),
      });
    });
  }

  /// Removes every favorite document of the merchant (historic duplicates
  /// included), so the heart really turns off.
  @override
  Future<void> removeFavorite(List<Object> favoriteHandles) async {
    final refs = favoriteHandles.whereType<DocumentReference>().toList();
    if (refs.isEmpty) return;
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snaps = [for (final ref in refs) await transaction.get(ref)];
      for (final snap in snaps) {
        if (snap.exists) transaction.delete(snap.reference);
      }
    });
  }

  @override
  Future<String> photoUrl(DirectoryMerchant merchant) async {
    final images = await queryImagesRecordOnce(
      parent: EnseignesRecord.collection.doc(merchant.id),
      singleRecord: true,
    );
    return images.firstOrNull?.url ?? '';
  }
}
