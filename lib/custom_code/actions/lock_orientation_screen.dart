// Automatic FlutterFlow imports
// Imports other custom actions
// Imports custom functions
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:flutter/services.dart';

// Set your action name, define your arguments and return parameter,
// and then add the boilerplate code using the green button on the right!// Automatic FlutterFlow imports

// je veux bloquer la rotation de l'ecran a la vertical dans toute l'app

Future lockOrientationScreen() async {
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
}
