/// Decide si le bloc "Parrainez un commercant" (bas de la Home) doit
/// s'afficher, a partir de `app_config/merchant_referral.enabled`.
///
/// Fail-closed par design, comme shouldShowHomeInviteBanner (voir
/// share_promo_banner_logic.dart) : un etat `null` -- config pas encore
/// chargee, en cours de chargement, ou echec de lecture -- masque le bloc,
/// au meme titre qu'un `enabled == false` confirme. En cas de
/// desactivation, le bloc disparait completement (aucun espace reserve).
bool shouldShowMerchantReferralBanner(bool? enabled) {
  return enabled == true;
}
