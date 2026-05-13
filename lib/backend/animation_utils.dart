import '/backend/backend.dart';

Future<bool> updateAnimationProgress(
  String uid,
  GamesRecord game,
) async {
  final animationId = game.animationId.trim();
  final merchantId = game.enseigneId?.id;

  if (uid.isEmpty ||
      animationId.isEmpty ||
      merchantId == null ||
      merchantId.isEmpty) {
    return false;
  }

  final firestore = FirebaseFirestore.instance;
  final animationRef = AnimationsRecord.collection.doc(animationId);
  final progressRef =
      firestore.collection('users').doc(uid).collection('animations').doc(animationId);

  return firestore.runTransaction((transaction) async {
    final animationSnapshot = await transaction.get(animationRef);
    final progressSnapshot = await transaction.get(progressRef);

    final animationDataRaw = animationSnapshot.data();
    final animationData = animationDataRaw is Map<String, dynamic>
        ? animationDataRaw
        : <String, dynamic>{};
    final progressDataRaw = progressSnapshot.data();
    final progressData = progressDataRaw is Map<String, dynamic>
        ? progressDataRaw
        : <String, dynamic>{};

    final animation =
        AnimationsRecord.getDocumentFromData(animationData, animationRef);
    final threshold = animation.threshold;

    final rawVisitedMerchants = progressData['visited_merchants'];
    final visitedMerchants = rawVisitedMerchants is Iterable
        ? rawVisitedMerchants.map((value) => value.toString()).toList()
        : <String>[];
    final qualified = progressData['qualified'] == true;
    final alreadyVisited = visitedMerchants.contains(merchantId);
    final updatedCount =
        alreadyVisited ? visitedMerchants.length : visitedMerchants.length + 1;
    final newlyQualified =
        !qualified && !alreadyVisited && updatedCount >= threshold;

    final updates = <String, dynamic>{
      'last_updated': Timestamp.now(),
      if (!alreadyVisited) 'visited_merchants': FieldValue.arrayUnion([merchantId]),
      if (newlyQualified) 'qualified': true,
    };

    transaction.set(progressRef, updates, SetOptions(merge: true));

    return newlyQualified;
  });
}
