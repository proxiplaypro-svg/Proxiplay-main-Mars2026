import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

Future initFirebase() async {
  if (kIsWeb) {
    await Firebase.initializeApp(
        options: const FirebaseOptions(
            apiKey: "AIzaSyC5BmWaTrmSP09kn7soHgBwpPwyopbDleY",
            authDomain: "proxi-play-odzp2e.firebaseapp.com",
            projectId: "proxi-play-odzp2e",
            storageBucket: "proxi-play-odzp2e.firebasestorage.app",
            messagingSenderId: "337086897094",
            appId: "1:337086897094:web:97a505ef0f0a0eea2bb0c7"));
  } else {
    await Firebase.initializeApp();
  }
}
