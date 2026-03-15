import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class AccountDeletionRequestsRecord extends FirestoreRecord {
  AccountDeletionRequestsRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // "merchant_id" field.
  DocumentReference? _merchantId;
  DocumentReference? get merchantId => _merchantId;
  bool hasMerchantId() => _merchantId != null;

  // "requested_at" field.
  DateTime? _requestedAt;
  DateTime? get requestedAt => _requestedAt;
  bool hasRequestedAt() => _requestedAt != null;

  void _initializeFields() {
    _merchantId = snapshotData['merchant_id'] as DocumentReference?;
    _requestedAt = snapshotData['requested_at'] as DateTime?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('accountDeletionRequests');

  static Stream<AccountDeletionRequestsRecord> getDocument(
          DocumentReference ref) =>
      ref.snapshots().map((s) => AccountDeletionRequestsRecord.fromSnapshot(s));

  static Future<AccountDeletionRequestsRecord> getDocumentOnce(
          DocumentReference ref) =>
      ref.get().then((s) => AccountDeletionRequestsRecord.fromSnapshot(s));

  static AccountDeletionRequestsRecord fromSnapshot(
          DocumentSnapshot snapshot) =>
      AccountDeletionRequestsRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static AccountDeletionRequestsRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      AccountDeletionRequestsRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'AccountDeletionRequestsRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is AccountDeletionRequestsRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createAccountDeletionRequestsRecordData({
  DocumentReference? merchantId,
  DateTime? requestedAt,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'merchant_id': merchantId,
      'requested_at': requestedAt,
    }.withoutNulls,
  );

  return firestoreData;
}

class AccountDeletionRequestsRecordDocumentEquality
    implements Equality<AccountDeletionRequestsRecord> {
  const AccountDeletionRequestsRecordDocumentEquality();

  @override
  bool equals(
      AccountDeletionRequestsRecord? e1, AccountDeletionRequestsRecord? e2) {
    return e1?.merchantId == e2?.merchantId &&
        e1?.requestedAt == e2?.requestedAt;
  }

  @override
  int hash(AccountDeletionRequestsRecord? e) =>
      const ListEquality().hash([e?.merchantId, e?.requestedAt]);

  @override
  bool isValidKey(Object? o) => o is AccountDeletionRequestsRecord;
}
