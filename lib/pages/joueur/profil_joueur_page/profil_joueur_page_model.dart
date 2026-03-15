import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'profil_joueur_page_widget.dart' show ProfilJoueurPageWidget;
import 'package:flutter/material.dart';

class ProfilJoueurPageModel extends FlutterFlowModel<ProfilJoueurPageWidget> {
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
