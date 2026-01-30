import '/backend/schema/structs/index.dart';

class ParticipateInGameTransactionCloudFunctionCallResponse {
  ParticipateInGameTransactionCloudFunctionCallResponse({
    this.errorCode,
    this.succeeded,
    this.jsonBody,
    this.resultAsString,
    this.data,
  });
  String? errorCode;
  bool? succeeded;
  dynamic jsonBody;
  String? resultAsString;
  ResultParticipationGameStruct? data;
}

class DeleteEnseigneAndGamesCloudFunctionCallResponse {
  DeleteEnseigneAndGamesCloudFunctionCallResponse({
    this.errorCode,
    this.succeeded,
    this.jsonBody,
  });
  String? errorCode;
  bool? succeeded;
  dynamic jsonBody;
}

class DeleteCommercantAccountCloudFunctionCallResponse {
  DeleteCommercantAccountCloudFunctionCallResponse({
    this.errorCode,
    this.succeeded,
    this.jsonBody,
  });
  String? errorCode;
  bool? succeeded;
  dynamic jsonBody;
}
