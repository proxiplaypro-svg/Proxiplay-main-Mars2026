// Automatic FlutterFlow imports
// Imports other custom actions
// Imports custom functions
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:share_plus/share_plus.dart';

import '/utils/share_links.dart';

Future shareAppStoreLink() async {
  final shareText = buildAppShareText();

  await Share.share(shareText, subject: 'Partage ProxiPlay');
}
