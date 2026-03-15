import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/enums/enums.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class HorairesRecord extends FirestoreRecord {
  HorairesRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // "opening_morning" field.
  DateTime? _openingMorning;
  DateTime? get openingMorning => _openingMorning;
  bool hasOpeningMorning() => _openingMorning != null;

  // "closing_morning" field.
  DateTime? _closingMorning;
  DateTime? get closingMorning => _closingMorning;
  bool hasClosingMorning() => _closingMorning != null;

  // "opening_afternoon" field.
  DateTime? _openingAfternoon;
  DateTime? get openingAfternoon => _openingAfternoon;
  bool hasOpeningAfternoon() => _openingAfternoon != null;

  // "closing_afternoon" field.
  DateTime? _closingAfternoon;
  DateTime? get closingAfternoon => _closingAfternoon;
  bool hasClosingAfternoon() => _closingAfternoon != null;

  // "closing_event" field.
  List<DateTime>? _closingEvent;
  List<DateTime> get closingEvent => _closingEvent ?? const [];
  bool hasClosingEvent() => _closingEvent != null;

  // "opening_day" field.
  DateTime? _openingDay;
  DateTime? get openingDay => _openingDay;
  bool hasOpeningDay() => _openingDay != null;

  // "closing_day" field.
  DateTime? _closingDay;
  DateTime? get closingDay => _closingDay;
  bool hasClosingDay() => _closingDay != null;

  // "is_full_day" field.
  bool? _isFullDay;
  bool get isFullDay => _isFullDay ?? false;
  bool hasIsFullDay() => _isFullDay != null;

  // "is_open" field.
  bool? _isOpen;
  bool get isOpen => _isOpen ?? false;
  bool hasIsOpen() => _isOpen != null;

  // "day" field.
  DayOfTheWeek? _day;
  DayOfTheWeek? get day => _day;
  bool hasDay() => _day != null;

  // "created_time" field.
  DateTime? _createdTime;
  DateTime? get createdTime => _createdTime;
  bool hasCreatedTime() => _createdTime != null;

  // "order" field.
  int? _order;
  int get order => _order ?? 0;
  bool hasOrder() => _order != null;

  DocumentReference get parentReference => reference.parent.parent!;

  void _initializeFields() {
    _openingMorning = snapshotData['opening_morning'] as DateTime?;
    _closingMorning = snapshotData['closing_morning'] as DateTime?;
    _openingAfternoon = snapshotData['opening_afternoon'] as DateTime?;
    _closingAfternoon = snapshotData['closing_afternoon'] as DateTime?;
    _closingEvent = getDataList(snapshotData['closing_event']);
    _openingDay = snapshotData['opening_day'] as DateTime?;
    _closingDay = snapshotData['closing_day'] as DateTime?;
    _isFullDay = snapshotData['is_full_day'] as bool?;
    _isOpen = snapshotData['is_open'] as bool?;
    _day = snapshotData['day'] is DayOfTheWeek
        ? snapshotData['day']
        : deserializeEnum<DayOfTheWeek>(snapshotData['day']);
    _createdTime = snapshotData['created_time'] as DateTime?;
    _order = castToType<int>(snapshotData['order']);
  }

  static Query<Map<String, dynamic>> collection([DocumentReference? parent]) =>
      parent != null
          ? parent.collection('horaires')
          : FirebaseFirestore.instance.collectionGroup('horaires');

  static DocumentReference createDoc(DocumentReference parent, {String? id}) =>
      parent.collection('horaires').doc(id);

  static Stream<HorairesRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => HorairesRecord.fromSnapshot(s));

  static Future<HorairesRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => HorairesRecord.fromSnapshot(s));

  static HorairesRecord fromSnapshot(DocumentSnapshot snapshot) =>
      HorairesRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static HorairesRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      HorairesRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'HorairesRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is HorairesRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createHorairesRecordData({
  DateTime? openingMorning,
  DateTime? closingMorning,
  DateTime? openingAfternoon,
  DateTime? closingAfternoon,
  DateTime? openingDay,
  DateTime? closingDay,
  bool? isFullDay,
  bool? isOpen,
  DayOfTheWeek? day,
  DateTime? createdTime,
  int? order,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'opening_morning': openingMorning,
      'closing_morning': closingMorning,
      'opening_afternoon': openingAfternoon,
      'closing_afternoon': closingAfternoon,
      'opening_day': openingDay,
      'closing_day': closingDay,
      'is_full_day': isFullDay,
      'is_open': isOpen,
      'day': day,
      'created_time': createdTime,
      'order': order,
    }.withoutNulls,
  );

  return firestoreData;
}

class HorairesRecordDocumentEquality implements Equality<HorairesRecord> {
  const HorairesRecordDocumentEquality();

  @override
  bool equals(HorairesRecord? e1, HorairesRecord? e2) {
    const listEquality = ListEquality();
    return e1?.openingMorning == e2?.openingMorning &&
        e1?.closingMorning == e2?.closingMorning &&
        e1?.openingAfternoon == e2?.openingAfternoon &&
        e1?.closingAfternoon == e2?.closingAfternoon &&
        listEquality.equals(e1?.closingEvent, e2?.closingEvent) &&
        e1?.openingDay == e2?.openingDay &&
        e1?.closingDay == e2?.closingDay &&
        e1?.isFullDay == e2?.isFullDay &&
        e1?.isOpen == e2?.isOpen &&
        e1?.day == e2?.day &&
        e1?.createdTime == e2?.createdTime &&
        e1?.order == e2?.order;
  }

  @override
  int hash(HorairesRecord? e) => const ListEquality().hash([
        e?.openingMorning,
        e?.closingMorning,
        e?.openingAfternoon,
        e?.closingAfternoon,
        e?.closingEvent,
        e?.openingDay,
        e?.closingDay,
        e?.isFullDay,
        e?.isOpen,
        e?.day,
        e?.createdTime,
        e?.order
      ]);

  @override
  bool isValidKey(Object? o) => o is HorairesRecord;
}
