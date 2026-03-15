import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'inscription_identity_photo_page_widget.dart'
    show InscriptionIdentityPhotoPageWidget;
import 'package:flutter/material.dart';

class InscriptionIdentityPhotoPageModel
    extends FlutterFlowModel<InscriptionIdentityPhotoPageWidget> {
  ///  Local state fields for this page.

  FFUploadedFile? photoCarteIdentite;

  ///  State fields for stateful widgets in this page.

  bool isDataUploading_uploadDataSelfieCommercant = false;
  FFUploadedFile uploadedLocalFile_uploadDataSelfieCommercant =
      FFUploadedFile(bytes: Uint8List.fromList([]), originalFilename: '');

  bool isDataUploading_uploadDataPhotoIdentity = false;
  FFUploadedFile uploadedLocalFile_uploadDataPhotoIdentity =
      FFUploadedFile(bytes: Uint8List.fromList([]), originalFilename: '');
  String uploadedFileUrl_uploadDataPhotoIdentity = '';

  // Stores action output result for [Firestore Query - Query a collection] action in ButtonCarteIdentite widget.
  IdentityDocumentsRecord? result;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
