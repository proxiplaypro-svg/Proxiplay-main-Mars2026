import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/components/custom_nav_bar_commercant2_widget.dart';
import '/components/list_empty_component_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/index.dart';
import 'mes_enseignes_commercant_page_widget.dart'
    show MesEnseignesCommercantPageWidget;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class MesEnseignesCommercantPageModel
    extends FlutterFlowModel<MesEnseignesCommercantPageWidget> {
  ///  State fields for stateful widgets in this page.

  // Model for ListEmptyComponent component.
  late ListEmptyComponentModel listEmptyComponentModel;
  // Model for CustomNavBarCommercant2 component.
  late CustomNavBarCommercant2Model customNavBarCommercant2Model;

  @override
  void initState(BuildContext context) {
    listEmptyComponentModel =
        createModel(context, () => ListEmptyComponentModel());
    customNavBarCommercant2Model =
        createModel(context, () => CustomNavBarCommercant2Model());
  }

  @override
  void dispose() {
    listEmptyComponentModel.dispose();
    customNavBarCommercant2Model.dispose();
  }
}
