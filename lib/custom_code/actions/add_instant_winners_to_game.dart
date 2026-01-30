// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

Future<void> addInstantWinnersToGame(
  DocumentReference gameRef,
  DateTime startDate,
  DateTime endDate,
  int numberOfWinners,
) async {
  if (startDate.isAfter(endDate)) {
    throw Exception("La date de début doit précéder la date de fin.");
  }

  final instantWinnersRef = gameRef.collection('instant_winners');

  for (int i = 0; i < numberOfWinners; i++) {
    final randomMillis = startDate.millisecondsSinceEpoch +
        (DateTimeRange(start: startDate, end: endDate).duration.inMilliseconds *
                (0.1 + (0.8 * (i / numberOfWinners))))
            .toInt();

    final randomDate = DateTime.fromMillisecondsSinceEpoch(randomMillis +
        (DateTime.now().millisecondsSinceEpoch % 100000)); // pour + d'aléa

    await instantWinnersRef.add({
      'date': Timestamp.fromDate(randomDate),
      'hasWinner': false,
      'claimed': false,
    });
  }
}
