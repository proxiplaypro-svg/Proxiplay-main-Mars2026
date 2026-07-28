import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/enums/enums.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class GamesRecord extends FirestoreRecord {
  GamesRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // "name" field.
  String? _name;
  String get name => _name ?? '';
  bool hasName() => _name != null;

  // "description" field.
  String? _description;
  String get description => _description ?? '';
  bool hasDescription() => _description != null;

  // "start_date" field.
  DateTime? _startDate;
  DateTime? get startDate => _startDate;
  bool hasStartDate() => _startDate != null;

  // "end_date" field.
  DateTime? _endDate;
  DateTime? get endDate => _endDate;
  bool hasEndDate() => _endDate != null;

  // "prize_usage_deadline" field.
  DateTime? _prizeUsageDeadline;
  DateTime? get prizeUsageDeadline => _prizeUsageDeadline;
  bool hasPrizeUsageDeadline() => _prizeUsageDeadline != null;

  // "enseigne_id" field.
  DocumentReference? _enseigneId;
  DocumentReference? get enseigneId => _enseigneId;
  bool hasEnseigneId() => _enseigneId != null;

  // "create_by" field.
  DocumentReference? _createBy;
  DocumentReference? get createBy => _createBy;
  bool hasCreateBy() => _createBy != null;

  // "created_time" field.
  DateTime? _createdTime;
  DateTime? get createdTime => _createdTime;
  bool hasCreatedTime() => _createdTime != null;

  // "visible_public" field.
  bool? _visiblePublic;
  bool get visiblePublic => _visiblePublic ?? false;
  bool hasVisiblePublic() => _visiblePublic != null;

  // "prize_value" field.
  double? _prizeValue;
  double get prizeValue => _prizeValue ?? 0.0;
  bool hasPrizeValue() => _prizeValue != null;

  // "game_type" field.
  GameType? _gameType;
  GameType? get gameType => _gameType;
  bool hasGameType() => _gameType != null;

  // "type" field.
  GameAccessType? _type;
  GameAccessType get type => _type ?? GameAccessType.standard;
  bool hasType() => _type != null;

  // "access_mode" field.
  AccessMode? _accessMode;
  AccessMode get accessMode => _accessMode ?? AccessMode.public;
  bool hasAccessMode() => _accessMode != null;

  // "animation_id" field.
  String? _animationId;
  String get animationId => _animationId ?? '';
  bool hasAnimationId() => _animationId != null;

  // "photo" field.
  String? _photo;
  String get photo => _photo ?? '';
  bool hasPhoto() => _photo != null;

  // "secondary_prize_description" field.
  String? _secondaryPrizeDescription;
  String get secondaryPrizeDescription => _secondaryPrizeDescription ?? '';
  bool hasSecondaryPrizeDescription() => _secondaryPrizeDescription != null;

  // "secondary_prizes" field.
  List<Map<String, dynamic>>? _secondaryPrizes;
  List<Map<String, dynamic>> get secondaryPrizes =>
      _secondaryPrizes ?? const [];
  bool hasSecondaryPrizes() => _secondaryPrizes != null;

  // "views" field.
  int? _views;
  int get views => _views ?? 0;
  bool hasViews() => _views != null;

  // "favorites" field.
  int? _favorites;
  int get favorites => _favorites ?? 0;
  bool hasFavorites() => _favorites != null;

  // "participations" field.
  int? _participations;
  int get participations => _participations ?? 0;
  bool hasParticipations() => _participations != null;

  // "prohibited_for_minors" field.
  bool? _prohibitedForMinors;
  bool get prohibitedForMinors => _prohibitedForMinors ?? false;
  bool hasProhibitedForMinors() => _prohibitedForMinors != null;

  // "hasWinner" field.
  bool? _hasWinner;
  bool get hasWinner => _hasWinner ?? false;
  bool hasHasWinner() => _hasWinner != null;

  // "enseigne_name" field.
  String? _enseigneName;
  String get enseigneName => _enseigneName ?? '';
  bool hasEnseigneName() => _enseigneName != null;

  // "main_prize_winner" field.
  DocumentReference? _mainPrizeWinner;
  DocumentReference? get mainPrizeWinner => _mainPrizeWinner;
  bool hasMainPrizeWinner() => _mainPrizeWinner != null;

  // "hasMainPrize" field.
  bool? _hasMainPrize;
  bool get hasMainPrize => _hasMainPrize ?? false;
  bool hasHasMainPrize() => _hasMainPrize != null;

  // "qr_link" field.
  String? _qrLink;
  String get qrLink => _qrLink ?? '';
  bool hasQrLink() => _qrLink != null;

  // "qr_target" field.
  String? _qrTarget;
  String get qrTarget => _qrTarget ?? '';
  bool hasQrTarget() => _qrTarget != null;

  // "qr_created_at" field.
  DateTime? _qrCreatedAt;
  DateTime? get qrCreatedAt => _qrCreatedAt;
  bool hasQrCreatedAt() => _qrCreatedAt != null;

  // "qr_version" field.
  int? _qrVersion;
  int get qrVersion => _qrVersion ?? 0;
  bool hasQrVersion() => _qrVersion != null;

  void _initializeFields() {
    _name = snapshotData['name'] as String?;
    _description = snapshotData['description'] as String?;
    _startDate = snapshotData['start_date'] as DateTime?;
    _endDate = snapshotData['end_date'] as DateTime?;
    _prizeUsageDeadline = snapshotData['prize_usage_deadline'] as DateTime?;
    _enseigneId = snapshotData['enseigne_id'] as DocumentReference?;
    _createBy = snapshotData['create_by'] as DocumentReference?;
    _createdTime = snapshotData['created_time'] as DateTime?;
    _visiblePublic = snapshotData['visible_public'] as bool?;
    _prizeValue = castToType<double>(snapshotData['prize_value']);
    _gameType = snapshotData['game_type'] is GameType
        ? snapshotData['game_type']
        : deserializeEnum<GameType>(snapshotData['game_type']);
    _type = snapshotData['type'] is GameAccessType
        ? snapshotData['type']
        : deserializeEnum<GameAccessType>(snapshotData['type']);
    _accessMode = snapshotData['access_mode'] is AccessMode
        ? snapshotData['access_mode']
        : deserializeEnum<AccessMode>(snapshotData['access_mode']);
    _animationId = snapshotData['animation_id'] as String?;
    _photo = snapshotData['photo'] as String?;
    _secondaryPrizeDescription =
        snapshotData['secondary_prize_description'] as String?;
    _secondaryPrizes =
        getDataList<Map<String, dynamic>>(snapshotData['secondary_prizes']);
    _views = castToType<int>(snapshotData['views']);
    _favorites = castToType<int>(snapshotData['favorites']);
    _participations = castToType<int>(snapshotData['participations']);
    _prohibitedForMinors = snapshotData['prohibited_for_minors'] as bool?;
    _hasWinner = snapshotData['hasWinner'] as bool?;
    _enseigneName = snapshotData['enseigne_name'] as String?;
    _mainPrizeWinner = snapshotData['main_prize_winner'] as DocumentReference?;
    _hasMainPrize = snapshotData['hasMainPrize'] as bool?;
    _qrLink = snapshotData['qr_link'] as String?;
    _qrTarget = snapshotData['qr_target'] as String?;
    _qrCreatedAt = snapshotData['qr_created_at'] as DateTime?;
    _qrVersion = castToType<int>(snapshotData['qr_version']);
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('games');

  static Stream<GamesRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => GamesRecord.fromSnapshot(s));

  static Future<GamesRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => GamesRecord.fromSnapshot(s));

  static GamesRecord fromSnapshot(DocumentSnapshot snapshot) => GamesRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static GamesRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      GamesRecord._(reference, mapFromFirestore(data));

  static GamesRecord fromJson(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      GamesRecord._(reference, mapFromFirestore(data));

  Map<String, dynamic> toJson() => mapToFirestore(
        <String, dynamic>{
          'name': _name,
          'description': _description,
          'start_date': _startDate,
          'end_date': _endDate,
          'prize_usage_deadline': _prizeUsageDeadline,
          'enseigne_id': _enseigneId,
          'create_by': _createBy,
          'created_time': _createdTime,
          'visible_public': _visiblePublic,
          'prize_value': _prizeValue,
          'game_type': _gameType,
          'type': _type ?? GameAccessType.standard,
          'access_mode': _accessMode ?? AccessMode.public,
          'animation_id': _animationId,
          'photo': _photo,
          'secondary_prize_description': _secondaryPrizeDescription,
          'secondary_prizes': _secondaryPrizes,
          'views': _views,
          'favorites': _favorites,
          'participations': _participations,
          'prohibited_for_minors': _prohibitedForMinors,
          'hasWinner': _hasWinner,
          'enseigne_name': _enseigneName,
          'main_prize_winner': _mainPrizeWinner,
          'hasMainPrize': _hasMainPrize,
          'qr_link': _qrLink,
          'qr_target': _qrTarget,
          'qr_created_at': _qrCreatedAt,
          'qr_version': _qrVersion,
        }.withoutNulls,
      );

  @override
  String toString() =>
      'GamesRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is GamesRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createGamesRecordData({
  String? name,
  String? description,
  DateTime? startDate,
  DateTime? endDate,
  DateTime? prizeUsageDeadline,
  DocumentReference? enseigneId,
  DocumentReference? createBy,
  DateTime? createdTime,
  bool? visiblePublic,
  num? prizeValue,
  GameType? gameType,
  GameAccessType? type,
  AccessMode? accessMode,
  String? animationId,
  String? photo,
  String? secondaryPrizeDescription,
  List<Map<String, dynamic>>? secondaryPrizes,
  int? views,
  int? favorites,
  int? participations,
  bool? prohibitedForMinors,
  bool? hasWinner,
  String? enseigneName,
  DocumentReference? mainPrizeWinner,
  bool? hasMainPrize,
  String? qrLink,
  String? qrTarget,
  DateTime? qrCreatedAt,
  int? qrVersion,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'name': name,
      'description': description,
      'start_date': startDate,
      'end_date': endDate,
      'prize_usage_deadline': prizeUsageDeadline,
      'enseigne_id': enseigneId,
      'create_by': createBy,
      'created_time': createdTime,
      'visible_public': visiblePublic,
      'prize_value': prizeValue,
      'game_type': gameType,
      'type': type ?? GameAccessType.standard,
      'access_mode': accessMode ?? AccessMode.public,
      'animation_id': animationId,
      'photo': photo,
      'secondary_prize_description': secondaryPrizeDescription,
      'secondary_prizes': secondaryPrizes,
      'views': views,
      'favorites': favorites,
      'participations': participations,
      'prohibited_for_minors': prohibitedForMinors,
      'hasWinner': hasWinner,
      'enseigne_name': enseigneName,
      'main_prize_winner': mainPrizeWinner,
      'hasMainPrize': hasMainPrize,
      'qr_link': qrLink,
      'qr_target': qrTarget,
      'qr_created_at': qrCreatedAt,
      'qr_version': qrVersion,
    }.withoutNulls,
  );

  return firestoreData;
}

