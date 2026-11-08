import '/components/app_bar_joueur_widget.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'enseigne_joueur_page_widget.dart' show EnseigneJoueurPageWidget;
import 'package:flutter/material.dart';

/// Search, filters and pagination live in MerchantDirectoryView.
class EnseigneJoueurPageModel
    extends FlutterFlowModel<EnseigneJoueurPageWidget> {
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
    customNavBarJoueurModel.dispose();
    appBarJoueurModel.dispose();
  }
}
