import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class WinnersRecord extends FirestoreRecord {
  WinnersRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // "player_id" field.
  DocumentReference? _playerId;
  DocumentReference? get playerId => _playerId;
  bool hasPlayerId() => _playerId != null;

  // "prize" field.
  String? _prize;
  String get prize => _prize ?? '';
  bool hasPrize() => _prize != null;

  // "play_position" field.
  int? _playPosition;
  int get playPosition => _playPosition ?? 0;
  bool hasPlayPosition() => _playPosition != null;

  // "claim_code" field.
  String? _claimCode;
  String get claimCode => _claimCode ?? '';
  bool hasClaimCode() => _claimCode != null;

  // "claimed" field.
  bool? _claimed;
  bool get claimed => _claimed ?? false;
  bool hasClaimed() => _claimed != null;

  DocumentReference get parentReference => reference.parent.parent!;

  void _initializeFields() {
    _playerId = snapshotData['player_id'] as DocumentReference?;
    _prize = snapshotData['prize'] as String?;
    _playPosition = castToType<int>(snapshotData['play_position']);
    _claimCode = snapshotData['claim_code'] as String?;
    _claimed = snapshotData['claimed'] as bool?;
  }

  static Query<Map<String, dynamic>> collection([DocumentReference? parent]) =>
      parent != null
          ? parent.collection('winners')
          : FirebaseFirestore.instance.collectionGroup('winners');

  static DocumentReference createDoc(DocumentReference parent, {String? id}) =>
      parent.collection('winners').doc(id);

  static Stream<WinnersRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => WinnersRecord.fromSnapshot(s));

  static Future<WinnersRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => WinnersRecord.fromSnapshot(s));

  static WinnersRecord fromSnapshot(DocumentSnapshot snapshot) =>
      WinnersRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static WinnersRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      WinnersRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'WinnersRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is WinnersRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createWinnersRecordData({
  DocumentReference? playerId,
  String? prize,
  int? playPosition,
  String? claimCode,
  bool? claimed,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'player_id': playerId,
      'prize': prize,
      'play_position': playPosition,
      'claim_code': claimCode,
      'claimed': claimed,
    }.withoutNulls,
  );

  return firestoreData;
}

class WinnersRecordDocumentEquality implements Equality<WinnersRecord> {
  const WinnersRecordDocumentEquality();

  @override
  bool equals(WinnersRecord? e1, WinnersRecord? e2) {
    return e1?.playerId == e2?.playerId &&
        e1?.prize == e2?.prize &&
        e1?.playPosition == e2?.playPosition &&
        e1?.claimCode == e2?.claimCode &&
        e1?.claimed == e2?.claimed;
  }

  @override
  int hash(WinnersRecord? e) => const ListEquality()
      .hash([e?.playerId, e?.prize, e?.playPosition, e?.claimCode, e?.claimed]);

  @override
  bool isValidKey(Object? o) => o is WinnersRecord;
}
