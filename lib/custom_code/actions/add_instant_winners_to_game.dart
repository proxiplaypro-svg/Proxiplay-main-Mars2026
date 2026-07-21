// Automatic FlutterFlow imports
import 'package:cloud_functions/cloud_functions.dart';

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
  await FirebaseFunctions.instance
      .httpsCallable('generateInstantWinnersForGame')
      .call({
    'gameId': gameRef.id,
  });
}
