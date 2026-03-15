import '/backend/backend.dart';
import '/components/custom_nav_bar_commercant2_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'dart:async';
import 'home_commercant_page_widget.dart' show HomeCommercantPageWidget;
import 'package:flutter/material.dart';

class HomeCommercantPageModel
    extends FlutterFlowModel<HomeCommercantPageWidget> {
  ///  State fields for stateful widgets in this page.

  // State field(s) for TextField widget.
  FocusNode? textFieldFocusNode;
  TextEditingController? textController;
  String? Function(BuildContext, String?)? textControllerValidator;
  // Stores action output result for [Firestore Query - Query a collection] action in Button widget.
  PrizesRecord? resultPrize;
  Completer<List<GamesRecord>>? firestoreRequestCompleter;
  // Stores action output result for [Backend Call - Read Document] action in Container widget.
  EnseignesRecord? enseigneRef;
  // Model for CustomNavBarCommercant2 component.
  late CustomNavBarCommercant2Model customNavBarCommercant2Model;

  @override
  void initState(BuildContext context) {
    customNavBarCommercant2Model =
        createModel(context, () => CustomNavBarCommercant2Model());
  }

  @override
  void dispose() {
    textFieldFocusNode?.dispose();
    textController?.dispose();

    customNavBarCommercant2Model.dispose();
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
