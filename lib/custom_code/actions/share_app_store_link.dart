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

import 'package:share_plus/share_plus.dart';

Future shareAppStoreLink() async {
  // Add your function code here!
  //   // Remplacez ces liens par les vrais liens de votre application sur les stores
  final String androidAppStoreLink =
      'https://play.google.com/store/apps/details?id=votre.package.name';
  final String iosAppStoreLink =
      'https://apps.apple.com/fr/app/idVOTREAPPPLEID'; // Remplacez VOTREAPPPLEID par l'ID de votre app

  // Le message de partage inclut directement les deux liens
  final String shareText = "Découvrez ma super application !\n\n"
      "Android: $androidAppStoreLink\n"
      "iOS: $iosAppStoreLink";

  await Share.share(shareText, subject: 'Partage de mon application');
}
