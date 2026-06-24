import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import '/firebase_options.dart';

Future initFirebase() async {
  final app = await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final options = app.options;
  debugPrint(
    'FIREBASE INIT projectId=${options.projectId} '
    'appId=${options.appId} '
    'messagingSenderId=${options.messagingSenderId}',
  );

  // Persistance locale : évite de re-télécharger les collections à chaque
  // démarrage et permet un accès hors ligne. Désactivé sur Web (non supporté).
  if (!kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }
}
