// Automatic FlutterFlow imports
// Imports other custom actions
// Imports custom functions
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:share_plus/share_plus.dart';

Future shareAppStoreLink() async {
  // Add your function code here!
  //   // Remplacez ces liens par les vrais liens de votre application sur les stores
  const String androidAppStoreLink =
      'https://play.google.com/store/apps/details?id=votre.package.name';
  const String iosAppStoreLink =
      'https://apps.apple.com/fr/app/idVOTREAPPPLEID'; // Remplacez VOTREAPPPLEID par l'ID de votre app

  // Le message de partage inclut directement les deux liens
  const String shareText = "Découvrez ma super application !\n\n"
      "Android: $androidAppStoreLink\n"
      "iOS: $iosAppStoreLink";

  await Share.share(shareText, subject: 'Partage de mon application');
}
