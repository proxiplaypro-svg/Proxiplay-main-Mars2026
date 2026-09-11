import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'enseigne_detail_joueur_page_widget.dart'
    show EnseigneDetailJoueurPageWidget;
import 'package:flutter/material.dart';

class EnseigneDetailJoueurPageModel
    extends FlutterFlowModel<EnseigneDetailJoueurPageWidget> {
  late CustomNavBarJoueurModel customNavBarJoueurModel;
  int currentImageIndex = 0;

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
