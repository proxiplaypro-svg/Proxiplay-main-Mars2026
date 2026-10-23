import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Short messages shown after a losing scratch, inviting the player to play
/// at a ProxiPlay partner (shop, craftsman or service provider, with or
/// without premises). Never promises unlimited plays nor a new play on the
/// same game the same day.
const List<String> kPartnerPlayMessages = [
  'Pas gagné ? Retentez votre chance chez un partenaire !',
  'Des parties supplémentaires chez nos partenaires !',
  'Plus de chances ? Jouez encore chez nos partenaires !',
  'Scannez un QR code partenaire pour jouer gratuitement !',
  'Vos 3 chances sont épuisées ? Scannez chez un partenaire !',
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
