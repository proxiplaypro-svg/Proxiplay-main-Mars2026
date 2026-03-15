import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'inscription_identity_card_page_widget.dart'
    show InscriptionIdentityCardPageWidget;
import 'package:flutter/material.dart';

class InscriptionIdentityCardPageModel
    extends FlutterFlowModel<InscriptionIdentityCardPageWidget> {
  ///  Local state fields for this page.

  FFUploadedFile? photoCarteIdentite;

  ///  State fields for stateful widgets in this page.

  bool isDataUploading_uploadDataIdentityCard = false;
  FFUploadedFile uploadedLocalFile_uploadDataIdentityCard =
      FFUploadedFile(bytes: Uint8List.fromList([]), originalFilename: '');

  bool isDataUploading_uploadDataCardIdentity = false;
  FFUploadedFile uploadedLocalFile_uploadDataCardIdentity =
      FFUploadedFile(bytes: Uint8List.fromList([]), originalFilename: '');
  String uploadedFileUrl_uploadDataCardIdentity = '';

  // Stores action output result for [Firestore Query - Query a collection] action in ButtonCarteIdentite widget.
  IdentityDocumentsRecord? result;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
