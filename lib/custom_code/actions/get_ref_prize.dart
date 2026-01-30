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

Future<PrizesRecord?> getRefPrize(String refPrize) async {
  if (refPrize.isEmpty) {
    throw Exception("⚠️ refPrize est vide !");
  }

  print("📌 Récupération du document: $refPrize");

  // Récupérer la référence du document
  DocumentReference docRef = FirebaseFirestore.instance.doc(refPrize);

  try {
    // Lire le document Firestore
    DocumentSnapshot docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      print("✅ Document trouvé !");
      return PrizesRecord.fromSnapshot(docSnapshot); // ✅ Conversion correcte
    } else {
      print("⚠️ Document non trouvé !");
      return null;
    }
  } catch (e) {
    print("❌ Erreur lors de la récupération du document: $e");
    return null;
  }
}
