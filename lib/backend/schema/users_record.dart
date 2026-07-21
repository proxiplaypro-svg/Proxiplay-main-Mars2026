import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/enums/enums.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class UsersRecord extends FirestoreRecord {
  UsersRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // "email" field.
  String? _email;
  String get email => _email ?? '';
  bool hasEmail() => _email != null;

  // "uid" field.
  String? _uid;
  String get uid => _uid ?? '';
  bool hasUid() => _uid != null;

  // "created_time" field.
  DateTime? _createdTime;
  DateTime? get createdTime => _createdTime;
  bool hasCreatedTime() => _createdTime != null;

  // "phone_number" field.
  String? _phoneNumber;
  String get phoneNumber => _phoneNumber ?? '';
  bool hasPhoneNumber() => _phoneNumber != null;

  // "first_name" field.
  String? _firstName;
  String get firstName => _firstName ?? '';
  bool hasFirstName() => _firstName != null;

  // "last_name" field.
  String? _lastName;
  String get lastName => _lastName ?? '';
  bool hasLastName() => _lastName != null;

  // "pseudo" field.
  String? _pseudo;
  String get pseudo => _pseudo ?? '';
  String get firstNameAndLastName => '$firstName $lastName';
  bool hasPseudo() => _pseudo != null;

  // "account_status" field.
  AccountStatus? _accountStatus;
  AccountStatus? get accountStatus => _accountStatus;
  bool hasAccountStatus() => _accountStatus != null;

  // "user_role" field.
  Roles? _userRole;
  Roles? get userRole => _userRole;
  bool hasUserRole() => _userRole != null;

  // "display_name" field.
  String? _displayName;
  String get displayName => _displayName ?? '';
  bool hasDisplayName() => _displayName != null;

  // "photo_url" field.
  String? _photoUrl;
  String get photoUrl => _photoUrl ?? '';
  bool hasPhotoUrl() => _photoUrl != null;

  // "remaining_part" field.
  int? _remainingPart;
  int get remainingPart => _remainingPart ?? 0;
  bool hasRemainingPart() => _remainingPart != null;

  // "city" field.
  String? _city;
  String get city => _city ?? '';
  bool hasCity() => _city != null;

  // "city_insee_code" field.
  String? _cityInseeCode;
  String get cityInseeCode => _cityInseeCode ?? '';
  bool hasCityInseeCode() => _cityInseeCode != null;

  // "part_last_update" field.
  DateTime? _partLastUpdate;
  DateTime? get partLastUpdate => _partLastUpdate;
  bool hasPartLastUpdate() => _partLastUpdate != null;

  // "birthday" field.
  DateTime? _birthday;
  DateTime? get birthday => _birthday;
  bool hasBirthday() => _birthday != null;

  // "professional_category" field.
  String? _professionalCategory;
  String get professionalCategory => _professionalCategory ?? '';
  bool hasProfessionalCategory() => _professionalCategory != null;

  // "allGamesAccessUntil" field.
  DateTime? _allGamesAccessUntil;
  DateTime? get allGamesAccessUntil => _allGamesAccessUntil;
  bool hasAllGamesAccessUntil() => _allGamesAccessUntil != null;

  // "last_real_activity_at" field.
  DateTime? _lastRealActivityAt;
  DateTime? get lastRealActivityAt => _lastRealActivityAt;
  bool hasLastRealActivityAt() => _lastRealActivityAt != null;

  // "games_played_count" field.
  int? _gamesPlayedCount;
  int get gamesPlayedCount => _gamesPlayedCount ?? 0;
  bool hasGamesPlayedCount() => _gamesPlayedCount != null;

  // "player_status_cached" field.
  String? _playerStatusCached;
  String get playerStatusCached => _playerStatusCached ?? 'statut_inconnu';
  bool hasPlayerStatusCached() => _playerStatusCached != null;

  // "last_inactive_relaunch_at" field.
  DateTime? _lastInactiveRelaunchAt;
  DateTime? get lastInactiveRelaunchAt => _lastInactiveRelaunchAt;
  bool hasLastInactiveRelaunchAt() => _lastInactiveRelaunchAt != null;

  void _initializeFields() {
    _email = snapshotData['email'] as String?;
    _uid = snapshotData['uid'] as String?;
    _createdTime = snapshotData['created_time'] as DateTime?;
    _phoneNumber = snapshotData['phone_number'] as String?;
    _firstName = snapshotData['first_name'] as String?;
    _lastName = snapshotData['last_name'] as String?;
    _pseudo = snapshotData['pseudo'] as String?;
    _accountStatus = snapshotData['account_status'] is AccountStatus
        ? snapshotData['account_status']
        : deserializeEnum<AccountStatus>(snapshotData['account_status']);
    _userRole = snapshotData['user_role'] is Roles
        ? snapshotData['user_role']
        : deserializeEnum<Roles>(snapshotData['user_role']);
    _displayName = snapshotData['display_name'] as String?;
    _photoUrl = snapshotData['photo_url'] as String?;
    _remainingPart = _readFlexibleInt(snapshotData['remaining_part']);
    _city = snapshotData['city'] as String?;
    _cityInseeCode = snapshotData['city_insee_code'] as String?;
    _partLastUpdate = snapshotData['part_last_update'] as DateTime?;
    _birthday = snapshotData['birthday'] as DateTime?;
    _professionalCategory = snapshotData['professional_category'] as String?;
    _allGamesAccessUntil = snapshotData['allGamesAccessUntil'] as DateTime?;
    _lastRealActivityAt = snapshotData['last_real_activity_at'] as DateTime?;
    _gamesPlayedCount = castToType<int>(snapshotData['games_played_count']);
    _playerStatusCached = snapshotData['player_status_cached'] as String?;
    _lastInactiveRelaunchAt = snapshotData['last_inactive_relaunch_at'] as DateTime?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('users');

  static Stream<UsersRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => UsersRecord.fromSnapshot(s));

  static Future<UsersRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => UsersRecord.fromSnapshot(s));

  static UsersRecord fromSnapshot(DocumentSnapshot snapshot) => UsersRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static UsersRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      UsersRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'UsersRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is UsersRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

