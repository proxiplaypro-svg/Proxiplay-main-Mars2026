// Automatic FlutterFlow imports
import '/backend/backend.dart';
// Imports other custom actions
// Imports custom functions
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

Future<void> addInstantWinnersToGame(
  DocumentReference gameRef,
  DateTime startDate,
  DateTime endDate,
  List<dynamic> secondaryPrizes,
) async {
  if (startDate.isAfter(endDate)) {
    throw Exception('La date de debut doit preceder la date de fin.');
  }

  final expandedSecondaryPrizes = <Map<String, dynamic>>[];
  for (var index = 0; index < secondaryPrizes.length; index++) {
    final rawPrize = secondaryPrizes[index];
    if (rawPrize is! Map) {
      continue;
    }

    final name = (rawPrize['name'] ?? '').toString().trim();
    final presentation = (rawPrize['presentation'] ?? '').toString().trim();
    final rawCount = rawPrize['count'];
    final count = rawCount is num
        ? rawCount.toInt()
        : int.tryParse(rawCount?.toString() ?? '') ?? 0;

    if (count <= 0) {
      continue;
    }

    for (var occurrence = 0; occurrence < count; occurrence++) {
      expandedSecondaryPrizes.add({
        'source_index': index,
        'occurrence_index': occurrence,
        'name': name,
        if (presentation.isNotEmpty) 'presentation': presentation,
      });
    }
  }

  final numberOfWinners = expandedSecondaryPrizes.length;
  if (numberOfWinners == 0) {
    return;
  }

  final instantWinnersRef = gameRef.collection('instant_winners');
  final batch = FirebaseFirestore.instance.batch();
  final totalRangeMs =
      endDate.millisecondsSinceEpoch - startDate.millisecondsSinceEpoch;

  for (int i = 0; i < numberOfWinners; i++) {
    final prizePayload = expandedSecondaryPrizes[i];
    // 1 instant gagnant par lot secondaire, borne strictement entre start/end.
    final ratio = (i + 0.5) / numberOfWinners;
    final candidateMs =
        startDate.millisecondsSinceEpoch + (totalRangeMs * ratio).round();
    final boundedMs = candidateMs.clamp(
      startDate.millisecondsSinceEpoch,
      endDate.millisecondsSinceEpoch,
    );
    final winningDate = DateTime.fromMillisecondsSinceEpoch(boundedMs);
    final winnerRef = instantWinnersRef.doc();

    batch.set(winnerRef, {
      'date': Timestamp.fromDate(winningDate),
      'hasWinner': false,
      'claimed': false,
      'secondary_prize_index': prizePayload['source_index'],
      'secondary_prize_occurrence_index': prizePayload['occurrence_index'],
      'secondary_prize_name': prizePayload['name'],
      if (prizePayload['presentation'] != null)
        'secondary_prize_presentation': prizePayload['presentation'],
    });
  }

  await batch.commit();
}
