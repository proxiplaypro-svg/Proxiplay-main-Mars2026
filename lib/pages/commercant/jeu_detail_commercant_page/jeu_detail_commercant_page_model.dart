import '/components/custom_nav_bar_commercant2_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'jeu_detail_commercant_page_widget.dart'
    show JeuDetailCommercantPageWidget;
import 'package:flutter/material.dart';

class JeuDetailCommercantPageModel
    extends FlutterFlowModel<JeuDetailCommercantPageWidget> {
  ///  State fields for stateful widgets in this page.

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
