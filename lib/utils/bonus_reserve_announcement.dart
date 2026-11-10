/// Annonce de la reserve de parties bonus (1.1.4), affichee une seule fois
/// par joueur sur l'accueil.
///
/// Memorisation locale, par compte (uid) et par appareil :
///  - une deconnexion ne l'efface pas : le meme compte ne la revoit pas ;
///  - un autre compte connecte sur le meme appareil la voit une fois ;
///  - sur un nouvel appareil (ou apres reinstallation), le joueur la revoit
///    une fois : c'est le choix d'un stockage local, sans ecriture serveur.
/// Aucun lien avec les regles de jeu : l'annonce n'ecrit rien dans Firestore.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String bonusReserveAnnouncementTitle =
    'Vos parties bonus restent à vous ! 🎉';
const String bonusReserveAnnouncementBody =
    'Bonne nouvelle ! Les parties bonus gagnées sur ProxiPlay sont désormais '
    'conservées, même après minuit. Cumulez-les et utilisez-les quand vous '
    'voulez, en plus de vos 3 parties quotidiennes.';
const String bonusReserveAnnouncementButton = 'Compris !';

const String _prefsKeyPrefix = 'bonus_reserve_announcement_1_1_4_seen/';

String bonusReserveAnnouncementPrefsKey(String accountId) =>
    '$_prefsKeyPrefix$accountId';

// Deja presentee pendant cette session de l'app : evite un double affichage
// si l'accueil est reconstruit avant la fin de l'ecriture locale.
final Set<String> _presentedThisSession = {};

/// Comptes a qui l'annonce ne s'adresse pas (pas de solde de parties).
bool isBonusReserveAnnouncementAudience({
  required String accountId,
  required bool isGuestOrAnonymous,
  String? userRole,
}) =>
    accountId.isNotEmpty &&
    !isGuestOrAnonymous &&
    userRole != 'commercant' &&
    userRole != 'admin';

/// Indique si l'annonce doit etre presentee maintenant a ce compte, et
/// l'enregistre comme vue. A appeler juste avant l'affichage.
/// Stockage indisponible : on ne l'affiche pas (jamais de rappel en boucle).
Future<bool> takeBonusReserveAnnouncement(String accountId) async {
  if (accountId.isEmpty || !_presentedThisSession.add(accountId)) {
    return false;
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = bonusReserveAnnouncementPrefsKey(accountId);
    if (prefs.getBool(key) == true) {
      return false;
    }
    await prefs.setBool(key, true);
    return true;
  } catch (_) {
    return false;
  }
}

@visibleForTesting
void resetBonusReserveAnnouncementSession() => _presentedThisSession.clear();
