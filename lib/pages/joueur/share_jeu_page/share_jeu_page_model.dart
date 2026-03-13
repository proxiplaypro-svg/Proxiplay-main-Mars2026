import '/backend/custom_cloud_functions/custom_cloud_function_response_manager.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'share_jeu_page_widget.dart' show ShareJeuPageWidget;
import 'package:flutter/material.dart';

class ShareJeuPageModel extends FlutterFlowModel<ShareJeuPageWidget> {
  ///  Local state fields for this page.

  DocumentReference? favRef;

  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Cloud Function - participateInGameTransaction] action in Button widget.
  ParticipateInGameTransactionCloudFunctionCallResponse? cloudFunction3sn;
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
