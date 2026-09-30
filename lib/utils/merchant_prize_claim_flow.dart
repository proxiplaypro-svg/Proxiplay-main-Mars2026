/// Local UI guard around the existing protected claim transaction.
/// It never changes the prize itself; only a completed backend transaction can
/// move this flow to [isClaimed].
class MerchantPrizeClaimFlow {
  bool _isSubmitting = false;
  bool _isClaimed = false;

  bool get isSubmitting => _isSubmitting;
  bool get isClaimed => _isClaimed;

  bool start() {
    if (_isSubmitting || _isClaimed) return false;
    _isSubmitting = true;
    return true;
  }

  void succeed() {
    _isClaimed = true;
    _isSubmitting = false;
  }

  void fail() => _isSubmitting = false;
}
