import '/components/custom_nav_bar_commercant2_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'profil_commercant_page_widget.dart' show ProfilCommercantPageWidget;
import 'package:flutter/material.dart';

class ProfilCommercantPageModel
    extends FlutterFlowModel<ProfilCommercantPageWidget> {
  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Firestore Query - Query a collection] action in Container widget.
  int? deleteRequestCountResult;
  // Stores action output result for [Firestore Query - Query a collection] action in Container widget.
  int? resultEndGame;
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
