// ignore_for_file: unnecessary_getters_setters

import 'package:cloud_firestore/cloud_firestore.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';
import '/backend/schema/enums/enums.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class HorairesStruct extends FFFirebaseStruct {
  HorairesStruct({
    bool? isClosing,
    FirestoreUtilData firestoreUtilData = const FirestoreUtilData(),
  })  : _isClosing = isClosing,
        super(firestoreUtilData);

  // "is_closing" field.
  bool? _isClosing;
  bool get isClosing => _isClosing ?? false;
  set isClosing(bool? val) => _isClosing = val;

  bool hasIsClosing() => _isClosing != null;

  static HorairesStruct fromMap(Map<String, dynamic> data) => HorairesStruct(
        isClosing: data['is_closing'] as bool?,
      );

  static HorairesStruct? maybeFromMap(dynamic data) =>
      data is Map ? HorairesStruct.fromMap(data.cast<String, dynamic>()) : null;

  Map<String, dynamic> toMap() => {
        'is_closing': _isClosing,
      }.withoutNulls;

  @override
  Map<String, dynamic> toSerializableMap() => {
        'is_closing': serializeParam(
          _isClosing,
          ParamType.bool,
        ),
      }.withoutNulls;

  static HorairesStruct fromSerializableMap(Map<String, dynamic> data) =>
      HorairesStruct(
        isClosing: deserializeParam(
          data['is_closing'],
          ParamType.bool,
          false,
        ),
      );

  @override
  String toString() => 'HorairesStruct(${toMap()})';

  @override
  bool operator ==(Object other) {
    return other is HorairesStruct && isClosing == other.isClosing;
  }

  @override
  int get hashCode => const ListEquality().hash([isClosing]);
}

HorairesStruct createHorairesStruct({
  bool? isClosing,
  Map<String, dynamic> fieldValues = const {},
  bool clearUnsetFields = true,
  bool create = false,
  bool delete = false,
}) =>
    HorairesStruct(
      isClosing: isClosing,
      firestoreUtilData: FirestoreUtilData(
        clearUnsetFields: clearUnsetFields,
        create: create,
        delete: delete,
        fieldValues: fieldValues,
      ),
    );

HorairesStruct? updateHorairesStruct(
  HorairesStruct? horaires, {
  bool clearUnsetFields = true,
  bool create = false,
}) =>
    horaires
      ?..firestoreUtilData = FirestoreUtilData(
        clearUnsetFields: clearUnsetFields,
        create: create,
      );

void addHorairesStructData(
  Map<String, dynamic> firestoreData,
  HorairesStruct? horaires,
  String fieldName, [
  bool forFieldValue = false,
]) {
  firestoreData.remove(fieldName);
  if (horaires == null) {
    return;
  }
  if (horaires.firestoreUtilData.delete) {
    firestoreData[fieldName] = FieldValue.delete();
    return;
  }
  final clearFields =
      !forFieldValue && horaires.firestoreUtilData.clearUnsetFields;
  if (clearFields) {
    firestoreData[fieldName] = <String, dynamic>{};
  }
  final horairesData = getHorairesFirestoreData(horaires, forFieldValue);
  final nestedData = horairesData.map((k, v) => MapEntry('$fieldName.$k', v));

  final mergeFields = horaires.firestoreUtilData.create || clearFields;
  firestoreData
      .addAll(mergeFields ? mergeNestedFields(nestedData) : nestedData);
}

Map<String, dynamic> getHorairesFirestoreData(
  HorairesStruct? horaires, [
  bool forFieldValue = false,
]) {
  if (horaires == null) {
    return {};
  }
  final firestoreData = mapToFirestore(horaires.toMap());

  // Add any Firestore field values
  horaires.firestoreUtilData.fieldValues
      .forEach((k, v) => firestoreData[k] = v);

  return forFieldValue ? mergeNestedFields(firestoreData) : firestoreData;
}

List<Map<String, dynamic>> getHorairesListFirestoreData(
  List<HorairesStruct>? horairess,
) =>
    horairess?.map((e) => getHorairesFirestoreData(e, true)).toList() ?? [];
