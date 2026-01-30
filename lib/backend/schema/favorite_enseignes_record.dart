import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';
import '/backend/schema/enums/enums.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class FavoriteEnseignesRecord extends FirestoreRecord {
  FavoriteEnseignesRecord._(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) : super(reference, data) {
    _initializeFields();
  }

  // "enseigne_id" field.
  DocumentReference? _enseigneId;
  DocumentReference? get enseigneId => _enseigneId;
  bool hasEnseigneId() => _enseigneId != null;

  // "added_at" field.
  DateTime? _addedAt;
  DateTime? get addedAt => _addedAt;
  bool hasAddedAt() => _addedAt != null;

  DocumentReference get parentReference => reference.parent.parent!;

  void _initializeFields() {
    _enseigneId = snapshotData['enseigne_id'] as DocumentReference?;
    _addedAt = snapshotData['added_at'] as DateTime?;
  }

  static Query<Map<String, dynamic>> collection([DocumentReference? parent]) =>
      parent != null
          ? parent.collection('favorite_enseignes')
          : FirebaseFirestore.instance.collectionGroup('favorite_enseignes');

  static DocumentReference createDoc(DocumentReference parent, {String? id}) =>
      parent.collection('favorite_enseignes').doc(id);

  static Stream<FavoriteEnseignesRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => FavoriteEnseignesRecord.fromSnapshot(s));

  static Future<FavoriteEnseignesRecord> getDocumentOnce(
          DocumentReference ref) =>
      ref.get().then((s) => FavoriteEnseignesRecord.fromSnapshot(s));

  static FavoriteEnseignesRecord fromSnapshot(DocumentSnapshot snapshot) =>
      FavoriteEnseignesRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static FavoriteEnseignesRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      FavoriteEnseignesRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'FavoriteEnseignesRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is FavoriteEnseignesRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createFavoriteEnseignesRecordData({
  DocumentReference? enseigneId,
  DateTime? addedAt,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'enseigne_id': enseigneId,
      'added_at': addedAt,
    }.withoutNulls,
  );

  return firestoreData;
}

class FavoriteEnseignesRecordDocumentEquality
    implements Equality<FavoriteEnseignesRecord> {
  const FavoriteEnseignesRecordDocumentEquality();

  @override
  bool equals(FavoriteEnseignesRecord? e1, FavoriteEnseignesRecord? e2) {
    return e1?.enseigneId == e2?.enseigneId && e1?.addedAt == e2?.addedAt;
  }

  @override
  int hash(FavoriteEnseignesRecord? e) =>
      const ListEquality().hash([e?.enseigneId, e?.addedAt]);

  @override
  bool isValidKey(Object? o) => o is FavoriteEnseignesRecord;
}
