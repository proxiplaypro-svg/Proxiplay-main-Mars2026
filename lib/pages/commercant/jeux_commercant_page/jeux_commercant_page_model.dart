import '/backend/backend.dart';
import '/components/custom_nav_bar_commercant2_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'jeux_commercant_page_widget.dart' show JeuxCommercantPageWidget;
import 'package:flutter/material.dart';

class JeuxCommercantPageModel
    extends FlutterFlowModel<JeuxCommercantPageWidget> {
  ///  State fields for stateful widgets in this page.

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
    customNavBarCommercant2Model.dispose();
  }
}
