import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';
import '/backend/schema/enums/enums.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class ParticipantsDetailsRecord extends FirestoreRecord {
  ParticipantsDetailsRecord._(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) : super(reference, data) {
    _initializeFields();
  }

  // "last_play" field.
  DateTime? _lastPlay;
  DateTime? get lastPlay => _lastPlay;
  bool hasLastPlay() => _lastPlay != null;

  // "game_bonus" field.
  int? _gameBonus;
  int get gameBonus => _gameBonus ?? 0;
  bool hasGameBonus() => _gameBonus != null;

  // "user_id" field.
  DocumentReference? _userId;
  DocumentReference? get userId => _userId;
  bool hasUserId() => _userId != null;

  DocumentReference get parentReference => reference.parent.parent!;

  void _initializeFields() {
    _lastPlay = snapshotData['last_play'] as DateTime?;
    _gameBonus = castToType<int>(snapshotData['game_bonus']);
    _userId = snapshotData['user_id'] as DocumentReference?;
  }

  static Query<Map<String, dynamic>> collection([DocumentReference? parent]) =>
      parent != null
          ? parent.collection('participants_details')
          : FirebaseFirestore.instance.collectionGroup('participants_details');

  static DocumentReference createDoc(DocumentReference parent, {String? id}) =>
      parent.collection('participants_details').doc(id);

  static Stream<ParticipantsDetailsRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => ParticipantsDetailsRecord.fromSnapshot(s));

  static Future<ParticipantsDetailsRecord> getDocumentOnce(
          DocumentReference ref) =>
      ref.get().then((s) => ParticipantsDetailsRecord.fromSnapshot(s));

  static ParticipantsDetailsRecord fromSnapshot(DocumentSnapshot snapshot) =>
      ParticipantsDetailsRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static ParticipantsDetailsRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      ParticipantsDetailsRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'ParticipantsDetailsRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is ParticipantsDetailsRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createParticipantsDetailsRecordData({
  DateTime? lastPlay,
  int? gameBonus,
  DocumentReference? userId,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'last_play': lastPlay,
      'game_bonus': gameBonus,
      'user_id': userId,
    }.withoutNulls,
  );

  return firestoreData;
}

class ParticipantsDetailsRecordDocumentEquality
    implements Equality<ParticipantsDetailsRecord> {
  const ParticipantsDetailsRecordDocumentEquality();

  @override
  bool equals(ParticipantsDetailsRecord? e1, ParticipantsDetailsRecord? e2) {
    return e1?.lastPlay == e2?.lastPlay &&
        e1?.gameBonus == e2?.gameBonus &&
        e1?.userId == e2?.userId;
  }

  @override
  int hash(ParticipantsDetailsRecord? e) =>
      const ListEquality().hash([e?.lastPlay, e?.gameBonus, e?.userId]);

  @override
  bool isValidKey(Object? o) => o is ParticipantsDetailsRecord;
}
