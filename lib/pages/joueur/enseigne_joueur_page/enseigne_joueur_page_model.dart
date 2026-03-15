import '/backend/backend.dart';
import '/components/app_bar_joueur_widget.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'enseigne_joueur_page_widget.dart' show EnseigneJoueurPageWidget;
import 'package:flutter/material.dart';

class EnseigneJoueurPageModel
    extends FlutterFlowModel<EnseigneJoueurPageWidget> {
  ///  Local state fields for this page.

  bool searchActive = false;

  ///  State fields for stateful widgets in this page.

  // State field(s) for TextField widget.
  FocusNode? textFieldFocusNode;
  TextEditingController? textController;
  String? Function(BuildContext, String?)? textControllerValidator;
  List<EnseignesRecord> simpleSearchResults = [];
  // Model for CustomNavBarJoueur component.
  late CustomNavBarJoueurModel customNavBarJoueurModel;
  // Model for appBarJoueur component.
  late AppBarJoueurModel appBarJoueurModel;

  @override
  void initState(BuildContext context) {
    customNavBarJoueurModel =
        createModel(context, () => CustomNavBarJoueurModel());
    appBarJoueurModel = createModel(context, () => AppBarJoueurModel());
  }

  @override
  void dispose() {
    textFieldFocusNode?.dispose();
    textController?.dispose();

    customNavBarJoueurModel.dispose();
    appBarJoueurModel.dispose();
  }
}
