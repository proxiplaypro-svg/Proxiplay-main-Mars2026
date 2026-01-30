// ignore_for_file: unnecessary_getters_setters

import 'package:cloud_firestore/cloud_firestore.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';
import '/backend/schema/enums/enums.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class ResultParticipationGameStruct extends FFFirebaseStruct {
  ResultParticipationGameStruct({
    String? message,
    bool? isWin,
    String? messageBonus,
    String? prizeId,
    FirestoreUtilData firestoreUtilData = const FirestoreUtilData(),
  })  : _message = message,
        _isWin = isWin,
        _messageBonus = messageBonus,
        _prizeId = prizeId,
        super(firestoreUtilData);

  // "message" field.
  String? _message;
  String get message => _message ?? '';
  set message(String? val) => _message = val;

  bool hasMessage() => _message != null;

  // "isWin" field.
  bool? _isWin;
  bool get isWin => _isWin ?? false;
  set isWin(bool? val) => _isWin = val;

  bool hasIsWin() => _isWin != null;

  // "messageBonus" field.
  String? _messageBonus;
  String get messageBonus => _messageBonus ?? '';
  set messageBonus(String? val) => _messageBonus = val;

  bool hasMessageBonus() => _messageBonus != null;

  // "prize_id" field.
  String? _prizeId;
  String get prizeId => _prizeId ?? '';
  set prizeId(String? val) => _prizeId = val;

  bool hasPrizeId() => _prizeId != null;

  static ResultParticipationGameStruct fromMap(Map<String, dynamic> data) =>
      ResultParticipationGameStruct(
        message: data['message'] as String?,
        isWin: data['isWin'] as bool?,
        messageBonus: data['messageBonus'] as String?,
        prizeId: data['prize_id'] as String?,
      );

  static ResultParticipationGameStruct? maybeFromMap(dynamic data) =>
      data is Map
          ? ResultParticipationGameStruct.fromMap(data.cast<String, dynamic>())
          : null;

  Map<String, dynamic> toMap() => {
        'message': _message,
        'isWin': _isWin,
        'messageBonus': _messageBonus,
        'prize_id': _prizeId,
      }.withoutNulls;

  @override
  Map<String, dynamic> toSerializableMap() => {
        'message': serializeParam(
          _message,
          ParamType.String,
        ),
        'isWin': serializeParam(
          _isWin,
          ParamType.bool,
        ),
        'messageBonus': serializeParam(
          _messageBonus,
          ParamType.String,
        ),
        'prize_id': serializeParam(
          _prizeId,
          ParamType.String,
        ),
      }.withoutNulls;

  static ResultParticipationGameStruct fromSerializableMap(
          Map<String, dynamic> data) =>
      ResultParticipationGameStruct(
        message: deserializeParam(
          data['message'],
          ParamType.String,
          false,
        ),
        isWin: deserializeParam(
          data['isWin'],
          ParamType.bool,
          false,
        ),
        messageBonus: deserializeParam(
          data['messageBonus'],
          ParamType.String,
          false,
        ),
        prizeId: deserializeParam(
          data['prize_id'],
          ParamType.String,
          false,
        ),
      );

  @override
  String toString() => 'ResultParticipationGameStruct(${toMap()})';

  @override
  bool operator ==(Object other) {
    return other is ResultParticipationGameStruct &&
        message == other.message &&
        isWin == other.isWin &&
        messageBonus == other.messageBonus &&
        prizeId == other.prizeId;
  }

  @override
  int get hashCode =>
      const ListEquality().hash([message, isWin, messageBonus, prizeId]);
}

ResultParticipationGameStruct createResultParticipationGameStruct({
  String? message,
  bool? isWin,
  String? messageBonus,
  String? prizeId,
  Map<String, dynamic> fieldValues = const {},
  bool clearUnsetFields = true,
  bool create = false,
  bool delete = false,
}) =>
    ResultParticipationGameStruct(
      message: message,
      isWin: isWin,
      messageBonus: messageBonus,
      prizeId: prizeId,
      firestoreUtilData: FirestoreUtilData(
        clearUnsetFields: clearUnsetFields,
        create: create,
        delete: delete,
        fieldValues: fieldValues,
      ),
    );

ResultParticipationGameStruct? updateResultParticipationGameStruct(
  ResultParticipationGameStruct? resultParticipationGame, {
  bool clearUnsetFields = true,
  bool create = false,
}) =>
    resultParticipationGame
      ?..firestoreUtilData = FirestoreUtilData(
        clearUnsetFields: clearUnsetFields,
        create: create,
      );

void addResultParticipationGameStructData(
  Map<String, dynamic> firestoreData,
  ResultParticipationGameStruct? resultParticipationGame,
  String fieldName, [
  bool forFieldValue = false,
]) {
  firestoreData.remove(fieldName);
  if (resultParticipationGame == null) {
    return;
  }
  if (resultParticipationGame.firestoreUtilData.delete) {
    firestoreData[fieldName] = FieldValue.delete();
    return;
  }
  final clearFields = !forFieldValue &&
      resultParticipationGame.firestoreUtilData.clearUnsetFields;
  if (clearFields) {
    firestoreData[fieldName] = <String, dynamic>{};
  }
  final resultParticipationGameData = getResultParticipationGameFirestoreData(
      resultParticipationGame, forFieldValue);
  final nestedData =
      resultParticipationGameData.map((k, v) => MapEntry('$fieldName.$k', v));

  final mergeFields =
      resultParticipationGame.firestoreUtilData.create || clearFields;
  firestoreData
      .addAll(mergeFields ? mergeNestedFields(nestedData) : nestedData);
}

Map<String, dynamic> getResultParticipationGameFirestoreData(
  ResultParticipationGameStruct? resultParticipationGame, [
  bool forFieldValue = false,
]) {
  if (resultParticipationGame == null) {
    return {};
  }
  final firestoreData = mapToFirestore(resultParticipationGame.toMap());

  // Add any Firestore field values
  resultParticipationGame.firestoreUtilData.fieldValues
      .forEach((k, v) => firestoreData[k] = v);

  return forFieldValue ? mergeNestedFields(firestoreData) : firestoreData;
}

List<Map<String, dynamic>> getResultParticipationGameListFirestoreData(
  List<ResultParticipationGameStruct>? resultParticipationGames,
) =>
    resultParticipationGames
        ?.map((e) => getResultParticipationGameFirestoreData(e, true))
        .toList() ??
    [];
