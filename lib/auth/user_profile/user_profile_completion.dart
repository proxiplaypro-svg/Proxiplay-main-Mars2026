import 'package:cloud_firestore/cloud_firestore.dart';

import '/backend/schema/enums/enums.dart';
import '/backend/schema/users_record.dart';

const int kCurrentUserProfileSchemaVersion = 1;

String normalizeUserProfileText(String? value) => value?.trim() ?? '';

bool hasMeaningfulUserProfileText(String? value) =>
    normalizeUserProfileText(value).isNotEmpty;

String buildDisplayNameFromProfileNames({
  required String? firstName,
  required String? lastName,
}) {
  final normalizedFirstName = normalizeUserProfileText(firstName);
  final normalizedLastName = normalizeUserProfileText(lastName);
  return [normalizedFirstName, normalizedLastName]
      .where((part) => part.isNotEmpty)
      .join(' ')
      .trim();
}

class TemporaryNamePrefill {
  const TemporaryNamePrefill({
    required this.firstName,
    required this.lastName,
  });

  final String firstName;
  final String lastName;
}

TemporaryNamePrefill? buildTemporaryNamePrefillFromDisplayName(
  String? displayName,
) {
  final normalizedDisplayName = normalizeUserProfileText(displayName);
  if (normalizedDisplayName.isEmpty) {
    return null;
  }

  final parts = normalizedDisplayName
      .split(RegExp(r'\s+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 2) {
    return null;
  }

  return TemporaryNamePrefill(
    firstName: parts.first,
    lastName: parts.sublist(1).join(' '),
  );
}

bool isUserProfileCompleteForRole({
  required Roles? role,
  required String? firstName,
  required String? lastName,
  required String? phoneNumber,
  required String? city,
  required DateTime? birthday,
}) {
  if (role == null || role == Roles.admin) {
    return true;
  }

  final hasFirstName = hasMeaningfulUserProfileText(firstName);
  final hasLastName = hasMeaningfulUserProfileText(lastName);
  final hasPhoneNumber = hasMeaningfulUserProfileText(phoneNumber);
  final hasCity = hasMeaningfulUserProfileText(city);
  final hasBirthday = role == Roles.joueur ? birthday != null : true;

  return hasFirstName &&
      hasLastName &&
      hasPhoneNumber &&
      hasCity &&
      hasBirthday;
}

bool isUserProfileComplete(UsersRecord? user) {
  if (user == null) {
    return false;
  }

  return isUserProfileCompleteForRole(
    role: user.userRole,
    firstName: user.firstName,
    lastName: user.lastName,
    phoneNumber: user.phoneNumber,
    city: user.city,
    birthday: user.birthday,
  );
}

bool isUserProfileCompleteFromData(
  Map<String, dynamic>? data, {
  required Roles? role,
}) {
  final safeData = data ?? const <String, dynamic>{};
  final birthday = safeData['birthday'];

  return isUserProfileCompleteForRole(
    role: role,
    firstName: safeData['first_name'] as String?,
    lastName: safeData['last_name'] as String?,
    phoneNumber: safeData['phone_number'] as String?,
    city: safeData['city'] as String?,
    birthday: birthday is Timestamp
        ? birthday.toDate()
        : birthday is DateTime
            ? birthday
            : null,
  );
}

bool shouldRequireProfileCompletion({
  required Roles? role,
  required int? profileSchemaVersion,
  required bool? profileCompleted,
  required bool isProfileComplete,
}) {
  if (role == null || role == Roles.admin) {
    return false;
  }

  if ((profileSchemaVersion ?? 0) >= kCurrentUserProfileSchemaVersion) {
    return profileCompleted != true || !isProfileComplete;
  }

  return profileCompleted == false;
}

bool shouldRequireUserProfileCompletion(UsersRecord? user) {
  if (user == null) {
    return false;
  }

  return shouldRequireProfileCompletion(
    role: user.userRole,
    profileSchemaVersion: user.profileSchemaVersion,
    profileCompleted: user.hasProfileCompleted() ? user.profileCompleted : null,
    isProfileComplete: isUserProfileComplete(user),
  );
}

bool shouldRequireUserProfileCompletionFromData(
  Map<String, dynamic>? data, {
  required Roles? role,
}) {
  final safeData = data ?? const <String, dynamic>{};

  return shouldRequireProfileCompletion(
    role: role,
    profileSchemaVersion: safeData['profile_schema_version'] is num
        ? (safeData['profile_schema_version'] as num).toInt()
        : null,
    profileCompleted: safeData['profile_completed'] is bool
        ? safeData['profile_completed'] as bool
        : null,
    isProfileComplete: isUserProfileCompleteFromData(
      safeData,
      role: role,
    ),
  );
}
