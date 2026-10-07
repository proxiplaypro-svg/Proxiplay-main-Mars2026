// Systeme publicitaire ProxiPlay (vendu en direct, pas AdMob). Fonctions
// pures, testables sans Firebase ni widget -- voir test/ad_system_utils_test.dart.
//
// Fail-open par design pour l'interstitiel d'ouverture (ads/open) : toute
// ambiguite (champ absent, horodatage invalide) doit faire pencher vers
// "ne pas bloquer l'acces a ProxiPlay", jamais l'inverse.

/// Un placement est eligible si explicitement active ET dans sa fenetre de
/// diffusion (bornes optionnelles). `enabled` absent/non-true -> jamais
/// eligible (fail-closed sur l'activation, qui est le comportement
/// attendu : une pub non configuree ne doit jamais s'afficher).
bool isAdPlacementEnabled({
  required bool? enabled,
  required DateTime? startAt,
  required DateTime? endAt,
  required DateTime now,
}) {
  if (enabled != true) {
    return false;
  }
  if (startAt != null && now.isBefore(startAt)) {
    return false;
  }
  if (endAt != null && now.isAfter(endAt)) {
    return false;
  }
  return true;
}

/// Plafond de frequence de l'interstitiel d'ouverture : vrai si on peut
/// (re)montrer la pub maintenant. Fail-open : pas de plafond configure, ou
/// jamais montree -> autorise. Un plafond a 0 signifie explicitement qu'il
/// n'y a aucun delai entre deux lancements a froid. Une valeur negative reste
/// fail-open pour ne jamais bloquer l'acces a ProxiPlay.
bool isOpenAdFrequencyElapsed({
  required DateTime? lastShownAt,
  required int? frequencyCapHours,
  required DateTime now,
}) {
  if (lastShownAt == null) {
    return true;
  }
  if (frequencyCapHours == null || frequencyCapHours == 0) {
    return true;
  }
  if (frequencyCapHours < 0) {
    return true;
  }
  final nextEligibleAt =
      lastShownAt.add(Duration(hours: frequencyCapHours));
  return !now.isBefore(nextEligibleAt);
}

/// Decision complete pour l'interstitiel d'ouverture (activation + fenetre
/// + frequence). Ne verifie PAS que l'image a ete chargee avec succes :
/// c'est au code appelant de ne jamais afficher sans image prete, et de
/// fail-open (ne rien afficher) si le chargement echoue ou depasse le
/// delai imparti.
bool shouldShowOpenAd({
  required bool? enabled,
  required DateTime? startAt,
  required DateTime? endAt,
  required DateTime? lastShownAt,
  required int? frequencyCapHours,
  required DateTime now,
}) {
  return isAdPlacementEnabled(
        enabled: enabled,
        startAt: startAt,
        endAt: endAt,
        now: now,
      ) &&
      isOpenAdFrequencyElapsed(
        lastShownAt: lastShownAt,
        frequencyCapHours: frequencyCapHours,
        now: now,
      );
}
