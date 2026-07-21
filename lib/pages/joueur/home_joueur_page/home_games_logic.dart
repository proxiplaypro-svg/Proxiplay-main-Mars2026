bool isPlayerHomeGameVisible({
  required DateTime now,
  required String animationId,
  required DateTime? startDate,
  required DateTime? endDate,
}) {
  if (animationId.trim().isNotEmpty) {
    return false;
  }
  if (endDate == null || !endDate.isAfter(now)) {
    return false;
  }
  if (startDate != null && now.isBefore(startDate)) {
    return false;
  }
  return true;
}
