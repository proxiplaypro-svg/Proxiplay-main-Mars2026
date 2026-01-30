import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';
import '/backend/schema/enums/enums.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class PrizesRecord extends FirestoreRecord {
  PrizesRecord._(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) : super(reference, data) {
    _initializeFields();
  }

  // "prize_type" field.
  PrizeType? _prizeType;
  PrizeType? get prizeType => _prizeType;
  bool hasPrizeType() => _prizeType != null;

  // "description" field.
  String? _description;
  String get description => _description ?? '';
  bool hasDescription() => _description != null;

  // "name" field.
  String? _name;
  String get name => _name ?? '';
  bool hasName() => _name != null;

  // "winner_id" field.
  DocumentReference? _winnerId;
  DocumentReference? get winnerId => _winnerId;
  bool hasWinnerId() => _winnerId != null;

  // "game_id" field.
  DocumentReference? _gameId;
  DocumentReference? get gameId => _gameId;
  bool hasGameId() => _gameId != null;

  // "enseigne_id" field.
  DocumentReference? _enseigneId;
  DocumentReference? get enseigneId => _enseigneId;
  bool hasEnseigneId() => _enseigneId != null;

  // "owner_id" field.
  DocumentReference? _ownerId;
  DocumentReference? get ownerId => _ownerId;
  bool hasOwnerId() => _ownerId != null;

  // "claim_code" field.
  String? _claimCode;
  String get claimCode => _claimCode ?? '';
  bool hasClaimCode() => _claimCode != null;

  // "claimed" field.
  bool? _claimed;
  bool get claimed => _claimed ?? false;
  bool hasClaimed() => _claimed != null;

  // "win_date" field.
  DateTime? _winDate;
  DateTime? get winDate => _winDate;
  bool hasWinDate() => _winDate != null;

  // "enseigne_name" field.
  String? _enseigneName;
  String get enseigneName => _enseigneName ?? '';
  bool hasEnseigneName() => _enseigneName != null;

  void _initializeFields() {
    _prizeType = snapshotData['prize_type'] is PrizeType
        ? snapshotData['prize_type']
        : deserializeEnum<PrizeType>(snapshotData['prize_type']);
    _description = snapshotData['description'] as String?;
    _name = snapshotData['name'] as String?;
    _winnerId = snapshotData['winner_id'] as DocumentReference?;
    _gameId = snapshotData['game_id'] as DocumentReference?;
    _enseigneId = snapshotData['enseigne_id'] as DocumentReference?;
    _ownerId = snapshotData['owner_id'] as DocumentReference?;
    _claimCode = snapshotData['claim_code'] as String?;
    _claimed = snapshotData['claimed'] as bool?;
    _winDate = snapshotData['win_date'] as DateTime?;
    _enseigneName = snapshotData['enseigne_name'] as String?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('prizes');

  static Stream<PrizesRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => PrizesRecord.fromSnapshot(s));

  static Future<PrizesRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => PrizesRecord.fromSnapshot(s));

  static PrizesRecord fromSnapshot(DocumentSnapshot snapshot) => PrizesRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static PrizesRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      PrizesRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'PrizesRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is PrizesRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createPrizesRecordData({
  PrizeType? prizeType,
  String? description,
  String? name,
  DocumentReference? winnerId,
  DocumentReference? gameId,
  DocumentReference? enseigneId,
  DocumentReference? ownerId,
  String? claimCode,
  bool? claimed,
  DateTime? winDate,
  String? enseigneName,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'prize_type': prizeType,
      'description': description,
      'name': name,
      'winner_id': winnerId,
      'game_id': gameId,
      'enseigne_id': enseigneId,
      'owner_id': ownerId,
      'claim_code': claimCode,
      'claimed': claimed,
      'win_date': winDate,
      'enseigne_name': enseigneName,
    }.withoutNulls,
  );

  return firestoreData;
}

class PrizesRecordDocumentEquality implements Equality<PrizesRecord> {
  const PrizesRecordDocumentEquality();

  @override
  bool equals(PrizesRecord? e1, PrizesRecord? e2) {
    return e1?.prizeType == e2?.prizeType &&
        e1?.description == e2?.description &&
        e1?.name == e2?.name &&
        e1?.winnerId == e2?.winnerId &&
        e1?.gameId == e2?.gameId &&
        e1?.enseigneId == e2?.enseigneId &&
        e1?.ownerId == e2?.ownerId &&
        e1?.claimCode == e2?.claimCode &&
        e1?.claimed == e2?.claimed &&
        e1?.winDate == e2?.winDate &&
        e1?.enseigneName == e2?.enseigneName;
  }

  @override
  int hash(PrizesRecord? e) => const ListEquality().hash([
        e?.prizeType,
        e?.description,
        e?.name,
        e?.winnerId,
        e?.gameId,
        e?.enseigneId,
        e?.ownerId,
        e?.claimCode,
        e?.claimed,
        e?.winDate,
        e?.enseigneName
      ]);

  @override
  bool isValidKey(Object? o) => o is PrizesRecord;
}
