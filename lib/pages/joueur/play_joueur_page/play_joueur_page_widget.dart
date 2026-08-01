import '/backend/backend.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/utils/share_links.dart';
import '/widgets/proxiplay_network_image.dart';
import '/widgets/tap_feedback.dart';
import 'dart:convert';
import 'dart:ui';
import '/custom_code/widgets/index.dart' as custom_widgets;
import '/index.dart';
import 'package:rive/rive.dart' hide Image, LinearGradient;
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:math';
import 'play_joueur_page_model.dart';
export 'play_joueur_page_model.dart';

class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// page qui permet a un utilisateur de faire un jeu a gratter et voir si il a
/// gagne un lot secondaire / regle du jeu en dessous et prevenir que le lot
/// principal sera gagne par tirage au sort a la date de fin du jeu
class PlayJoueurPageWidget extends StatefulWidget {
  const PlayJoueurPageWidget({
    super.key,
    required this.game,
    required this.resultParticipation,
    this.source,
    this.attemptId,
    this.onGameScreenMounted,
  });

  final GamesRecord? game;
  final ResultParticipationGameStruct? resultParticipation;
  final String? source;
  final String? attemptId;

  /// Called once, after this screen has rendered its first frame. Used by
  /// launch callers (see `GameLaunchCoordinator`) as the closest available
  /// proxy for "the player actually saw the game" — it does NOT gate the
  /// server-side participation, which is already committed by the time this
  /// widget is even constructed, but it lets callers log/detect the cases
  /// where the screen never made it to the player.
  final VoidCallback? onGameScreenMounted;

  static String routeName = 'playJoueurPage';
  static String routePath = 'playJoueurPage';

  @override
  State<PlayJoueurPageWidget> createState() => _PlayJoueurPageWidgetState();
}

class _PlayJoueurPageWidgetState extends State<PlayJoueurPageWidget> {
  static const List<String> _messagesTirage = [
    'Participation validée. Rendez-vous au tirage final !',
    'Ta participation est enregistrée pour le tirage au sort.',
    'Tu es bien inscrit(e) au tirage final, patience !',
  ];

  static const List<String> _messagesInstant = [
    'Rien pour cette fois, retente ta chance demain !',
    'La chance peut te sourire à chaque instant !',
    'Une autre fois sûrement !',
  ];

  late PlayJoueurPageModel _model;
  String? _resultMessage;
  String? _resultMessageBonus;
  bool _isPreparingShare = false;
  bool _isShareDialogVisible = false;
  late String _preparedShareText;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  bool hasMainPrize(GamesRecord game) {
    if (game.hasHasMainPrize()) {
      return game.hasMainPrize;
    }

    return game.prizeValue > 0;
  }

  String _pickDisplayMessage(List<String> messages) {
    if (messages.isEmpty) {
      return '';
    }
    final randomIndex = Random().nextInt(messages.length);
    _logPlayPageTrace(
      'play_page_message_pool_pick',
      detail:
          'poolSize=${messages.length} randomIndex=$randomIndex picked=${messages[randomIndex]}',
    );
    return messages[randomIndex];
  }

  String _resolveDisplayMessage() {
    final backendMessage = (widget.resultParticipation?.message ?? '').trim();
    final isWin = widget.resultParticipation?.isWin == true;

    _logPlayPageTrace(
      'play_page_resolve_display_message_enter',
      detail:
          'backendMessage=$backendMessage isWin=$isWin messageBonus=${widget.resultParticipation?.messageBonus ?? ''}',
    );

    if (isWin && backendMessage.isNotEmpty) {
      _logPlayPageTrace(
        'play_page_resolve_display_message_return',
        detail: 'reason=backend_win_message value=$backendMessage',
      );
      return backendMessage;
    }

    final lowerBackendMessage = backendMessage.toLowerCase();
    final isAlreadyPlayedStatusMessage =
        lowerBackendMessage.contains('dï¿½jï¿½ participï¿½') ||
            lowerBackendMessage.contains('deja participe');
    final isBackendStatusMessage = isAlreadyPlayedStatusMessage ||
        lowerBackendMessage.contains('plus de parties');
    if (isBackendStatusMessage) {
      if (isAlreadyPlayedStatusMessage) {
        const normalizedAlreadyPlayedMessage =
            'Vous avez dï¿½jï¿½ participï¿½ ï¿½ ce jeu.';
        _logPlayPageTrace(
          'play_page_resolve_display_message_return',
          detail:
              'reason=normalized_already_played_message value=$normalizedAlreadyPlayedMessage',
        );
        return normalizedAlreadyPlayedMessage;
      }
      _logPlayPageTrace(
        'play_page_resolve_display_message_return',
        detail: 'reason=backend_status_message value=$backendMessage',
      );
      return backendMessage;
    }

    final game = widget.game;
    final mainPrize = game != null && hasMainPrize(game);
    final messages = mainPrize ? _messagesTirage : _messagesInstant;
    final pickedMessage = _pickDisplayMessage(messages);
    _logPlayPageTrace(
      'play_page_resolve_display_message_return',
      detail:
          'reason=random_pool mainPrize=$mainPrize value=$pickedMessage',
    );
    return pickedMessage;
  }

