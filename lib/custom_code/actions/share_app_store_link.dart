// Automatic FlutterFlow imports
// Imports other custom actions
// Imports custom functions
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:share_plus/share_plus.dart';

import '/utils/share_links.dart';

Future shareAppStoreLink() async {
  final shareText = buildAppShareText(
    title: 'Decouvrez ProxiPlay',
    description: 'Rejoignez-moi sur ProxiPlay avec ce lien.',
  );

  await Share.share(shareText, subject: 'Partage de ProxiPlay');
}
