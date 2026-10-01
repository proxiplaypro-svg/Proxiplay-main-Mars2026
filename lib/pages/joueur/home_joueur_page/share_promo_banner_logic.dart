import '/models/share_promo_models.dart';

/// Decides whether the "Aide un ami..." invite banner on the Home page
/// should be shown, based on `showBanner` as computed by the
/// getSharePromoState Cloud Function from app_config/share_promo
/// (enabled/isDraft/dates, or shareState rewardAvailable/pendingCount — see
/// firebase/functions/src/share_promo).
///
/// Fail-closed by design: this is a server-driven promotional banner, so it
/// only shows on an explicit, successfully fetched `showBanner == true`.
/// A `null` state — config not loaded yet, still loading, or the fetch
/// failed — hides it, same as a confirmed `showBanner == false`.
bool shouldShowHomeInviteBanner(SharePromoStateViewModel? state) {
  return state?.showBanner == true;
}