  Future<void> _shareGame() async {
    if (_isPreparingShare) {
      return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    safeSetState(() {
      _isPreparingShare = true;
    });

    try {
      if (!mounted) {
        return;
      }
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) {
              _logPlayPageTrace(
                'play_page_share_dialog_pop_scope_invoked',
                detail: 'didPop=$didPop canPop=false',
              );
            },
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 18.0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20.0,
                      height: 20.0,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: FlutterFlowTheme.of(context).primary,
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Flexible(
                      child: Text(
                        'Prï¿½paration du partage...',
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                              font: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .fontStyle,
                              ),
                              letterSpacing: 0.0,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      _isShareDialogVisible = true;
      _logPlayPageTrace(
        'play_page_share_future_delayed_before',
        detail: 'durationMs=16',
      );
      await Future<void>.delayed(const Duration(milliseconds: 16));
      _logPlayPageTrace(
        'play_page_share_future_delayed_after',
        detail: 'durationMs=16',
      );
      if (!mounted) {
        return;
      }
      await Share.share(
        _preparedShareText,
        sharePositionOrigin: getWidgetBoundingBox(context),
      );
    } finally {
      if (_isShareDialogVisible && navigator.mounted && navigator.canPop()) {
        _logPlayPagePop('share_dialog_navigator.pop_finally');
        navigator.pop();
        _isShareDialogVisible = false;
      }
      if (mounted) {
        safeSetState(() {
          _isPreparingShare = false;
        });
      }
    }
  }

  Future<void> _primeScratchSound() async {
    _model.scratchSoundPlayer ??= AudioPlayer();
    const scratchCandidates = [
      'assets/audios/scratch.mp3',
      'assets/audios/171670__leszek_szary__success-2.wav',
    ];

    try {
      await _model.scratchSoundPlayer!.setVolume(1.0);
      await _model.scratchSoundPlayer!.setLoopMode(LoopMode.one);
      for (final assetPath in scratchCandidates) {
        try {
          await _model.scratchSoundPlayer!.setAsset(assetPath);
          _model.scratchSoundAssetPath = assetPath;
          _model.isScratchSoundPrimed = true;
          return;
        } catch (_) {}
      }
      _model.isScratchSoundPrimed = false;
    } catch (e) {
      _model.isScratchSoundPrimed = false;
      debugPrint('Scratch sound preload failed: $e');
    }
  }

  Future<void> _startScratchSound() async {
    if (_model.isScratchSoundStarting) return;
    _model.isScratchSoundStarting = true;

    try {
      if (!_model.isScratchSoundPrimed) {
        await _primeScratchSound();
      }
      if (!_model.isScratchSoundPrimed) {
        _model.isScratchSoundStarting = false;
        return;
      }

      if (!(_model.scratchSoundPlayer?.playing ?? false)) {
        await _model.scratchSoundPlayer!.play();
      }
      _model.isScratchSoundStarting = false;
    } catch (e) {
      _model.isScratchSoundStarting = false;
      debugPrint('Scratch sound start failed: $e');
    }
  }

  Future<void> _stopScratchSound() async {
    try {
      if (_model.scratchSoundPlayer?.playing ?? false) {
        await _model.scratchSoundPlayer!.pause();
      }
    } catch (e) {
      debugPrint('Scratch sound stop failed: $e');
    }
  }

  String _firstNonEmptyString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String) {
        final normalized = value.trim();
        if (normalized.isNotEmpty) {
          return normalized;
        }
      }
    }
    return '';
  }

  String _normalizeFirstName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return '';
    return normalized.split(RegExp(r'\s+')).first;
  }

  String _sanitizeRewardText(String value) {
    if (value.trim().isEmpty) {
      return value;
    }
    var output = _tryDecodeMojibake(value);
    final replacements = <String, String>{
      'â€™': '\'',
      'â€˜': '\'',
      'â€œ': '"',
      'â€': '"',
      'â€¦': '...',
      'â€“': '-',
      'â€”': '-',
      'â‚¬': '\u20AC',
      '\u00C2\u00A0': ' ',
      '\u00A0': ' ',
      '\uFFFD': '',
    };
    replacements.forEach((source, target) {
      output = output.replaceAll(source, target);
    });
    output = output.replaceAll(
        RegExp(r'[^\u0009\u000A\u000D\u0020-\u007E\u00A0-\u00FF\u20AC]'), '');
    output = output.replaceAll(RegExp(r'\s+'), ' ');
    output = output.replaceFirst(RegExp(r'^[^A-Za-zï¿½-ï¿½ï¿½-ï¿½ï¿½-ï¿½0-9]+'), '');
    return output.trim();
  }

  String _tryDecodeMojibake(String input) {
    final hasMojibakeMarkers =
        input.contains('ï¿½') || input.contains('ï¿½') || input.contains('ï¿½');
    if (!hasMojibakeMarkers) {
      return input;
    }
    try {
      return utf8.decode(latin1.encode(input));
    } catch (_) {
      return input;
    }
  }

  DocumentReference? _extractWinnerRef(Map<String, dynamic> gameData) {
    final candidates = [
      gameData['main_prize_winner'],
      gameData['winnerUserRef'],
      gameData['winner_user_ref'],
      gameData['winner_id'],
      gameData['winnerRef'],
    ];

    for (final candidate in candidates) {
      if (candidate is DocumentReference) {
        return candidate;
      }
    }
    return null;
  }

  Map<String, String> _extractWinnerDisplayFromGameData(
      Map<String, dynamic> gameData) {
    final firstName = _normalizeFirstName(
      _firstNonEmptyString(gameData, [
        'winnerFirstName',
        'winner_first_name',
        'winnerName',
        'winner_name',
        'winner_name_first',
      ]),
    );

    final city = _firstNonEmptyString(gameData, [
      'winnerCity',
      'winner_city',
      'winnerVille',
      'winner_ville',
      'winnerTown',
      'winner_town',
    ]);

    return {
      'firstName': firstName,
      'city': city,
    };
  }

  Map<String, String> _extractWinnerDisplayFromUser(UsersRecord? userRecord) {
    if (userRecord == null) {
      return {'firstName': '', 'city': ''};
    }
    final firstName = _normalizeFirstName(
      userRecord.firstName.isNotEmpty
          ? userRecord.firstName
          : userRecord.pseudo,
    );
    final city = userRecord.city.trim();
    return {
      'firstName': firstName,
      'city': city,
    };
  }

  String capitalize(String? value) {
    if (value == null || value.isEmpty) return '';
    return value[0].toUpperCase() + value.substring(1).toLowerCase();
  }

  void _logPlayPageTrace(String stage, {String? detail}) {
  }

  void _logPlayPagePop(String reason) {
  }

  void _logPlayPageDispose() {
  }

  @override
  void initState() {
    super.initState();

    _model = createModel(context, () => PlayJoueurPageModel());
    _logPlayPageTrace(
      'play_page_initState',
      detail:
          'hasResultParticipation=${widget.resultParticipation != null} backendMessage=${widget.resultParticipation?.message ?? ''} messageBonus=${widget.resultParticipation?.messageBonus ?? ''} isWin=${widget.resultParticipation?.isWin == true} prizeId=${widget.resultParticipation?.prizeId ?? ''}',
    );
    _resultMessage = _sanitizeRewardText(_resolveDisplayMessage());
    _resultMessageBonus =
        _sanitizeRewardText(widget.resultParticipation?.messageBonus ?? '');
    _logPlayPageTrace(
      'play_page_result_text_initialized',
      detail:
          'resultMessage=${_resultMessage ?? ''} resultMessageBonus=${_resultMessageBonus ?? ''}',
    );
    _preparedShareText = buildAppShareText(
      title: '${widget.game?.name ?? 'ce jeu'} sur ProxiPlay',
    );

    _primeScratchSound();
    _logPlayPageTrace('play_page_addPostFrameCallback_registered');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logPlayPageTrace('play_page_addPostFrameCallback_invoked');
      if (!mounted) return;
      setState(() {});
      _logPlayPageTrace('play_page_first_frame_rendered');
      widget.onGameScreenMounted?.call();
    });
  }

  @override
  void dispose() {
    _logPlayPageDispose();
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Garde-fou : widget.game est nullable dans sa signature meme si le
    // flux normal ne le passe jamais null. Sans ce retour anticipe, tout
    // acces synchrone `widget.game!.xxx` plus bas planterait sans jamais
    // afficher la carte a gratter.
    if (widget.game == null) {
      debugPrint('[GAME_FLOW_DEBUG] play_page_missing_game_doc');
      return Scaffold(
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Impossible d'afficher ce jeu pour le moment.",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16.0),
                  TextButton(
                    onPressed: () {
                      _logPlayPagePop(
                        'missing_game_doc_return_button_context.safePop',
                      );
                      context.safePop();
                    },
                    child: const Text('Retour'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final rewardText = _resultMessage ?? '';
    final rewardTextBonus = _resultMessageBonus ?? '';
    final lowerBackendMessage =
        (widget.resultParticipation?.message ?? '').trim().toLowerCase();
    final isAlreadyPlayedStatus =
        lowerBackendMessage.contains('dï¿½jï¿½ participï¿½') ||
            lowerBackendMessage.contains('deja participe');
    final hasMainPrizeGame =
        widget.game != null ? hasMainPrize(widget.game!) : false;
    final mainPrizeDescription = (widget.game?.description ?? '').trim();
    final hasMainPrizeDescription = mainPrizeDescription.isNotEmpty;
    final isCompactHeight = MediaQuery.sizeOf(context).height < 1000.0;
    final now = DateTime.now();
    final endDate = widget.game?.endDate;
    final isGameEnded = endDate != null && now.isAfter(endDate);
    final gameData = widget.game?.snapshotData ?? const <String, dynamic>{};
    final winnerDisplayFromGame = _extractWinnerDisplayFromGameData(gameData);
    final winnerRef =
        widget.game?.mainPrizeWinner ?? _extractWinnerRef(gameData);
    final hasWinnerSignal = (widget.game?.hasWinner ?? false) ||
        winnerRef != null ||
        (winnerDisplayFromGame['firstName']?.isNotEmpty ?? false) ||
        (winnerDisplayFromGame['city']?.isNotEmpty ?? false);
    final shouldShowWinnerBlock = isGameEnded && hasWinnerSignal;
    final playPageBranch = shouldShowWinnerBlock
        ? 'winner_block'
        : isGameEnded
            ? 'game_ended_no_winner_block'
            : 'scratch_card';
    _logPlayPageTrace(
      'play_page_build_branch',
      detail:
          'branch=$playPageBranch isAlreadyPlayedStatus=$isAlreadyPlayedStatus isGameEnded=$isGameEnded hasWinnerSignal=$hasWinnerSignal isWin=${widget.resultParticipation?.isWin == true} backendMessage=${widget.resultParticipation?.message ?? ''} rewardText=$rewardText rewardTextBonus=$rewardTextBonus',
    );

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          _logPlayPageTrace(
            'play_page_pop_scope_invoked',
            detail: 'didPop=$didPop canPop=false',
          );
        },
        child: Scaffold(
          key: scaffoldKey,
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(104.0),
            child: AppBar(
              backgroundColor: Colors.transparent,
              automaticallyImplyLeading: false,
              elevation: 0.0,
              titleSpacing: 16.0,
              title: Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Row(
                  children: [
                    Container(
                      width: 48.0,
                      height: 48.0,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: TapFeedback(
                        enabled: true,
                        borderRadius: BorderRadius.circular(12.0),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 48.0, height: 48.0),
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18.0,
                          ),
                          color: FlutterFlowTheme.of(context).primary,
                          onPressed: () async {
                            _logPlayPagePop('appbar_back_button_context.safePop');
                            context.safePop();
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Image.asset(
                          'assets/images/logo_D_secondaire.png',
                          height: 40.0,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    Container(
                      width: 48.0,
                      height: 48.0,
                      decoration: BoxDecoration(
                        color: const Color(0xFFA0134D),
                        borderRadius: BorderRadius.circular(12.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 10.0,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TapFeedback(
                        enabled: true,
                        borderRadius: BorderRadius.circular(12.0),
                        child: IconButton(
                          icon: const Icon(Icons.share_rounded, size: 22.0),
                          color: Colors.white,
                          onPressed: () async {
                            await _shareGame();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: ScrollConfiguration(
            behavior: const _NoGlowScrollBehavior(),
            child: SafeArea(
              top: true,
              child: Stack(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              fit: BoxFit.cover,
                              image: Image.asset(
                                'assets/images/Background.png',
                              ).image,
                            ),
                          ),
                          child: SingleChildScrollView(
                            padding: EdgeInsets.only(
                              bottom: isCompactHeight ? 12.0 : 20.0,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                Container(
                                  width: MediaQuery.sizeOf(context).width * 0.9,
                                  decoration: BoxDecoration(
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryBackground,
                                    borderRadius: BorderRadius.circular(16.0),
                                  ),
                                  child: Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            24.0, 24.0, 24.0, 24.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.max,
                                      children: [
                                        Text(
                                          isGameEnded
                                              ? 'Jeu termin\u00E9'
                                              : 'Grattez pour d\u00E9couvrir',
                                          style: FlutterFlowTheme.of(context)
                                              .headlineSmall
                                              .override(
                                                font: GoogleFonts.interTight(
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .headlineSmall
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .headlineSmall
                                                          .fontStyle,
                                                ),
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primaryText,
                                                letterSpacing: 0.0,
                                                fontWeight:
                                                    FlutterFlowTheme.of(context)
                                                        .headlineSmall
                                                        .fontWeight,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .headlineSmall
                                                        .fontStyle,
                                              ),
                                        ),
                                        if (shouldShowWinnerBlock)
                                          Container(
                                            width: MediaQuery.sizeOf(context)
                                                    .width *
                                                1.0,
                                            decoration: BoxDecoration(
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .secondaryBackground,
                                              borderRadius:
                                                  BorderRadius.circular(12.0),
                                              border: Border.all(
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primary,
                                                width: 1.0,
                                              ),
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                      16.0, 20.0, 16.0, 20.0),
                                              child: Builder(
                                                builder: (context) {
                                                  Widget winnerAnnouncement(
                                                    String firstName,
                                                    String city,
                                                  ) {
                                                    final firstNameFormatted =
                                                        capitalize(firstName);
                                                    final cityFormatted =
                                                        capitalize(city);
                                                    final announcementText =
                                                        firstNameFormatted
                                                                .isEmpty
                                                            ? 'F\u00E9licitations au gagnant !'
                                                            : cityFormatted
                                                                    .isEmpty
                                                                ? 'F\u00E9licitations \u00E0 $firstNameFormatted !'
                                                                : 'F\u00E9licitations \u00E0 $firstNameFormatted de $cityFormatted !';
                                                    return Column(
                                                      mainAxisSize:
                                                          MainAxisSize.max,
                                                      children: [
                                                        Text(
                                                          'F\u00E9licitations !',
                                                          style: FlutterFlowTheme
                                                                  .of(context)
                                                              .titleMedium
                                                              .override(
                                                                font: GoogleFonts
                                                                    .interTight(
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleMedium
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleMedium
                                                                      .fontStyle,
                                                                ),
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight: FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleMedium
                                                                    .fontWeight,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleMedium
                                                                    .fontStyle,
                                                              ),
                                                        ),
                                                        Text(
                                                          announcementText,
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: FlutterFlowTheme
                                                                  .of(context)
                                                              .bodyMedium
                                                              .override(
                                                                font:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyMedium
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyMedium
                                                                      .fontStyle,
                                                                ),
                                                                color: FlutterFlowTheme.of(
                                                                        context)
                                                                    .secondaryText,
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .fontWeight,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .fontStyle,
                                                              ),
                                                        ),
                                                        Text(
                                                          'Le jeu est termin\u00E9 pour le moment. Revenez bient\u00F4t pour d\u00E9couvrir les prochains jeux !',
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: FlutterFlowTheme
                                                                  .of(context)
                                                              .bodySmall
                                                              .override(
                                                                font:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontStyle,
                                                                ),
                                                                color: FlutterFlowTheme.of(
                                                                        context)
                                                                    .secondaryText,
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodySmall
                                                                    .fontWeight,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodySmall
                                                                    .fontStyle,
                                                              ),
                                                        ),
                                                      ].divide(const SizedBox(
                                                          height: 12.0)),
                                                    );
                                                  }

                                                  final gameFirstName =
                                                      winnerDisplayFromGame[
                                                              'firstName'] ??
                                                          '';
                                                  final gameCity =
                                                      winnerDisplayFromGame[
                                                              'city'] ??
                                                          '';
                                                  // Le prenom (au minimum)
                                                  // est deja denormalise sur
                                                  // le doc game par la CF qui
                                                  // a tire le gagnant : pas
                                                  // besoin de lire le profil
                                                  // d'un autre utilisateur.
                                                  // La ville seule peut
                                                  // manquer (champ optionnel
                                                  // sur le profil).
                                                  if (gameFirstName
                                                      .isNotEmpty) {
                                                    return winnerAnnouncement(
                                                      gameFirstName,
                                                      gameCity,
                                                    );
                                                  }

                                                  if (winnerRef == null) {
                                                    return winnerAnnouncement(
                                                        '', '');
                                                  }

                                                  return FutureBuilder<
                                                      UsersRecord?>(
                                                    future: () async {
                                                      try {
                                                        return await UsersRecord
                                                            .getDocumentOnce(
                                                                winnerRef);
                                                      } catch (_) {
                                                        return null;
                                                      }
                                                    }(),
                                                    builder:
                                                        (context, snapshot) {
                                                      final userDisplay =
                                                          _extractWinnerDisplayFromUser(
                                                              snapshot.data);
                                                      final firstName =
                                                          userDisplay['firstName']
                                                                      ?.isNotEmpty ==
                                                                  true
                                                              ? userDisplay[
                                                                  'firstName']!
                                                              : gameFirstName;
                                                      final city = userDisplay[
                                                                      'city']
                                                                  ?.isNotEmpty ==
                                                              true
                                                          ? userDisplay['city']!
                                                          : gameCity;
                                                      return winnerAnnouncement(
                                                        firstName,
                                                        city,
                                                      );
                                                    },
                                                  );
                                                },
                                              ),
                                            ),
                                          )
                                        else
                                          MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: Container(
                                              width: MediaQuery.sizeOf(context)
                                                      .width *
                                                  1.0,
                                              height: 200.0,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF5F5F5),
                                                borderRadius:
                                                    BorderRadius.circular(12.0),
                                              ),
                                              child: SizedBox(
                                                width: 300.0,
                                                height: 300.0,
                                                child: custom_widgets
                                                    .ScratchCardWidget(
                                                  width: 300.0,
                                                  height: 300.0,
                                                  hiddenContent: ' ',
                                                  rewardText: rewardText,
                                                  rewardImageUrl:
                                                      widget.game!.photo,
                                                  rewardTextBonus:
                                                      rewardTextBonus,
                                                  onScratchStart: () {
                                                    _logPlayPageTrace(
                                                      'scratch_card_onScratchStart',
                                                    );
                                                    _startScratchSound();
                                                    _model.isScratching = true;
                                                    safeSetState(() {});
                                                  },
                                                  onScratchEnd: () {
                                                    _logPlayPageTrace(
                                                      'scratch_card_onScratchEnd',
                                                    );
                                                    _stopScratchSound();
                                                    _model.isScratching = false;
                                                    safeSetState(() {});
                                                  },
                                                  setCardRevealed: () async {
                                                    _logPlayPageTrace(
                                                      'scratch_card_setCardRevealed_enter',
                                                      detail:
                                                          'isWin=${widget.resultParticipation?.isWin == true}',
                                                    );
                                                    _model.cardReveal = true;
                                                    if (widget
                                                            .resultParticipation
                                                            ?.isWin ==
                                                        true) {
                                                      _model.isWin = true;
                                                      safeSetState(() {});
                                                      await _stopScratchSound();
                                                      _model.soundPlayer ??=
                                                          AudioPlayer();
                                                      if (_model.soundPlayer!
                                                          .playing) {
                                                        await _model
                                                            .soundPlayer!
                                                            .stop();
                                                      }
                                                      _model.soundPlayer!
                                                          .setVolume(1.0);
                                                      await _model.soundPlayer!
                                                          .setAsset(
                                                              'assets/audios/171670__leszek_szary__success-2.wav')
                                                          .then((_) => _model
                                                              .soundPlayer!
                                                              .play());
                                                    } else {
                                                      _model.isWin = false;
                                                      safeSetState(() {});
                                                    }
                                                    _logPlayPageTrace(
                                                      'scratch_card_setCardRevealed_exit',
                                                      detail:
                                                          'isWin=${_model.isWin == true}',
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                      ].divide(const SizedBox(height: 16.0)),
                                    ),
                                  ),
                                ),
                                if (widget.game?.enseigneId != null)
                                  FutureBuilder<EnseignesRecord>(
                                    future: EnseignesRecord.getDocumentOnce(
                                        widget.game!.enseigneId!),
                                    builder: (context, snapshot) {
                                      if (!snapshot.hasData) {
                                        return const SizedBox(height: 0.0);
                                      }
                                      final enseigneRecord = snapshot.data!;
                                      final enseigneName = (widget.game
                                                  ?.enseigneName.isNotEmpty ??
                                              false)
                                          ? widget.game!.enseigneName
                                          : enseigneRecord.name;
                                      return SizedBox(
                                        width:
                                            MediaQuery.sizeOf(context).width *
                                                0.9,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Material(
                                              color: Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(16.0),
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(16.0),
                                                splashColor:
                                                    FlutterFlowTheme.of(context)
                                                        .primary
                                                        .withOpacity(0.08),
                                                highlightColor:
                                                    FlutterFlowTheme.of(context)
                                                        .primary
                                                        .withOpacity(0.04),
                                                onTap: () async {
                                                  context.pushNamed(
                                                    EnseigneDetailJoueurPageWidget
                                                        .routeName,
                                                    queryParameters: {
                                                      'enseigneDoc':
                                                          serializeParam(
                                                        enseigneRecord,
                                                        ParamType.Document,
                                                      ),
                                                    }.withoutNulls,
                                                    extra: <String, dynamic>{
                                                      'enseigneDoc':
                                                          enseigneRecord,
                                                    },
                                                  );
                                                },
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: FlutterFlowTheme.of(
                                                            context)
                                                        .secondaryBackground,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            16.0),
                                                  ),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            10.0),
                                                    child: Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      children: [
                                                        SizedBox(
                                                          width: 110.0,
                                                          height: 110.0,
                                                          child: FutureBuilder<
                                                              List<
                                                                  ImagesRecord>>(
                                                            future:
                                                                queryImagesRecordOnce(
                                                              parent:
                                                                  enseigneRecord
                                                                      .reference,
                                                              singleRecord:
                                                                  true,
                                                            ),
                                                            builder: (context,
                                                                imageSnapshot) {
                                                              if (!imageSnapshot
                                                                  .hasData) {
                                                                return const SizedBox
                                                                    .shrink();
                                                              }
                                                              final imageList =
                                                                  imageSnapshot
                                                                      .data!;
                                                              if (imageList
                                                                  .isEmpty) {
                                                                return ClipRRect(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              12.0),
                                                                  child:
                                                                      ProxiplayNetworkImage(
                                                                    imageUrl: widget
                                                                        .game!
                                                                        .photo,
                                                                    fit: BoxFit
                                                                        .cover,
                                                                  ),
                                                                );
                                                              }

                                                              return ClipRRect(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            12.0),
                                                                child:
                                                                    ProxiplayNetworkImage(
                                                                  imageUrl:
                                                                      imageList
                                                                          .first
                                                                          .url,
                                                                  fit: BoxFit
                                                                      .cover,
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 12.0),
                                                        Expanded(
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .max,
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .center,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                enseigneName,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleSmall
                                                                    .override(
                                                                      font: GoogleFonts
                                                                          .interTight(
                                                                        fontWeight:
                                                                            FontWeight.w700,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .titleSmall
                                                                            .fontStyle,
                                                                      ),
                                                                      letterSpacing:
                                                                          0.0,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleSmall
                                                                          .fontStyle,
                                                                    ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 10.0),
                                                              Row(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .max,
                                                                children: [
                                                                  Container(
                                                                    width: 26.0,
                                                                    alignment:
                                                                        const AlignmentDirectional(
                                                                            -1.0,
                                                                            0.0),
                                                                    child: Icon(
                                                                      Icons
                                                                          .location_on_sharp,
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primaryText,
                                                                      size:
                                                                          18.0,
                                                                    ),
                                                                  ),
                                                                  Expanded(
                                                                    child: Text(
                                                                      enseigneRecord
                                                                          .city,
                                                                      maxLines:
                                                                          1,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                      style: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodySmall,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(
                                                                  height: 6.0),
                                                              Row(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .max,
                                                                children: [
                                                                  Container(
                                                                    width: 26.0,
                                                                    alignment:
                                                                        const AlignmentDirectional(
                                                                            -1.0,
                                                                            0.0),
                                                                    child: Icon(
                                                                      Icons
                                                                          .phone,
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primaryText,
                                                                      size:
                                                                          18.0,
                                                                    ),
                                                                  ),
                                                                  Expanded(
                                                                    child: Text(
                                                                      enseigneRecord
                                                                          .phoneNumber,
                                                                      maxLines:
                                                                          1,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                      style: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodySmall,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 8.0),
                                                        Icon(
                                                          Icons
                                                              .arrow_forward_ios_rounded,
                                                          size: 16.0,
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .secondaryText,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 10.0),
                                            InkWell(
                                              splashColor:
                                                  FlutterFlowTheme.of(context)
                                                      .primary
                                                      .withOpacity(0.08),
                                              focusColor: Colors.transparent,
                                              hoverColor: Colors.transparent,
                                              highlightColor:
                                                  Colors.transparent,
                                              onTap: () async {
                                                await _shareGame();
                                              },
                                              child: AnimatedScale(
                                                duration: const Duration(
                                                    milliseconds: 140),
                                                curve: Curves.easeOut,
                                                scale: _isPreparingShare
                                                    ? 0.97
                                                    : 1.0,
                                                child: AnimatedOpacity(
                                                  duration: const Duration(
                                                      milliseconds: 140),
                                                  opacity: _isPreparingShare
                                                      ? 0.72
                                                      : 1.0,
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 10.0,
                                                      vertical: 8.0,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                              0xFFA0134D)
                                                          .withOpacity(0.06),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              999.0),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .card_giftcard_rounded,
                                                          size: 16.0,
                                                          color: const Color(
                                                              0xFFA0134D),
                                                        ),
                                                        const SizedBox(
                                                            width: 6.0),
                                                        Text(
                                                          'Tu aimes tes amis ? Partage-leur ce jeu !',
                                                          style: FlutterFlowTheme
                                                                  .of(context)
                                                              .bodySmall
                                                              .override(
                                                                font:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontStyle,
                                                                ),
                                                                color: const Color(
                                                                    0xFFA0134D),
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodySmall
                                                                    .fontStyle,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                if (_model.cardReveal)
                                  Container(
                                    width:
                                        MediaQuery.sizeOf(context).width * 0.9,
                                    decoration: BoxDecoration(
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryBackground,
                                      borderRadius: BorderRadius.circular(16.0),
                                    ),
                                    child: Padding(
                                      padding:
                                          const EdgeInsetsDirectional.fromSTEB(
                                              24.0, 24.0, 24.0, 24.0),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.max,
                                        children: [
                                          if (widget
                                                  .resultParticipation?.isWin ==
                                              true)
                                            FFButtonWidget(
                                              onPressed: () async {
                                                context.pushNamed(
                                                    LotsJoueurPageWidget
                                                        .routeName);
                                              },
                                              text: 'Voir mon prix',
                                              options: FFButtonOptions(
                                                width: double.infinity,
                                                height: 40.0,
                                                padding:
                                                    const EdgeInsetsDirectional
                                                        .fromSTEB(
                                                        16.0, 0.0, 16.0, 0.0),
                                                iconPadding:
                                                    const EdgeInsetsDirectional
                                                        .fromSTEB(
                                                        0.0, 0.0, 0.0, 0.0),
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primary,
                                                textStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .titleSmall
                                                        .override(
                                                          font: GoogleFonts
                                                              .interTight(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleSmall
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleSmall
                                                                    .fontStyle,
                                                          ),
                                                          color: Colors.white,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .titleSmall
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .titleSmall
                                                                  .fontStyle,
                                                        ),
                                                elevation: 0.0,
                                                borderRadius:
                                                    BorderRadius.circular(30.0),
                                              ),
                                            ),
                                          FFButtonWidget(
                                            onPressed: () async {
                                              debugPrint(
                                                '[GLOBAL_NAV] action=context.goNamed from=${ModalRoute.of(context)?.settings.name} to=${HomeJoueurPageWidget.routeName}\n${StackTrace.current}',
                                              );
                                              context.goNamed(
                                                  HomeJoueurPageWidget
                                                      .routeName);
                                            },
                                            text: isAlreadyPlayedStatus
                                                ? 'Retour ï¿½ l\'accueil'
                                                : 'Revenez demain',
                                            options: FFButtonOptions(
                                              width: double.infinity,
                                              height: 40.0,
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                      16.0, 0.0, 16.0, 0.0),
                                              iconPadding:
                                                  const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                      0.0, 0.0, 0.0, 0.0),
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .primary,
                                              textStyle: FlutterFlowTheme.of(
                                                      context)
                                                  .titleSmall
                                                  .override(
                                                    font:
                                                        GoogleFonts.interTight(
                                                      fontWeight:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .titleSmall
                                                              .fontWeight,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .titleSmall
                                                              .fontStyle,
                                                    ),
                                                    color: Colors.white,
                                                    letterSpacing: 0.0,
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .titleSmall
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .titleSmall
                                                            .fontStyle,
                                                  ),
                                              elevation: 0.0,
                                              borderRadius:
                                                  BorderRadius.circular(30.0),
                                            ),
                                          ),
                                        ].divide(const SizedBox(height: 16.0)),
                                      ),
                                    ),
                                  ),
                                Visibility(
                                  visible: false,
                                  child: Padding(
                                    padding: EdgeInsetsDirectional.fromSTEB(0.0,
                                        0.0, 0.0, isCompactHeight ? 8.0 : 20.0),
                                    child: Container(
                                      width: MediaQuery.sizeOf(context).width *
                                          0.9,
                                      decoration: BoxDecoration(
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryBackground,
                                        borderRadius:
                                            BorderRadius.circular(16.0),
                                      ),
                                      child: Padding(
                                        padding: EdgeInsetsDirectional.fromSTEB(
                                            isCompactHeight ? 12.0 : 16.0,
                                            isCompactHeight ? 12.0 : 16.0,
                                            isCompactHeight ? 12.0 : 16.0,
                                            isCompactHeight ? 12.0 : 16.0),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.max,
                                          children: [
                                            Text(
                                              'Lots \u00E0 gagner',
                                              style: FlutterFlowTheme.of(
                                                      context)
                                                  .headlineSmall
                                                  .override(
                                                    font:
                                                        GoogleFonts.interTight(
                                                      fontWeight:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .headlineSmall
                                                              .fontWeight,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .headlineSmall
                                                              .fontStyle,
                                                    ),
                                                    color: FlutterFlowTheme.of(
                                                            context)
                                                        .primaryText,
                                                    letterSpacing: 0.0,
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .headlineSmall
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .headlineSmall
                                                            .fontStyle,
                                                  ),
                                            ),
                                            if (hasMainPrizeGame)
                                              Row(
                                                mainAxisSize: MainAxisSize.max,
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.max,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Lot principal',
                                                          style: FlutterFlowTheme
                                                                  .of(context)
                                                              .bodyLarge
                                                              .override(
                                                                font:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyLarge
                                                                      .fontStyle,
                                                                ),
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyLarge
                                                                    .fontStyle,
                                                              ),
                                                        ),
                                                        if (hasMainPrizeDescription)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                                    top: 4.0),
                                                            child: Text(
                                                              mainPrizeDescription,
                                                              maxLines: 2,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: FlutterFlowTheme
                                                                      .of(context)
                                                                  .bodyMedium
                                                                  .override(
                                                                    font: GoogleFonts
                                                                        .inter(
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodyMedium
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodyMedium
                                                                          .fontStyle,
                                                                    ),
                                                                    color: const Color(
                                                                        0xFF374151),
                                                                    letterSpacing:
                                                                        0.0,
                                                                    fontSize:
                                                                        13.0,
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodyMedium
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodyMedium
                                                                        .fontStyle,
                                                                  ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (!isCompactHeight)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsetsDirectional
                                                              .fromSTEB(8.0,
                                                              8.0, 8.0, 8.0),
                                                      child: Container(
                                                        decoration:
                                                            BoxDecoration(
                                                          color: const Color(
                                                              0xFFFFF3E0),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      20.0),
                                                        ),
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(8.0),
                                                          child: Text(
                                                            'Tirage au sort',
                                                            style: FlutterFlowTheme
                                                                    .of(context)
                                                                .bodySmall
                                                                .override(
                                                                  font:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodySmall
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodySmall
                                                                        .fontStyle,
                                                                  ),
                                                                  color: const Color(
                                                                      0xFFFF6F00),
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontStyle,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            Row(
                                              mainAxisSize: MainAxisSize.max,
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Container(
                                                    decoration:
                                                        const BoxDecoration(),
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.max,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Lots secondaires',
                                                          style: FlutterFlowTheme
                                                                  .of(context)
                                                              .bodyLarge
                                                              .override(
                                                                font:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyLarge
                                                                      .fontStyle,
                                                                ),
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyLarge
                                                                    .fontStyle,
                                                              ),
                                                        ),
                                                        Builder(
                                                          builder: (context) {
                                                            final secondaryPrizes =
                                                                widget.game!
                                                                    .secondaryPrizes;
                                                            final visiblePrizes =
                                                                secondaryPrizes
                                                                    .take(
                                                                        isCompactHeight
                                                                            ? 1
                                                                            : 2)
                                                                    .toList();
                                                            if (secondaryPrizes
                                                                .isNotEmpty) {
                                                              return Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  ...visiblePrizes
                                                                      .map(
                                                                    (p) {
                                                                      final name =
                                                                          (p['name'] ?? '')
                                                                              .toString();
                                                                      final presentation =
                                                                          (p['presentation'] ?? '')
                                                                              .toString();
                                                                      final count =
                                                                          p['count'];
                                                                      final countText = count !=
                                                                              null
                                                                          ? ' x$count'
                                                                          : '';
                                                                      return Padding(
                                                                        padding:
                                                                            const EdgeInsets.only(
                                                                          bottom:
                                                                              8.0,
                                                                        ),
                                                                        child:
                                                                            Column(
                                                                          crossAxisAlignment:
                                                                              CrossAxisAlignment.start,
                                                                          children: [
                                                                            Text(
                                                                              '$name$countText',
                                                                              style: FlutterFlowTheme.of(context).bodyMedium,
                                                                              maxLines: 1,
                                                                              overflow: TextOverflow.ellipsis,
                                                                            ),
                                                                            if (presentation.isNotEmpty &&
                                                                                !isCompactHeight)
                                                                              Text(
                                                                                presentation,
                                                                                maxLines: 2,
                                                                                overflow: TextOverflow.ellipsis,
                                                                                style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                      color: FlutterFlowTheme.of(context).secondaryText,
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                    ),
                                                                              ),
                                                                          ],
                                                                        ),
                                                                      );
                                                                    },
                                                                  ),
                                                                  if (secondaryPrizes
                                                                          .length >
                                                                      (isCompactHeight
                                                                          ? 1
                                                                          : 2))
                                                                    Text(
                                                                      '+${secondaryPrizes.length - (isCompactHeight ? 1 : 2)} autres lots',
                                                                      style: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodySmall,
                                                                    ),
                                                                ],
                                                              );
                                                            }
                                                            if (widget
                                                                .game!
                                                                .secondaryPrizeDescription
                                                                .isNotEmpty) {
                                                              return AutoSizeText(
                                                                widget.game!
                                                                    .secondaryPrizeDescription,
                                                                maxLines: 3,
                                                                style: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .override(
                                                                      font: GoogleFonts
                                                                          .inter(
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .bodyMedium
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .bodyMedium
                                                                            .fontStyle,
                                                                      ),
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .secondaryText,
                                                                      letterSpacing:
                                                                          0.0,
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodyMedium
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodyMedium
                                                                          .fontStyle,
                                                                    ),
                                                              );
                                                            }
                                                            return Text(
                                                              'Aucun gagnant',
                                                              style: FlutterFlowTheme
                                                                      .of(context)
                                                                  .bodySmall
                                                                  .override(
                                                                    font: GoogleFonts
                                                                        .inter(
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodySmall
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodySmall
                                                                          .fontStyle,
                                                                    ),
                                                                    color: FlutterFlowTheme.of(
                                                                            context)
                                                                        .secondaryText,
                                                                    letterSpacing:
                                                                        0.0,
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodySmall
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodySmall
                                                                        .fontStyle,
                                                                  ),
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                if (!isCompactHeight)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsetsDirectional
                                                            .fromSTEB(8.0, 16.0,
                                                            8.0, 16.0),
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                            0xFFE8F5E9),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20.0),
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(8.0),
                                                        child: Text(
                                                          'Gain imm\u00E9diat',
                                                          style: FlutterFlowTheme
                                                                  .of(context)
                                                              .bodySmall
                                                              .override(
                                                                font:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontStyle,
                                                                ),
                                                                color: const Color(
                                                                    0xFF2E7D32),
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodySmall
                                                                    .fontWeight,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodySmall
                                                                    .fontStyle,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ].divide(
                                              const SizedBox(height: 16.0)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ].divide(SizedBox(
                                  height: isCompactHeight ? 12.0 : 20.0)),
                            ),
                          ),
                        ),
                      ),
                      wrapWithModel(
                        model: _model.customNavBarJoueurModel,
                        updateCallback: () => safeSetState(() {}),
                        child: const CustomNavBarJoueurWidget(),
                      ),
                    ],
                  ),
                  Align(
                    alignment: const AlignmentDirectional(0.0, 0.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(0.0),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 2.0,
                          sigmaY: 2.0,
                        ),
                        child: Visibility(
                          visible: _model.isWin == true,
                          child: TapFeedback(
                            enabled: true,
                            onTap: () {
                              _model.isWin = false;
                              safeSetState(() {});
                            },
                            child: SizedBox(
                              width: double.infinity,
                              height: double.infinity,
                              child: RiveAnimation.asset(
                                'assets/rive_animations/win_animation.riv',
                                artboard: 'Artboard',
                                fit: BoxFit.fitWidth,
                                controllers: _model.riveAnimationControllers,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
