import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/index.dart';
import 'selected_auto_enseignes_for_add_game_commercant_page_widget.dart'
    show SelectedAutoEnseignesForAddGameCommercantPageWidget;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class SelectedAutoEnseignesForAddGameCommercantPageModel
    extends FlutterFlowModel<
        SelectedAutoEnseignesForAddGameCommercantPageWidget> {
  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Firestore Query - Query a collection] action in SelectedAutoEnseignesForAddGameCommercantPage widget.
  EnseignesRecord? enseigneRef;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
