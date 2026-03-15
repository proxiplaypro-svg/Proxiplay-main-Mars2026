import '/backend/backend.dart';
import '/backend/custom_cloud_functions/custom_cloud_function_response_manager.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'dart:async';
import 'jeu_detail_joueur_page_widget.dart' show JeuDetailJoueurPageWidget;
import 'package:flutter/material.dart';

class JeuDetailJoueurPageModel
    extends FlutterFlowModel<JeuDetailJoueurPageWidget> {
  ///  Local state fields for this page.

  DocumentReference? favRef;

  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Cloud Function - participateInGameTransaction] action in Button widget.
  ParticipateInGameTransactionCloudFunctionCallResponse? cloudFunction3sn;
  // Stores action output result for [Cloud Function - participateInGameTransaction] action in Button widget.
  ParticipateInGameTransactionCloudFunctionCallResponse? cloudFunction3sn2;
  // Model for CustomNavBarJoueur component.
  late CustomNavBarJoueurModel customNavBarJoueurModel;
  Completer<List<ImagesRecord>>? firestoreRequestCompleter;

  @override
  void initState(BuildContext context) {
    customNavBarJoueurModel =
        createModel(context, () => CustomNavBarJoueurModel());
  }

  @override
  void dispose() {
    customNavBarJoueurModel.dispose();
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
