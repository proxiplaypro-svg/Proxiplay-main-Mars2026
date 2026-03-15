// Automatic FlutterFlow imports
// Imports other custom actions
// Imports custom functions
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:share_plus/share_plus.dart';

import '/services/referral/referral_service.dart';

Future shareAppStoreLink() async {
  final referralService = ReferralService();
  final shareText = referralService.buildAppShareText();

  await Share.share(shareText, subject: 'Partage ProxiPlay');
}

