import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'partage_jeu_joueur_page_model.dart';
export 'partage_jeu_joueur_page_model.dart';

/// remplir le container sous l'image par une liste de text
class PartageJeuJoueurPageWidget extends StatefulWidget {
  const PartageJeuJoueurPageWidget({
    super.key,
    required this.gameDoc,
    required this.enseigneDoc,
  });

  final GamesRecord? gameDoc;
  final EnseignesRecord? enseigneDoc;

  static String routeName = 'PartageJeuJoueurPage';
  static String routePath = 'partageJeuJoueurPage';

  @override
  State<PartageJeuJoueurPageWidget> createState() =>
      _PartageJeuJoueurPageWidgetState();
}

class _PartageJeuJoueurPageWidgetState
    extends State<PartageJeuJoueurPageWidget> {
  late PartageJeuJoueurPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => PartageJeuJoueurPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'PartageJeuJoueurPage'});
    // On page load action.
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      context.pushNamed(
        JeuDetailJoueurPageWidget.routeName,
        queryParameters: {
          'gameDoc': serializeParam(
            widget.gameDoc,
            ParamType.Document,
          ),
          'enseigneDoc': serializeParam(
            widget.enseigneDoc,
            ParamType.Document,
          ),
        }.withoutNulls,
        extra: <String, dynamic>{
          'gameDoc': widget.gameDoc,
          'enseigneDoc': widget.enseigneDoc,
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
