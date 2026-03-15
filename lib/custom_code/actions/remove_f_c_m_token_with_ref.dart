// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_util.dart';
// Imports other custom actions
// Imports custom functions
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

Future<void> removeFCMTokenWithRef(DocumentReference userRef) async {
  final token = await FirebaseMessaging.instance.getToken();
  if (token == null) {
    return;
  }
  final tokenRef = userRef.collection('fcm_tokens').doc(token);
  await tokenRef.delete();
}
