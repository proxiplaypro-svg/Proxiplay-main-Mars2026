import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC5BmWaTrmSP09kn7soHgBwpPwyopbDleY',
    authDomain: 'proxi-play-odzp2e.firebaseapp.com',
    projectId: 'proxi-play-odzp2e',
    storageBucket: 'proxi-play-odzp2e.firebasestorage.app',
    messagingSenderId: '337086897094',
    appId: '1:337086897094:web:97a505ef0f0a0eea2bb0c7',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBmHXWsaD3UDvmYOX3aSFGT-rgf_lrBiQY',
    appId: '1:337086897094:android:2b0e389e68cb7ad42bb0c7',
    messagingSenderId: '337086897094',
    projectId: 'proxi-play-odzp2e',
    storageBucket: 'proxi-play-odzp2e.firebasestorage.app',
  );
}
