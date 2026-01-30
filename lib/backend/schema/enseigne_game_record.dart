import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';
import '/backend/schema/enums/enums.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class EnseigneGameRecord extends FirestoreRecord {
  EnseigneGameRecord._(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) : super(reference, data) {
    _initializeFields();
  }

  // "game_id" field.
  DocumentReference? _gameId;
  DocumentReference? get gameId => _gameId;
  bool hasGameId() => _gameId != null;

  // "added_at" field.
  DateTime? _addedAt;
  DateTime? get addedAt => _addedAt;
  bool hasAddedAt() => _addedAt != null;

  DocumentReference get parentReference => reference.parent.parent!;

  void _initializeFields() {
    _gameId = snapshotData['game_id'] as DocumentReference?;
    _addedAt = snapshotData['added_at'] as DateTime?;
  }

  static Query<Map<String, dynamic>> collection([DocumentReference? parent]) =>
      parent != null
          ? parent.collection('enseigne_game')
          : FirebaseFirestore.instance.collectionGroup('enseigne_game');

  static DocumentReference createDoc(DocumentReference parent, {String? id}) =>
      parent.collection('enseigne_game').doc(id);

  static Stream<EnseigneGameRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => EnseigneGameRecord.fromSnapshot(s));

  static Future<EnseigneGameRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => EnseigneGameRecord.fromSnapshot(s));

  static EnseigneGameRecord fromSnapshot(DocumentSnapshot snapshot) =>
      EnseigneGameRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static EnseigneGameRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      EnseigneGameRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'EnseigneGameRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is EnseigneGameRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createEnseigneGameRecordData({
  DocumentReference? gameId,
  DateTime? addedAt,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'game_id': gameId,
      'added_at': addedAt,
    }.withoutNulls,
  );

  return firestoreData;
}

class EnseigneGameRecordDocumentEquality
    implements Equality<EnseigneGameRecord> {
  const EnseigneGameRecordDocumentEquality();

  @override
  bool equals(EnseigneGameRecord? e1, EnseigneGameRecord? e2) {
    return e1?.gameId == e2?.gameId && e1?.addedAt == e2?.addedAt;
  }

  @override
  int hash(EnseigneGameRecord? e) =>
      const ListEquality().hash([e?.gameId, e?.addedAt]);

  @override
  bool isValidKey(Object? o) => o is EnseigneGameRecord;
}
