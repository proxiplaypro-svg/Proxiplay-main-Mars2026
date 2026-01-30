import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_rive_controller.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/custom_code/widgets/index.dart' as custom_widgets;
import '/index.dart';
import 'package:rive/rive.dart' hide LinearGradient;
import 'play_joueur_page_widget.dart' show PlayJoueurPageWidget;
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

class PlayJoueurPageModel extends FlutterFlowModel<PlayJoueurPageWidget> {
  ///  Local state fields for this page.

  bool cardReveal = false;

  bool isWin = false;

  ///  State fields for stateful widgets in this page.

  AudioPlayer? soundPlayer;
  // Model for CustomNavBarJoueur component.
  late CustomNavBarJoueurModel customNavBarJoueurModel;
  // State field(s) for RiveAnimation widget.
  final riveAnimationAnimationsList = [
    'Timeline 1',
  ];
  List<FlutterFlowRiveController> riveAnimationControllers = [];

  @override
  void initState(BuildContext context) {
    customNavBarJoueurModel =
        createModel(context, () => CustomNavBarJoueurModel());
    riveAnimationAnimationsList.forEach((name) {
      riveAnimationControllers.add(FlutterFlowRiveController(
        name,
      ));
    });
  }

  @override
  void dispose() {
    customNavBarJoueurModel.dispose();
  }
}
