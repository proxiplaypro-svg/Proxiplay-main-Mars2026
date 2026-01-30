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