class GamesRecordDocumentEquality implements Equality<GamesRecord> {
  const GamesRecordDocumentEquality();

  @override
  bool equals(GamesRecord? e1, GamesRecord? e2) {
    return e1?.name == e2?.name &&
        e1?.description == e2?.description &&
        e1?.startDate == e2?.startDate &&
        e1?.endDate == e2?.endDate &&
        e1?.prizeUsageDeadline == e2?.prizeUsageDeadline &&
        e1?.enseigneId == e2?.enseigneId &&
        e1?.createBy == e2?.createBy &&
        e1?.createdTime == e2?.createdTime &&
        e1?.visiblePublic == e2?.visiblePublic &&
        e1?.prizeValue == e2?.prizeValue &&
        e1?.gameType == e2?.gameType &&
        e1?.type == e2?.type &&
        e1?.accessMode == e2?.accessMode &&
        e1?.animationId == e2?.animationId &&
        e1?.photo == e2?.photo &&
        e1?.secondaryPrizeDescription == e2?.secondaryPrizeDescription &&
        const ListEquality().equals(e1?.secondaryPrizes, e2?.secondaryPrizes) &&
        e1?.views == e2?.views &&
        e1?.favorites == e2?.favorites &&
        e1?.participations == e2?.participations &&
        e1?.prohibitedForMinors == e2?.prohibitedForMinors &&
        e1?.hasWinner == e2?.hasWinner &&
        e1?.enseigneName == e2?.enseigneName &&
        e1?.mainPrizeWinner == e2?.mainPrizeWinner &&
        e1?.hasMainPrize == e2?.hasMainPrize &&
        e1?.qrLink == e2?.qrLink &&
        e1?.qrTarget == e2?.qrTarget &&
        e1?.qrCreatedAt == e2?.qrCreatedAt &&
        e1?.qrVersion == e2?.qrVersion;
  }

  @override
  int hash(GamesRecord? e) => const ListEquality().hash([
        e?.name,
        e?.description,
        e?.startDate,
        e?.endDate,
        e?.prizeUsageDeadline,
        e?.enseigneId,
        e?.createBy,
        e?.createdTime,
        e?.visiblePublic,
        e?.prizeValue,
        e?.gameType,
        e?.type,
        e?.accessMode,
        e?.animationId,
        e?.photo,
        e?.secondaryPrizeDescription,
        e?.secondaryPrizes,
        e?.views,
        e?.favorites,
        e?.participations,
        e?.prohibitedForMinors,
        e?.hasWinner,
        e?.enseigneName,
        e?.mainPrizeWinner,
        e?.hasMainPrize,
        e?.qrLink,
        e?.qrTarget,
        e?.qrCreatedAt,
        e?.qrVersion
      ]);

  @override
  bool isValidKey(Object? o) => o is GamesRecord;
}
