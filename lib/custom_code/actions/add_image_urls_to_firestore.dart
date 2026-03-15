// Automatic FlutterFlow imports
import '/backend/backend.dart';
// Imports other custom actions
// Imports custom functions
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
