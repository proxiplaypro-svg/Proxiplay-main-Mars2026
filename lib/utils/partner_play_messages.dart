import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Short invitations to the shop QR of this game, shown after a losing
/// classic play (see [mayInviteToShopQr]). The message does not change
/// participation rights.
const List<String> kPartnerPlayMessages = [
  'Et si vous alliez faire les boutiques ?',
  'Un QR code en boutique, une chance en plus !',
  'Et si vous découvriez de nouveaux commerces ?',
];

/// About one losing scratch out of [kPartnerPlayMessageOneIn].
const int kPartnerPlayMessageOneIn = 3;

/// Local USB/widget-test switch only. Production keeps the one-in-three draw
/// because an unset dart-define is always false in release builds.
const bool kForcePartnerPlayMessageForLocalTesting =
    bool.fromEnvironment('FORCE_PARTNER_PLAY_MESSAGE', defaultValue: false);

const String _kLastPartnerPlayMessageKey = 'partner_play_message_last_index';

/// Pure choice: null (no message) about two times out of three; otherwise a
/// random message different from [lastIndex].
int? pickPartnerPlayMessageIndex(Random random,
    {int? lastIndex, bool force = false}) {
  final gatePassed = force || random.nextInt(kPartnerPlayMessageOneIn) == 0;
  if (!gatePassed) {
    if (kDebugMode) {
      debugPrint(
          '[PARTNER_PLAY_TRACE] event=draw_completed forced=false selected=false');
    }
    return null;
  }
  final candidates = [
    for (var i = 0; i < kPartnerPlayMessages.length; i++)
      if (i != lastIndex) i,
  ];
  final index = candidates[random.nextInt(candidates.length)];
  if (kDebugMode) {
    debugPrint(
        '[PARTNER_PLAY_TRACE] event=draw_completed forced=$force selected=true messageIndex=$index');
  }
  return index;
}

/// Message for one losing scratch, or null. The last shown message is
/// remembered on the device so the same one never appears twice in a row.
/// Never throws: a storage error only means no message this time.
Future<String?> nextPartnerPlayMessage(
    {Random? random, SharedPreferences? prefs, bool? force}) async {
  try {
    final store = prefs ?? await SharedPreferences.getInstance();
    final index = pickPartnerPlayMessageIndex(
      random ?? Random(),
      lastIndex: store.getInt(_kLastPartnerPlayMessageKey),
      force: force ?? kForcePartnerPlayMessageForLocalTesting,
    );
    if (index == null) return null;
    await store.setInt(_kLastPartnerPlayMessageKey, index);
    return kPartnerPlayMessages[index];
  } catch (error) {
    if (kDebugMode) {
      debugPrint(
          '[PARTNER_PLAY_TRACE] event=selection_failed errorType=${error.runtimeType}');
    }
    return null;
  }
}
