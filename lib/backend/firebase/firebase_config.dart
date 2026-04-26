import 'package:firebase_core/firebase_core.dart';
import '/firebase_options.dart';

Future initFirebase() async {
  final app = await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final options = app.options;
  print(
    'FIREBASE INIT projectId=${options.projectId} '
    'appId=${options.appId} '
    'messagingSenderId=${options.messagingSenderId}',
  );
}
