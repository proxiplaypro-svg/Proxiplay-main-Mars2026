import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class AnimationsRecord extends FirestoreRecord {
  AnimationsRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // "name" field.
  String? _name;
  String get name => _name ?? '';
  bool hasName() => _name != null;

  // "description" field.
  String? _description;
  String get description => _description ?? '';
  bool hasDescription() => _description != null;

  // "cover_image" field.
  String? _coverImage;
  String get coverImage => _coverImage ?? '';
  bool hasCoverImage() => _coverImage != null;

  // "start_date" field.
  DateTime? _startDate;
  DateTime? get startDate => _startDate;
  bool hasStartDate() => _startDate != null;

  // "end_date" field.
  DateTime? _endDate;
  DateTime? get endDate => _endDate;
  bool hasEndDate() => _endDate != null;

  // "status" field.
  String? _status;
  String get status => _status ?? 'draft';
  bool hasStatus() => _status != null;

  // "prize_description" field.
  String? _prizeDescription;
  String get prizeDescription => _prizeDescription ?? '';
  bool hasPrizeDescription() => _prizeDescription != null;

  // "prize_image" field.
  String? _prizeImage;
  String get prizeImage => _prizeImage ?? '';
  bool hasPrizeImage() => _prizeImage != null;

  // "merchant_ids" field.
  List<String>? _merchantIds;
  List<String> get merchantIds => _merchantIds ?? const [];
  bool hasMerchantIds() => _merchantIds != null;

  // "threshold" field.
  int? _threshold;
  int get threshold => _threshold ?? 3;
  bool hasThreshold() => _threshold != null;

  void _initializeFields() {
    _name = snapshotData['name'] as String?;
    _description = snapshotData['description'] as String?;
    _coverImage = snapshotData['cover_image'] as String?;
    _startDate = snapshotData['start_date'] as DateTime?;
    _endDate = snapshotData['end_date'] as DateTime?;
    _status = snapshotData['status'] as String?;
    _prizeDescription = snapshotData['prize_description'] as String?;
    _prizeImage = snapshotData['prize_image'] as String?;
    _merchantIds = getDataList<String>(snapshotData['merchant_ids']);
    _threshold = castToType<int>(snapshotData['threshold']);
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('animations');

  static Stream<AnimationsRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => AnimationsRecord.fromSnapshot(s));

  static Future<AnimationsRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => AnimationsRecord.fromSnapshot(s));

  static AnimationsRecord fromSnapshot(DocumentSnapshot snapshot) =>
      AnimationsRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static AnimationsRecord fromJson(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      AnimationsRecord._(reference, mapFromFirestore(data));

  static AnimationsRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      AnimationsRecord._(reference, mapFromFirestore(data));

  Map<String, dynamic> toJson() => mapToFirestore(
        <String, dynamic>{
          'name': _name ?? '',
          'description': _description ?? '',
          'cover_image': _coverImage ?? '',
          'start_date': _startDate,
          'end_date': _endDate,
          'status': _status ?? 'draft',
          'prize_description': _prizeDescription ?? '',
          'prize_image': _prizeImage ?? '',
          'merchant_ids': _merchantIds ?? const <String>[],
          'threshold': _threshold ?? 3,
        }.withoutNulls,
      );

  @override
  String toString() =>
      'AnimationsRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is AnimationsRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createAnimationsRecordData({
  String? name,
  String? description,
  String? coverImage,
  DateTime? startDate,
  DateTime? endDate,
  String? status,
  String? prizeDescription,
  String? prizeImage,
  List<String>? merchantIds,
  int? threshold,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'name': name,
      'description': description,
      'cover_image': coverImage,
      'start_date': startDate,
      'end_date': endDate,
      'status': status ?? 'draft',
      'prize_description': prizeDescription,
      'prize_image': prizeImage,
      'merchant_ids': merchantIds ?? const <String>[],
      'threshold': threshold ?? 3,
    }.withoutNulls,
  );

  return firestoreData;
}

class AnimationsRecordDocumentEquality implements Equality<AnimationsRecord> {
  const AnimationsRecordDocumentEquality();

  @override
  bool equals(AnimationsRecord? e1, AnimationsRecord? e2) {
    return e1?.name == e2?.name &&
        e1?.description == e2?.description &&
        e1?.coverImage == e2?.coverImage &&
        e1?.startDate == e2?.startDate &&
        e1?.endDate == e2?.endDate &&
        e1?.status == e2?.status &&
        e1?.prizeDescription == e2?.prizeDescription &&
        e1?.prizeImage == e2?.prizeImage &&
        const ListEquality().equals(e1?.merchantIds, e2?.merchantIds) &&
        e1?.threshold == e2?.threshold;
  }

  @override
  int hash(AnimationsRecord? e) => const ListEquality().hash([
        e?.name,
        e?.description,
        e?.coverImage,
        e?.startDate,
        e?.endDate,
        e?.status,
        e?.prizeDescription,
        e?.prizeImage,
        e?.merchantIds,
        e?.threshold,
      ]);

  @override
  bool isValidKey(Object? o) => o is AnimationsRecord;
}
