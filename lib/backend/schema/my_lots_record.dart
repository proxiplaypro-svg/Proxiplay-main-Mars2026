import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';
import '/backend/schema/enums/enums.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class MyLotsRecord extends FirestoreRecord {
  MyLotsRecord._(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) : super(reference, data) {
    _initializeFields();
  }

  // "prize_id" field.
  DocumentReference? _prizeId;
  DocumentReference? get prizeId => _prizeId;
  bool hasPrizeId() => _prizeId != null;

  DocumentReference get parentReference => reference.parent.parent!;

  void _initializeFields() {
    _prizeId = snapshotData['prize_id'] as DocumentReference?;
  }

  static Query<Map<String, dynamic>> collection([DocumentReference? parent]) =>
      parent != null
          ? parent.collection('my_lots')
          : FirebaseFirestore.instance.collectionGroup('my_lots');

  static DocumentReference createDoc(DocumentReference parent, {String? id}) =>
      parent.collection('my_lots').doc(id);

  static Stream<MyLotsRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => MyLotsRecord.fromSnapshot(s));

  static Future<MyLotsRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => MyLotsRecord.fromSnapshot(s));

  static MyLotsRecord fromSnapshot(DocumentSnapshot snapshot) => MyLotsRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static MyLotsRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      MyLotsRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'MyLotsRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is MyLotsRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createMyLotsRecordData({
  DocumentReference? prizeId,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'prize_id': prizeId,
    }.withoutNulls,
  );

  return firestoreData;
}

class MyLotsRecordDocumentEquality implements Equality<MyLotsRecord> {
  const MyLotsRecordDocumentEquality();

  @override
  bool equals(MyLotsRecord? e1, MyLotsRecord? e2) {
    return e1?.prizeId == e2?.prizeId;
  }

  @override
  int hash(MyLotsRecord? e) => const ListEquality().hash([e?.prizeId]);

  @override
  bool isValidKey(Object? o) => o is MyLotsRecord;
}
