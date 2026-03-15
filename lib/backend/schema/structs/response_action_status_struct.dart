// ignore_for_file: unnecessary_getters_setters

import 'package:cloud_firestore/cloud_firestore.dart';

import '/backend/schema/util/firestore_util.dart';

import '/flutter_flow/flutter_flow_util.dart';

class ResponseActionStatusStruct extends FFFirebaseStruct {
  ResponseActionStatusStruct({
    String? status,
    String? message,
    FirestoreUtilData firestoreUtilData = const FirestoreUtilData(),
  })  : _status = status,
        _message = message,
        super(firestoreUtilData);

  // "status" field.
  String? _status;
  String get status => _status ?? '';
  set status(String? val) => _status = val;

  bool hasStatus() => _status != null;

  // "message" field.
  String? _message;
  String get message => _message ?? '';
  set message(String? val) => _message = val;

  bool hasMessage() => _message != null;

  static ResponseActionStatusStruct fromMap(Map<String, dynamic> data) =>
      ResponseActionStatusStruct(
        status: data['status'] as String?,
        message: data['message'] as String?,
      );

  static ResponseActionStatusStruct? maybeFromMap(dynamic data) => data is Map
      ? ResponseActionStatusStruct.fromMap(data.cast<String, dynamic>())
      : null;

  Map<String, dynamic> toMap() => {
        'status': _status,
        'message': _message,
      }.withoutNulls;

  @override
  Map<String, dynamic> toSerializableMap() => {
        'status': serializeParam(
          _status,
          ParamType.String,
        ),
        'message': serializeParam(
          _message,
          ParamType.String,
        ),
      }.withoutNulls;

  static ResponseActionStatusStruct fromSerializableMap(
          Map<String, dynamic> data) =>
      ResponseActionStatusStruct(
        status: deserializeParam(
          data['status'],
          ParamType.String,
          false,
        ),
        message: deserializeParam(
          data['message'],
          ParamType.String,
          false,
        ),
      );

  @override
  String toString() => 'ResponseActionStatusStruct(${toMap()})';

  @override
  bool operator ==(Object other) {
    return other is ResponseActionStatusStruct &&
        status == other.status &&
        message == other.message;
  }

  @override
  int get hashCode => const ListEquality().hash([status, message]);
}

ResponseActionStatusStruct createResponseActionStatusStruct({
  String? status,
  String? message,
  Map<String, dynamic> fieldValues = const {},
  bool clearUnsetFields = true,
  bool create = false,
  bool delete = false,
}) =>
    ResponseActionStatusStruct(
      status: status,
      message: message,
      firestoreUtilData: FirestoreUtilData(
        clearUnsetFields: clearUnsetFields,
        create: create,
        delete: delete,
        fieldValues: fieldValues,
      ),
    );

ResponseActionStatusStruct? updateResponseActionStatusStruct(
  ResponseActionStatusStruct? responseActionStatus, {
  bool clearUnsetFields = true,
  bool create = false,
}) =>
    responseActionStatus
      ?..firestoreUtilData = FirestoreUtilData(
        clearUnsetFields: clearUnsetFields,
        create: create,
      );

void addResponseActionStatusStructData(
  Map<String, dynamic> firestoreData,
  ResponseActionStatusStruct? responseActionStatus,
  String fieldName, [
  bool forFieldValue = false,
]) {
  firestoreData.remove(fieldName);
  if (responseActionStatus == null) {
    return;
  }
  if (responseActionStatus.firestoreUtilData.delete) {
    firestoreData[fieldName] = FieldValue.delete();
    return;
  }
  final clearFields =
      !forFieldValue && responseActionStatus.firestoreUtilData.clearUnsetFields;
  if (clearFields) {
    firestoreData[fieldName] = <String, dynamic>{};
  }
  final responseActionStatusData =
      getResponseActionStatusFirestoreData(responseActionStatus, forFieldValue);
  final nestedData =
      responseActionStatusData.map((k, v) => MapEntry('$fieldName.$k', v));

  final mergeFields =
      responseActionStatus.firestoreUtilData.create || clearFields;
  firestoreData
      .addAll(mergeFields ? mergeNestedFields(nestedData) : nestedData);
}

Map<String, dynamic> getResponseActionStatusFirestoreData(
  ResponseActionStatusStruct? responseActionStatus, [
  bool forFieldValue = false,
]) {
  if (responseActionStatus == null) {
    return {};
  }
  final firestoreData = mapToFirestore(responseActionStatus.toMap());

  // Add any Firestore field values
  responseActionStatus.firestoreUtilData.fieldValues
      .forEach((k, v) => firestoreData[k] = v);

  return forFieldValue ? mergeNestedFields(firestoreData) : firestoreData;
}

List<Map<String, dynamic>> getResponseActionStatusListFirestoreData(
  List<ResponseActionStatusStruct>? responseActionStatuss,
) =>
    responseActionStatuss
        ?.map((e) => getResponseActionStatusFirestoreData(e, true))
        .toList() ??
    [];
