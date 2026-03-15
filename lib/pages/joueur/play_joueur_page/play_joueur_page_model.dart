import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_rive_controller.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'play_joueur_page_widget.dart' show PlayJoueurPageWidget;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class PlayJoueurPageModel extends FlutterFlowModel<PlayJoueurPageWidget> {
  ///  Local state fields for this page.

  bool cardReveal = false;

  bool isWin = false;

  bool isScratching = false;
  bool hasPlayedScratchSound = false;
  bool isScratchSoundStarting = false;
  bool isScratchSoundPrimed = false;
  String? scratchSoundAssetPath;

  ///  State fields for stateful widgets in this page.

  AudioPlayer? scratchSoundPlayer;
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
    for (var name in riveAnimationAnimationsList) {
      riveAnimationControllers.add(FlutterFlowRiveController(
        name,
      ));
    }
  }

  @override
  void dispose() {
    scratchSoundPlayer?.dispose();
    soundPlayer?.dispose();
    customNavBarJoueurModel.dispose();
  }
}
