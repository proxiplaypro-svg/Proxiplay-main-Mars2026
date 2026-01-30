import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/index.dart';
import 'partage_jeu_joueur_page_widget.dart' show PartageJeuJoueurPageWidget;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class PartageJeuJoueurPageModel
    extends FlutterFlowModel<PartageJeuJoueurPageWidget> {
  ///  Local state fields for this page.

  DocumentReference? favRef;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
