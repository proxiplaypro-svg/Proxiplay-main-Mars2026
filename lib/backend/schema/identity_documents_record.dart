import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';
import '/backend/schema/enums/enums.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class IdentityDocumentsRecord extends FirestoreRecord {
  IdentityDocumentsRecord._(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) : super(reference, data) {
    _initializeFields();
  }

  // "id_photo_commercant_url" field.
  String? _idPhotoCommercantUrl;
  String get idPhotoCommercantUrl => _idPhotoCommercantUrl ?? '';
  bool hasIdPhotoCommercantUrl() => _idPhotoCommercantUrl != null;

  // "id_front_card_url" field.
  String? _idFrontCardUrl;
  String get idFrontCardUrl => _idFrontCardUrl ?? '';
  bool hasIdFrontCardUrl() => _idFrontCardUrl != null;

  // "id_back_card_url" field.
  String? _idBackCardUrl;
  String get idBackCardUrl => _idBackCardUrl ?? '';
  bool hasIdBackCardUrl() => _idBackCardUrl != null;

  DocumentReference get parentReference => reference.parent.parent!;

  void _initializeFields() {
    _idPhotoCommercantUrl = snapshotData['id_photo_commercant_url'] as String?;
    _idFrontCardUrl = snapshotData['id_front_card_url'] as String?;
    _idBackCardUrl = snapshotData['id_back_card_url'] as String?;
  }

  static Query<Map<String, dynamic>> collection([DocumentReference? parent]) =>
      parent != null
          ? parent.collection('identity_documents')
          : FirebaseFirestore.instance.collectionGroup('identity_documents');

  static DocumentReference createDoc(DocumentReference parent, {String? id}) =>
      parent.collection('identity_documents').doc(id);

  static Stream<IdentityDocumentsRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => IdentityDocumentsRecord.fromSnapshot(s));

  static Future<IdentityDocumentsRecord> getDocumentOnce(
          DocumentReference ref) =>
      ref.get().then((s) => IdentityDocumentsRecord.fromSnapshot(s));

  static IdentityDocumentsRecord fromSnapshot(DocumentSnapshot snapshot) =>
      IdentityDocumentsRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static IdentityDocumentsRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      IdentityDocumentsRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'IdentityDocumentsRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is IdentityDocumentsRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createIdentityDocumentsRecordData({
  String? idPhotoCommercantUrl,
  String? idFrontCardUrl,
  String? idBackCardUrl,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'id_photo_commercant_url': idPhotoCommercantUrl,
      'id_front_card_url': idFrontCardUrl,
      'id_back_card_url': idBackCardUrl,
    }.withoutNulls,
  );

  return firestoreData;
}

class IdentityDocumentsRecordDocumentEquality
    implements Equality<IdentityDocumentsRecord> {
  const IdentityDocumentsRecordDocumentEquality();

  @override
  bool equals(IdentityDocumentsRecord? e1, IdentityDocumentsRecord? e2) {
    return e1?.idPhotoCommercantUrl == e2?.idPhotoCommercantUrl &&
        e1?.idFrontCardUrl == e2?.idFrontCardUrl &&
        e1?.idBackCardUrl == e2?.idBackCardUrl;
  }

  @override
  int hash(IdentityDocumentsRecord? e) => const ListEquality()
      .hash([e?.idPhotoCommercantUrl, e?.idFrontCardUrl, e?.idBackCardUrl]);

  @override
  bool isValidKey(Object? o) => o is IdentityDocumentsRecord;
}
