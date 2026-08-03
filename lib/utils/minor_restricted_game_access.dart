enum MinorRestrictedGameAccessStatus {
  allowed,
  birthdayRequired,
  underage,
}

bool isAdult(
  DateTime birthday, {
  DateTime? today,
}) {
  final currentDate = today ?? DateTime.now();
  var age = currentDate.year - birthday.year;
  final birthdayReachedThisYear = currentDate.month > birthday.month ||
      (currentDate.month == birthday.month && currentDate.day >= birthday.day);
  if (!birthdayReachedThisYear) {
    age -= 1;
  }
  return age >= 18;
}

MinorRestrictedGameAccessStatus resolveMinorRestrictedGameAccess({
  required bool prohibitedForMinors,
  required DateTime? birthday,
  DateTime? today,
}) {
  if (!prohibitedForMinors) {
    return MinorRestrictedGameAccessStatus.allowed;
  }
  if (birthday == null) {
    return MinorRestrictedGameAccessStatus.birthdayRequired;
  }
  return isAdult(
    birthday,
    today: today,
  )
      ? MinorRestrictedGameAccessStatus.allowed
      : MinorRestrictedGameAccessStatus.underage;
}

bool canPlayMinorRestrictedGame({
  required bool prohibitedForMinors,
  required DateTime? birthday,
  DateTime? today,
}) {
  return resolveMinorRestrictedGameAccess(
        prohibitedForMinors: prohibitedForMinors,
        birthday: birthday,
        today: today,
      ) ==
      MinorRestrictedGameAccessStatus.allowed;
}
