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
  int numberOfWinners,
) async {
  if (startDate.isAfter(endDate)) {
    throw Exception('La date de debut doit preceder la date de fin.');
  }
  if (numberOfWinners < 0) {
    throw Exception("Le nombre d'instants gagnants ne peut pas etre negatif.");
  }
  if (numberOfWinners == 0) {
    return;
  }

  final instantWinnersRef = gameRef.collection('instant_winners');
  final batch = FirebaseFirestore.instance.batch();
  final totalRangeMs =
      endDate.millisecondsSinceEpoch - startDate.millisecondsSinceEpoch;

  for (int i = 0; i < numberOfWinners; i++) {
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
    });
  }

  await batch.commit();
}
