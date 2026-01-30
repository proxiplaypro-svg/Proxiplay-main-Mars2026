import '/backend/backend.dart';
import '/backend/firebase_storage/storage.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/upload_data.dart';
import 'dart:ui';
import '/custom_code/actions/index.dart' as actions;
import 'photo_enseigne_commercant_page_widget.dart'
    show PhotoEnseigneCommercantPageWidget;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class PhotoEnseigneCommercantPageModel
    extends FlutterFlowModel<PhotoEnseigneCommercantPageWidget> {
  ///  State fields for stateful widgets in this page.

  bool isDataUploading_uploadDataUpdate = false;
  List<FFUploadedFile> uploadedLocalFiles_uploadDataUpdate = [];

  bool isDataUploading_uploadDataUpdatePhoto = false;
  List<FFUploadedFile> uploadedLocalFiles_uploadDataUpdatePhoto = [];
  List<String> uploadedFileUrls_uploadDataUpdatePhoto = [];

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
