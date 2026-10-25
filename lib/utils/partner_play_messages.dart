import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Short invitations to the shop QR of this game, shown after a losing
/// classic play while its extra QR play is still available (see
/// mayInviteToShopQr). Never promises unlimited plays.
const List<String> kPartnerPlayMessages = [
  'Passe sur place et scanne le QR pour rejouer !',
  "Pas gagné ? Une nouvelle chance t'attend sur place !",
  'Envie de retenter ta chance ? Scanne le QR sur place !',
];

/// About one losing scratch out of [kPartnerPlayMessageOneIn].
const int kPartnerPlayMessageOneIn = 3;

const String _kLastPartnerPlayMessageKey = 'partner_play_message_last_index';

/// Pure choice: null (no message) about two times out of three; otherwise a
/// random message different from [lastIndex].
int? pickPartnerPlayMessageIndex(Random random, {int? lastIndex}) {
  if (random.nextInt(kPartnerPlayMessageOneIn) != 0) return null;
  final candidates = [
    for (var i = 0; i < kPartnerPlayMessages.length; i++)
      if (i != lastIndex) i,
  ];
  return candidates[random.nextInt(candidates.length)];
}

/// Message for one losing scratch, or null. The last shown message is
/// remembered on the device so the same one never appears twice in a row.
/// Never throws: a storage error only means no message this time.
Future<String?> nextPartnerPlayMessage({Random? random, SharedPreferences? prefs}) async {
  try {
    final store = prefs ?? await SharedPreferences.getInstance();
    final index = pickPartnerPlayMessageIndex(
      random ?? Random(),
      lastIndex: store.getInt(_kLastPartnerPlayMessageKey),
    );
    if (index == null) return null;
    await store.setInt(_kLastPartnerPlayMessageKey, index);
    return kPartnerPlayMessages[index];
  } catch (_) {
    return null;
  }
}
