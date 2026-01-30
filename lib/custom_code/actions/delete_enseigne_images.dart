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

import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;

Future<void> deleteEnseigneImages(DocumentReference refEnseigne) async {
  // Add your function code here!
  try {
    //Accès à la sous-collection "images"
    CollectionReference imageCollection = refEnseigne.collection('images');

    // Récupérer toutes les images de l'enseigne
    QuerySnapshot imageDocs = await imageCollection.get();

    if (imageDocs.docs.isEmpty) {
      print("✅ Aucune image trouvée pour cette enseigne.");
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

          print("Suppression de l'image : $filePath");
          await firebase_storage.FirebaseStorage.instance
              .ref(filePath)
              .delete();
        } catch (e) {
          print("Erreur de suppression de l'image : $e");
        }
      }

      //  Supprimer le document de Firestore
      await doc.reference.delete();
    }

    // Supprimer ensuite l'enseigne après suppression des images
    // await refEnseigne.delete();

    print(" Enseigne et images supprimées avec succès.");
  } catch (e) {
    print(" Erreur lors de la suppression des images et de l'enseigne : $e");
  }
}
