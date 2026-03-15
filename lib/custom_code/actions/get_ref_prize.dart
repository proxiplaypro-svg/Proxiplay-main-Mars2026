// Automatic FlutterFlow imports
import '/backend/backend.dart';
// Imports other custom actions
// Imports custom functions
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:flutter/foundation.dart' show debugPrint;

Future<PrizesRecord?> getRefPrize(String refPrize) async {
  if (refPrize.isEmpty) {
    throw Exception('refPrize est vide !');
  }

  debugPrint('Recuperation du document: $refPrize');

  // Recuperer la reference du document
  DocumentReference docRef = FirebaseFirestore.instance.doc(refPrize);

  try {
    // Lire le document Firestore
    DocumentSnapshot docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      debugPrint('Document trouve.');
      return PrizesRecord.fromSnapshot(docSnapshot);
    } else {
      debugPrint('Document non trouve.');
      return null;
    }
  } catch (e) {
    debugPrint('Erreur lors de la recuperation du document: $e');
    return null;
  }
}