int? _readFlexibleInt(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.tryParse(trimmed);
  }
  return null;
}

Map<String, dynamic> createUsersRecordData({
  String? email,
  String? uid,
  DateTime? createdTime,
  String? phoneNumber,
  String? firstName,
  String? lastName,
  String? pseudo,
  AccountStatus? accountStatus,
  Roles? userRole,
  String? displayName,
  String? photoUrl,
  int? remainingPart,
  String? city,
  String? cityInseeCode,
  DateTime? partLastUpdate,
  DateTime? birthday,
  String? professionalCategory,
  DateTime? allGamesAccessUntil,
  DateTime? lastRealActivityAt,
  int? gamesPlayedCount,
  DateTime? lastInactiveRelaunchAt,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'email': email,
      'uid': uid,
      'created_time': createdTime,
      'phone_number': phoneNumber,
      'first_name': firstName,
      'last_name': lastName,
      'pseudo': pseudo,
      'account_status': accountStatus,
      'user_role': userRole,
      'display_name': displayName,
      'photo_url': photoUrl,
      'remaining_part': remainingPart,
      'city': city,
      'city_insee_code': cityInseeCode,
      'part_last_update': partLastUpdate,
      'birthday': birthday,
      'professional_category': professionalCategory,
      'allGamesAccessUntil': allGamesAccessUntil,
      'last_real_activity_at': lastRealActivityAt,
      'games_played_count': gamesPlayedCount,
      'last_inactive_relaunch_at': lastInactiveRelaunchAt,
    }.withoutNulls,
  );

  return firestoreData;
}

class UsersRecordDocumentEquality implements Equality<UsersRecord> {
  const UsersRecordDocumentEquality();

  @override
  bool equals(UsersRecord? e1, UsersRecord? e2) {
    return e1?.email == e2?.email &&
        e1?.uid == e2?.uid &&
        e1?.createdTime == e2?.createdTime &&
        e1?.phoneNumber == e2?.phoneNumber &&
        e1?.firstName == e2?.firstName &&
        e1?.lastName == e2?.lastName &&
        e1?.pseudo == e2?.pseudo &&
        e1?.accountStatus == e2?.accountStatus &&
        e1?.userRole == e2?.userRole &&
        e1?.displayName == e2?.displayName &&
        e1?.photoUrl == e2?.photoUrl &&
        e1?.remainingPart == e2?.remainingPart &&
        e1?.city == e2?.city &&
        e1?.cityInseeCode == e2?.cityInseeCode &&
        e1?.partLastUpdate == e2?.partLastUpdate &&
        e1?.birthday == e2?.birthday &&
        e1?.professionalCategory == e2?.professionalCategory &&
        e1?.allGamesAccessUntil == e2?.allGamesAccessUntil &&
        e1?.lastInactiveRelaunchAt == e2?.lastInactiveRelaunchAt &&
        e1?.lastRealActivityAt == e2?.lastRealActivityAt &&
        e1?.gamesPlayedCount == e2?.gamesPlayedCount &&
        e1?.playerStatusCached == e2?.playerStatusCached;
  }

  @override
  int hash(UsersRecord? e) => const ListEquality().hash([
        e?.email,
        e?.uid,
        e?.createdTime,
        e?.phoneNumber,
        e?.firstName,
        e?.lastName,
        e?.pseudo,
        e?.accountStatus,
        e?.userRole,
        e?.displayName,
        e?.photoUrl,
        e?.remainingPart,
        e?.city,
        e?.cityInseeCode,
        e?.partLastUpdate,
        e?.birthday,
        e?.professionalCategory,
        e?.allGamesAccessUntil,
        e?.lastRealActivityAt,
        e?.gamesPlayedCount,
        e?.lastInactiveRelaunchAt,
        e?.playerStatusCached,
      ]);

  @override
  bool isValidKey(Object? o) => o is UsersRecord;
}
