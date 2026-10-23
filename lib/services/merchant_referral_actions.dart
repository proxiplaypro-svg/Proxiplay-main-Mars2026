import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '/utils/merchant_referral_utils.dart';

Future<bool> copyMerchantReferralCode(String? code) async {
  if (!isValidMerchantReferralCode(code)) return false;
  await Clipboard.setData(ClipboardData(text: code!));
  return true;
}

Future<bool> shareMerchantReferralCode(String? code, {Rect? origin}) async {
  if (!isValidMerchantReferralCode(code)) return false;
  await Share.share(buildMerchantReferralShareText(code!),
      subject: 'Parrainez un commerçant sur ProxiPlay',
      sharePositionOrigin: origin);
  return true;
}
