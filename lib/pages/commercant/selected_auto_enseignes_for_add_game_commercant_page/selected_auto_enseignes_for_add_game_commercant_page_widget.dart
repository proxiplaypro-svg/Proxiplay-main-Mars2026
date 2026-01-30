import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/index.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'selected_auto_enseignes_for_add_game_commercant_page_model.dart';
export 'selected_auto_enseignes_for_add_game_commercant_page_model.dart';

class SelectedAutoEnseignesForAddGameCommercantPageWidget
    extends StatefulWidget {
  const SelectedAutoEnseignesForAddGameCommercantPageWidget({super.key});

  static String routeName = 'SelectedAutoEnseignesForAddGameCommercantPage';
  static String routePath = 'selectedAutoEnseignesForAddGameCommercantPage';

  @override
  State<SelectedAutoEnseignesForAddGameCommercantPageWidget> createState() =>
      _SelectedAutoEnseignesForAddGameCommercantPageWidgetState();
}

class _SelectedAutoEnseignesForAddGameCommercantPageWidgetState
    extends State<SelectedAutoEnseignesForAddGameCommercantPageWidget> {
  late SelectedAutoEnseignesForAddGameCommercantPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(
        context, () => SelectedAutoEnseignesForAddGameCommercantPageModel());

    logFirebaseEvent('screen_view', parameters: {
      'screen_name': 'SelectedAutoEnseignesForAddGameCommercan'
    });
    // On page load action.
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      _model.enseigneRef = await queryEnseignesRecordOnce(
        queryBuilder: (enseignesRecord) => enseignesRecord.where(
          'owner',
          isEqualTo: currentUserReference,
        ),
        singleRecord: true,
      ).then((s) => s.firstOrNull);
      if (Navigator.of(context).canPop()) {
        context.pop();
      }
      context.pushNamed(
        AddGameCommercantPageWidget.routeName,
        queryParameters: {
          'enseigneRef': serializeParam(
            _model.enseigneRef?.reference,
            ParamType.DocumentReference,
          ),
          'enseigne': serializeParam(
            _model.enseigneRef?.name,
            ParamType.String,
          ),
        }.withoutNulls,
        extra: <String, dynamic>{
          kTransitionInfoKey: TransitionInfo(
            hasTransition: true,
            transitionType: PageTransitionType.fade,
            duration: Duration(milliseconds: 0),
          ),
        },
      );
    });
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      ),
    );
  }
}
