import 'package:cloud_functions/cloud_functions.dart';
import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';

String? merchantIdentityPath(dynamic value) {
  if (value is DocumentReference) return value.path;
  if (value is! String) return null;
  final text = value.replaceFirst(RegExp(r'^/'), '');
  if (RegExp(r'^users/[^/]+$').hasMatch(text)) return text;
  return text.isNotEmpty && !text.contains('/') ? 'users/$text' : null;
}

bool shopBelongsToMerchant(Map<String, dynamic> data, String uid) {
  final identities = [data['owner_id'], data['owner']].where((v) => v != null);
  return identities.isNotEmpty &&
      identities.every((v) => merchantIdentityPath(v) == 'users/$uid');
}

Future<List<PrizesRecord>> loadMerchantPrizes({String gameId = ''}) async {
  final prizes = <PrizesRecord>[];
  var cursor = '';
  do {
    final response = await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('getMerchantPrizes')
        .call({'gameId': gameId, 'cursor': cursor});
    final data = Map<String, dynamic>.from(response.data as Map);
    final snapshots = await Future.wait(List<String>.from(data['ids']).map(
        (id) => FirebaseFirestore.instance.collection('prizes').doc(id).get()));
    prizes.addAll(
        snapshots.where((s) => s.exists).map(PrizesRecord.fromSnapshot));
    if (data['hasMore'] != true) return prizes;
    final next = data['cursor'] as String;
    if (next == cursor) throw StateError('Invalid prize pagination');
    cursor = next;
  } while (true);
}

Future<Set<String>> _ownedPrizeShop(PrizesRecord prize, String uid) async {
  if (prize.snapshotData['owner_id'] != null || prize.enseigneId == null) {
    return {};
  }
  final shop = await prize.enseigneId!.get();
  return shop.exists &&
          shopBelongsToMerchant(
              Map<String, dynamic>.from(shop.data() as Map), uid)
      ? {shop.reference.path}
      : {};
}

Future<bool> canClaimMerchantPrize(PrizesRecord prize) async {
  final uid = currentUserUid;
  if (uid.isEmpty) return false;
  return prize.canBeClaimedBy(uid, await _ownedPrizeShop(prize, uid));
}

/// Reread the prize before updating; rules independently enforce ownership,
/// expiry and the single false/missing -> true transition atomically.
Future<void> claimMerchantPrize(PrizesRecord original) async {
  await FirebaseFirestore.instance.runTransaction((transaction) async {
    final snapshot = await transaction.get(original.reference);
    if (!snapshot.exists) throw StateError('Prize no longer exists');
    final current = PrizesRecord.fromSnapshot(snapshot);
    if (current.winnerId?.path != original.winnerId?.path ||
        !await canClaimMerchantPrize(current)) {
      throw StateError('Prize is no longer claimable by this merchant');
    }
    transaction.update(current.reference, {'claimed': true});
  });
}
