// Automatic FlutterFlow imports
import '/backend/backend.dart';
// Imports other custom actions
// Imports custom functions
import 'package:flutter/foundation.dart' show debugPrint;
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;

Future<void> deleteEnseigneImages(DocumentReference refEnseigne) async {
  // Add your function code here!
  try {
    //Accès à la sous-collection "images"
    CollectionReference imageCollection = refEnseigne.collection('images');

    // Récupérer toutes les images de l'enseigne
    QuerySnapshot imageDocs = await imageCollection.get();

    if (imageDocs.docs.isEmpty) {
      debugPrint("✅ Aucune image trouvée pour cette enseigne.");
      return;
    }

    // Parcourir chaque document et supprimer l'image de Firebase Storage
    for (QueryDocumentSnapshot doc in imageDocs.docs) {
      Map<String, dynamic> imageData = doc.data() as Map<String, dynamic>;
      String? imageUrl = imageData['url'];

      if (imageUrl != null) {
        try {
          // Récupérer le chemin de l'image dans Firebase Storage
          String filePath =
              Uri.decodeFull(imageUrl.split('/o/')[1].split('?alt=media')[0]);

          debugPrint("Suppression de l'image : $filePath");
          await firebase_storage.FirebaseStorage.instance
              .ref(filePath)
              .delete();
        } catch (e) {
          debugPrint("Erreur de suppression de l'image : $e");
        }
      }

      //  Supprimer le document de Firestore
      await doc.reference.delete();
    }

    // Supprimer ensuite l'enseigne après suppression des images
    // await refEnseigne.delete();

    debugPrint(" Enseigne et images supprimées avec succès.");
  } catch (e) {
    debugPrint(" Erreur lors de la suppression des images et de l'enseigne : $e");
  }
}
