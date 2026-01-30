import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/firebase_storage/storage.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_animations.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/upload_data.dart';
import 'dart:math';
import 'dart:ui';
import '/index.dart';
import 'inscription_identity_photo_page_widget.dart'
    show InscriptionIdentityPhotoPageWidget;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

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
