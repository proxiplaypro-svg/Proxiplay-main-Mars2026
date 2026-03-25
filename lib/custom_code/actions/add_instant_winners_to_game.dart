// Automatic FlutterFlow imports
import '/backend/backend.dart';
// Imports other custom actions
// Imports custom functions
// Begin custom action code
import 'package:flutter/foundation.dart';

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

  final prizeSlots = <Map<String, dynamic>>[];
  for (var prizeIndex = 0; prizeIndex < secondaryPrizes.length; prizeIndex++) {
    final rawPrize = secondaryPrizes[prizeIndex];
    if (rawPrize is! Map) {
      continue;
    }

    final prize = Map<String, dynamic>.from(rawPrize);
    final count = prize['count'] is num ? (prize['count'] as num).toInt() : 0;
    if (count <= 0) {
      continue;
    }

    final name = (prize['name'] ?? '').toString().trim();
    final presentation = (prize['presentation'] ?? '').toString().trim();
    final prizeLabel = name.isNotEmpty ? name : 'Lot secondaire ${prizeIndex + 1}';

    for (var occurrenceIndex = 0; occurrenceIndex < count; occurrenceIndex++) {
      prizeSlots.add({
        'prize': prizeLabel,
        'secondary_prize_index': prizeIndex,
        'secondary_prize_name': name,
        if (presentation.isNotEmpty) 'secondary_prize_presentation': presentation,
        'secondary_prize_occurrence': occurrenceIndex,
      });
    }
  }

  if (prizeSlots.isEmpty) {
    return;
  }

  final instantWinnersRef = gameRef.collection('instant_winners');
  final batch = FirebaseFirestore.instance.batch();
  final totalRangeMs =
      endDate.millisecondsSinceEpoch - startDate.millisecondsSinceEpoch;
  final numberOfWinners = prizeSlots.length;

  debugPrint(
    '[instant_winners][create] game=${gameRef.id} slots=${prizeSlots.length} payload=$prizeSlots',
  );

  for (int i = 0; i < numberOfWinners; i++) {
    // 1 instant gagnant par occurrence de lot secondaire, borne strictement entre start/end.
    final ratio = (i + 0.5) / numberOfWinners;
    final candidateMs =
        startDate.millisecondsSinceEpoch + (totalRangeMs * ratio).round();
    final boundedMs = candidateMs.clamp(
      startDate.millisecondsSinceEpoch,
      endDate.millisecondsSinceEpoch,
    );
    final winningDate = DateTime.fromMillisecondsSinceEpoch(boundedMs);
    final winnerRef = instantWinnersRef.doc();
    final slot = prizeSlots[i];

    batch.set(winnerRef, {
      'date': Timestamp.fromDate(winningDate),
      'hasWinner': false,
      'claimed': false,
      ...slot,
    });
  }

  await batch.commit();
}

