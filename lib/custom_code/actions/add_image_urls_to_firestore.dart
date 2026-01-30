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

Future<void> addImageUrlsToFirestore(
  DocumentReference refEnseigne,
  List<String> listUrl,
) async {
  // Obtenir une référence à la sous-collection 'image' du document enseigne
  CollectionReference imageCollection = refEnseigne.collection('images');

  // Utiliser un `for` pour garantir la gestion correcte des appels async
  for (String url in listUrl) {
    await imageCollection.add({
      'url': url,
    });
  }
}
