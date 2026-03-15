// Automatic FlutterFlow imports
import '/backend/backend.dart';
// Imports other custom actions
// Imports custom functions
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

Future<void> associateFCMTokenWithDevice(
  DocumentReference userRef,
  String deviceType,
) async {
  // 1) Récupérer le token FCM depuis Firebase Messaging
  final token = await FirebaseMessaging.instance.getToken();
  if (token == null) {
    // L'utilisateur n'a peut-être pas autorisé les notifications,
    // ou un problème est survenu.
    return;
  }

  // 2) Référence du document dans la sous-collection "fcm_tokens"
  // On utilise le token comme ID du document (tu peux aussi générer un ID random)
  final tokenRef = userRef.collection('fcm_tokens').doc(token);

  // 3) Écriture du document
  await tokenRef.set({
    'created_at': FieldValue.serverTimestamp(),
    'fcm_token': token, // On stocke la valeur du token FCM
    'device_type': deviceType, // iOS, Android, Web, etc.
  });
}
