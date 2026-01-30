import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/components/custom_nav_bar_admin_widget.dart';
import '/components/list_empty_component_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/index.dart';
import 'home_admin_page_widget.dart' show HomeAdminPageWidget;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class HomeAdminPageModel extends FlutterFlowModel<HomeAdminPageWidget> {
  ///  State fields for stateful widgets in this page.

  // Model for CustomNavBarAdmin component.
  late CustomNavBarAdminModel customNavBarAdminModel;

  @override
  void initState(BuildContext context) {
    customNavBarAdminModel =
        createModel(context, () => CustomNavBarAdminModel());
  }

  @override
  void dispose() {
    customNavBarAdminModel.dispose();
  }
}
