import '/backend/backend.dart';
import '/components/custom_nav_bar_commercant2_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'dart:async';
import 'stat_commercant_page_widget.dart' show StatCommercantPageWidget;
import 'package:flutter/material.dart';

class StatCommercantPageModel
    extends FlutterFlowModel<StatCommercantPageWidget> {
  ///  State fields for stateful widgets in this page.

  // State field(s) for TabBar widget.
  TabController? tabBarController;
  int get tabBarCurrentIndex =>
      tabBarController != null ? tabBarController!.index : 0;
  int get tabBarPreviousIndex =>
      tabBarController != null ? tabBarController!.previousIndex : 0;

  Completer<List<GamesRecord>>? firestoreRequestCompleter;
  // Stores action output result for [Backend Call - Read Document] action in Container widget.
  EnseignesRecord? enseigneRef2;
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
    tabBarController?.dispose();
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
