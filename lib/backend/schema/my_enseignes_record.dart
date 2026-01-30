import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';
import '/backend/schema/enums/enums.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class MyEnseignesRecord extends FirestoreRecord {
  MyEnseignesRecord._(
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
          ? parent.collection('my_enseignes')
          : FirebaseFirestore.instance.collectionGroup('my_enseignes');

  static DocumentReference createDoc(DocumentReference parent, {String? id}) =>
      parent.collection('my_enseignes').doc(id);

  static Stream<MyEnseignesRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => MyEnseignesRecord.fromSnapshot(s));

  static Future<MyEnseignesRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => MyEnseignesRecord.fromSnapshot(s));

  static MyEnseignesRecord fromSnapshot(DocumentSnapshot snapshot) =>
      MyEnseignesRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static MyEnseignesRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      MyEnseignesRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'MyEnseignesRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is MyEnseignesRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createMyEnseignesRecordData({
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

class MyEnseignesRecordDocumentEquality implements Equality<MyEnseignesRecord> {
  const MyEnseignesRecordDocumentEquality();

  @override
  bool equals(MyEnseignesRecord? e1, MyEnseignesRecord? e2) {
    return e1?.enseigneId == e2?.enseigneId && e1?.addedAt == e2?.addedAt;
  }

  @override
  int hash(MyEnseignesRecord? e) =>
      const ListEquality().hash([e?.enseigneId, e?.addedAt]);

  @override
  bool isValidKey(Object? o) => o is MyEnseignesRecord;
}
