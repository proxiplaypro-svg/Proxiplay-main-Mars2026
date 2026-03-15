// Automatic FlutterFlow imports
import '/backend/backend.dart';
// Imports other custom actions
// Imports custom functions
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
