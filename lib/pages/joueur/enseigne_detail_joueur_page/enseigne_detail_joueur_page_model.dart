import '/backend/backend.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'dart:async';
import 'enseigne_detail_joueur_page_widget.dart'
    show EnseigneDetailJoueurPageWidget;
import 'package:flutter/material.dart';

class EnseigneDetailJoueurPageModel
    extends FlutterFlowModel<EnseigneDetailJoueurPageWidget> {
  ///  Local state fields for this page.

  DocumentReference? favRef;

  bool isAdult = false;

  ///  State fields for stateful widgets in this page.

  // Model for CustomNavBarJoueur component.
  late CustomNavBarJoueurModel customNavBarJoueurModel;
  Completer<List<HorairesRecord>>? firestoreRequestCompleter;
  
  // ScrollController for image carousel
  ScrollController? imagesScrollController;
  int currentImageIndex = 0;

  @override
  void initState(BuildContext context) {
    customNavBarJoueurModel =
        createModel(context, () => CustomNavBarJoueurModel());
  }

  @override
  void dispose() {
    customNavBarJoueurModel.dispose();
    imagesScrollController?.dispose();
  }

  /// Additional helper methods.
  Future waitForFirestoreRequestCompleted({
    double minWait = 0,
    double maxWait = 10000,
  }) async {
    final stopwatch = Stopwatch()..start();
    while (true) {
      await Future.delayed(const Duration(milliseconds: 50));
      final timeElapsed = stopwatch.elapsedMilliseconds;
      final requestComplete = firestoreRequestCompleter?.isCompleted ?? false;
      if (timeElapsed > maxWait || (requestComplete && timeElapsed > minWait)) {
        break;
      }
    }
  }
}
