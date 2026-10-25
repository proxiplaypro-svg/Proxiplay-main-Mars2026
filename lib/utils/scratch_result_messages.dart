// Messages shown under a losing scratch (validated 26/10/2026). Instant
// wins show the prize name sent by the server; status messages (already
// played, no more chances) are unchanged.

/// A loss in a game the player is now entered in for its final draw.
const List<String> kDrawLossMessages = [
  "C'est joué ! Rendez-vous au tirage final.",
  'Ta participation est enregistrée. Bonne chance !',
  'Pas de gain immédiat, mais tout reste possible !',
  'Ton ticket est dans la course. Croise les doigts !',
  "Le suspense continue jusqu'au tirage final !",
  "Une chance de gagner au tirage final, c'est déjà ça !",
];

/// A loss in a game without a final draw.
const List<String> kInstantLossMessages = [
  'Pas cette fois… mais demain est un autre jour !',
  "La chance n'était pas au rendez-vous. À demain !",
  "Raté pour aujourd'hui, mais garde le sourire !",
  "Ce n'est pas gagné… pour cette fois !",
  "Merci d'avoir joué ! Reviens tenter ta chance demain.",
  "Pas de lot aujourd'hui, mais le jeu continue !",
];

/// Every participation in a main-prize game is one draw ticket, so the
/// draw messages appear only when the game is known to have a main prize
/// (`null`, an older game not yet backfilled, is treated as no draw).
List<String> lossMessagePool({required bool? hasMainPrize}) =>
    hasMainPrize == true ? kDrawLossMessages : kInstantLossMessages;

/// Whether the result screen may invite the player to the shop QR: only
/// after a new, losing classic play, when the game page knew the extra QR
/// play was still available ([shopQrPlayAvailable]). Never after the QR
/// play itself, nor on a replayed result.
bool mayInviteToShopQr({
  required bool shopQrPlayAvailable,
  required bool isWin,
  required bool isReplay,
}) =>
    shopQrPlayAvailable && !isWin && !isReplay;
