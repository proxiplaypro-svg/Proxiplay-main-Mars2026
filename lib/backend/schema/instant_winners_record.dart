import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';
import '/backend/schema/enums/enums.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class InstantWinnersRecord extends FirestoreRecord {
  InstantWinnersRecord._(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) : super(reference, data) {
    _initializeFields();
  }

  // "date" field.
  DateTime? _date;
  DateTime? get date => _date;
  bool hasDate() => _date != null;

  // "hasWinner" field.
  bool? _hasWinner;
  bool get hasWinner => _hasWinner ?? false;
  bool hasHasWinner() => _hasWinner != null;

  // "player_id" field.
  DocumentReference? _playerId;
  DocumentReference? get playerId => _playerId;
  bool hasPlayerId() => _playerId != null;

  // "prize" field.
  String? _prize;
  String get prize => _prize ?? '';
  bool hasPrize() => _prize != null;

  DocumentReference get parentReference => reference.parent.parent!;

  void _initializeFields() {
    _date = snapshotData['date'] as DateTime?;
    _hasWinner = snapshotData['hasWinner'] as bool?;
    _playerId = snapshotData['player_id'] as DocumentReference?;
    _prize = snapshotData['prize'] as String?;
  }

  static Query<Map<String, dynamic>> collection([DocumentReference? parent]) =>
      parent != null
          ? parent.collection('instant_winners')
          : FirebaseFirestore.instance.collectionGroup('instant_winners');

  static DocumentReference createDoc(DocumentReference parent, {String? id}) =>
      parent.collection('instant_winners').doc(id);

  static Stream<InstantWinnersRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => InstantWinnersRecord.fromSnapshot(s));

  static Future<InstantWinnersRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => InstantWinnersRecord.fromSnapshot(s));

  static InstantWinnersRecord fromSnapshot(DocumentSnapshot snapshot) =>
      InstantWinnersRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static InstantWinnersRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      InstantWinnersRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'InstantWinnersRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is InstantWinnersRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createInstantWinnersRecordData({
  DateTime? date,
  bool? hasWinner,
  DocumentReference? playerId,
  String? prize,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'date': date,
      'hasWinner': hasWinner,
      'player_id': playerId,
      'prize': prize,
    }.withoutNulls,
  );

  return firestoreData;
}

class InstantWinnersRecordDocumentEquality
    implements Equality<InstantWinnersRecord> {
  const InstantWinnersRecordDocumentEquality();

  @override
  bool equals(InstantWinnersRecord? e1, InstantWinnersRecord? e2) {
    return e1?.date == e2?.date &&
        e1?.hasWinner == e2?.hasWinner &&
        e1?.playerId == e2?.playerId &&
        e1?.prize == e2?.prize;
  }

  @override
  int hash(InstantWinnersRecord? e) =>
      const ListEquality().hash([e?.date, e?.hasWinner, e?.playerId, e?.prize]);

  @override
  bool isValidKey(Object? o) => o is InstantWinnersRecord;
}
