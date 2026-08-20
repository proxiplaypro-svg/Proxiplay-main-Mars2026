import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'parrainage_joueur_page_widget.dart' show ParrainageJoueurPageWidget;
import 'package:flutter/material.dart';

class ParrainageJoueurPageModel
    extends FlutterFlowModel<ParrainageJoueurPageWidget> {
  ///  State fields for stateful widgets in this page.

  // Model for CustomNavBarJoueur component.
  late CustomNavBarJoueurModel customNavBarJoueurModel;

  @override
  void initState(BuildContext context) {
    customNavBarJoueurModel =
        createModel(context, () => CustomNavBarJoueurModel());
  }

  @override
  void dispose() {
    customNavBarJoueurModel.dispose();
  }
}
