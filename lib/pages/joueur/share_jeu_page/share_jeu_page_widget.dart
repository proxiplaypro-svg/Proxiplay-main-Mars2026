import 'dart:async';

import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/animation_utils.dart';
import '/backend/custom_cloud_functions/custom_cloud_function_response_manager.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/utils/create_account_to_play_dialog.dart';
import '/utils/game_launch_coordinator.dart';
import '/utils/minor_restricted_game_access.dart';
import '/utils/share_links.dart';
import '/utils/game_view_tracker.dart';
import '/widgets/proxiplay_network_image.dart';
import '/index.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webviewx_plus/webviewx_plus.dart';
import 'share_jeu_page_model.dart';
export 'share_jeu_page_model.dart';

/// remplir le container sous l[image par une liste de text
class ShareJeuPageWidget extends StatefulWidget {
  const ShareJeuPageWidget({
    super.key,
    required this.gameDoc,
    required this.enseigneDoc,
    this.source,
  });

  final GamesRecord? gameDoc;
  final EnseignesRecord? enseigneDoc;
  final String? source;

  static String routeName = 'ShareJeuPage';
  static String routePath = 'shareJeuPage';

  @override
  State<ShareJeuPageWidget> createState() => _ShareJeuPageWidgetState();
}

class _ShareJeuPageWidgetState extends State<ShareJeuPageWidget> {
  late ShareJeuPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool _hasTrackedView = false;
  bool _isLaunchingGame = false;
  final GameLaunchCoordinator _launchCoordinator =
      GameLaunchCoordinator(screenName: 'ShareJeuPage');
  String? _currentAttemptId;

  void _setLaunchingGame(bool value) {
    if (!mounted || _isLaunchingGame == value) {
      return;
    }
    safeSetState(() {
      _isLaunchingGame = value;
    });
  }

  String _newAttemptId() {
    final id =
        '${DateTime.now().toUtc().microsecondsSinceEpoch}_${widget.gameDoc?.reference.id ?? 'unknown'}';
    _currentAttemptId = id;
    return id;
  }

  DateTime? _coerceDateTime(dynamic value) {
    if (value is DateTime) {
      return value;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }

  bool _computeHasPlayedToday(DateTime? lastPlay, DateTime now) {
    return lastPlay != null &&
        lastPlay.year == now.year &&
        lastPlay.month == now.month &&
        lastPlay.day == now.day;
  }

  bool get _showsParticipationEntry => true;

  Future<bool> _ensureMinorRestrictedGameEligibility() async {
    final accessStatus = resolveMinorRestrictedGameAccess(
      prohibitedForMinors: widget.gameDoc?.prohibitedForMinors ?? false,
      birthday: currentUserDocument?.birthday,
    );

    switch (accessStatus) {
      case MinorRestrictedGameAccessStatus.allowed:
        return true;
      case MinorRestrictedGameAccessStatus.birthdayRequired:
        final shouldOpenProfile = await showDialog<bool>(
              context: context,
              builder: (dialogContext) {
                return WebViewAware(
                  child: AlertDialog(
                    title: const Text('Jeu reserve aux majeurs'),
                    content: const Text(
                      'Ce jeu est reserve aux personnes majeures.\nPour verifier votre age, merci de renseigner votre date de naissance.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Plus tard'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text(
                          'Renseigner ma date de naissance',
                        ),
                      ),
                    ],
                  ),
                );
              },
            ) ??
            false;
        if (shouldOpenProfile && mounted) {
          await context.pushNamed(
            InscriptionInformationsPageWidget.routeName,
          );
        }
        return false;
      case MinorRestrictedGameAccessStatus.underage:
        await showDialog<void>(
          context: context,
          builder: (dialogContext) {
            return WebViewAware(
              child: AlertDialog(
                title: const Text('Jeu reserve aux majeurs'),
                content: const Text(
                  'Ce jeu est reserve aux personnes majeures.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Fermer'),
                  ),
                ],
              ),
            );
          },
        );
        return false;
    }
  }

  void _logParticipationTrace({
    required String stage,
    required String attemptId,
    required String gameId,
    DateTime? lastPlay,
    bool? hasPlayedToday,
    String? detail,
  }) {}

  Future<ParticipateInGameTransactionCloudFunctionCallResponse>
      _callParticipateInGameTransaction({
    required String attemptId,
    required Map<String, dynamic> payload,
  }) async {
    final gameId = widget.gameDoc?.reference.id ?? 'unknown';
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('participateInGameTransaction')
          .call(payload);
      return ParticipateInGameTransactionCloudFunctionCallResponse(
        data: ResultParticipationGameStruct.fromMap(result.data),
        succeeded: true,
        resultAsString: result.data.toString(),
        jsonBody: result.data,
      );
    } on FirebaseFunctionsException catch (error) {
      return ParticipateInGameTransactionCloudFunctionCallResponse(
        data: createResultParticipationGameStruct(
          message: error.message ?? 'Erreur (${error.code})',
        ),
        errorCode: error.code,
        succeeded: false,
      );
    }
  }

  /// Launches a game through [GameLaunchCoordinator] — same single-flight
  /// lock, timeout and logging semantics as
  /// `jeu_detail_joueur_page_widget.dart`. See the audit notes on
  /// [GameParticipationOutcome]: the server-side participation is already
  /// committed by the time [participate] returns success, so this method
  /// focuses on never compounding that (no duplicate calls, no stuck lock,
  /// no premature local "already played" state).
  Future<void> _launchGame({
    required String attemptId,
    required Future<ParticipateInGameTransactionCloudFunctionCallResponse>
            Function()
        participate,
  }) async {
    final gameId = widget.gameDoc?.reference.id ?? 'unknown';
    _currentAttemptId = attemptId;
    _logParticipationTrace(
      stage: 'launchGame_enter',
      attemptId: attemptId,
      gameId: gameId,
      detail: 'source=${widget.source ?? 'unknown'}',
    );

    await _launchCoordinator.launch(
      attemptId: attemptId,
      gameId: gameId,
      onLaunchingChanged: _setLaunchingGame,
      participate: () async {
        final response = await participate();
        return GameParticipationOutcome(
          succeeded: response.succeeded == true,
          alreadyParticipatedToday: response.jsonBody is Map &&
              (response.jsonBody as Map)['alreadyParticipatedToday'] == true,
          errorCode: response.errorCode,
          errorMessage: response.data?.message,
          raw: response,
          attemptId: attemptId,
        );
      },
      navigate: _navigateToGameScreen,
      onParticipationError: _showLaunchErrorDialog,
      onNavigationFailed: _showNavigationFailureDialog,
      onMountTimedOut: () {
        // Diagnostic only for now — see audit. No compensation triggered
        // client-side without a validated server-side design.
      },
    );

    if (mounted) {
      _logParticipationTrace(
        stage: 'launchGame_before_safeSetState',
        attemptId: attemptId,
        gameId: gameId,
      );
      safeSetState(() {});
    }
  }

  /// Pushes [PlayJoueurPageWidget] imperatively (rather than through the
  /// named/GoRouter route) so we can wire [PlayJoueurPageWidget.onGameScreenMounted]
  /// — the generated named route rebuilds the widget from serializable
  /// params only and cannot carry a callback. Any refresh of this page's
  /// own state is deferred until the player has actually returned.
  Future<GameNavigationResult> _navigateToGameScreen(
    GameParticipationOutcome outcome,
  ) async {
    final response =
        outcome.raw as ParticipateInGameTransactionCloudFunctionCallResponse;
    final attemptId = outcome.attemptId ?? 'none';
    final gameId = widget.gameDoc?.reference.id ?? 'unknown';

    var newlyQualified = false;
    if (!outcome.alreadyParticipatedToday &&
        widget.gameDoc != null &&
        currentUserUid.isNotEmpty &&
        widget.gameDoc!.animationId.trim().isNotEmpty) {
      try {
        newlyQualified =
            await updateAnimationProgress(currentUserUid, widget.gameDoc!);
      } catch (error) {
        debugPrint(
          '[ANIMATION_PROGRESS] update skipped gameId=${widget.gameDoc?.reference.id} '
          'animationId=${widget.gameDoc?.animationId} error=$error',
        );
      }
    }
    if (!mounted) {
      _logParticipationTrace(
        stage: 'navigation_aborted_not_mounted',
        attemptId: attemptId,
        gameId: gameId,
      );
      return GameNavigationResult.navigationFailed;
    }

    if (newlyQualified) {
      await showDialog(
        context: context,
        builder: (dialogContext) {
          return WebViewAware(
            child: AlertDialog(
              title: const Text(
                'Felicitations, tu es qualifie pour le tirage final !',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        },
      );
      if (!mounted) {
        return GameNavigationResult.navigationFailed;
      }
    }

    final mountedBy = Completer<void>();

    return GameLaunchCoordinator.runNavigation(
      mountedBy: mountedBy,
      mountTimeout: _launchCoordinator.mountTimeout,
      push: () {
        _logParticipationTrace(
          stage: 'before_push_play_page',
          attemptId: attemptId,
          gameId: gameId,
          detail:
              'alreadyParticipatedToday=${outcome.alreadyParticipatedToday}',
        );
        return AppStateNotifier.instance
            .runWithCriticalImperativeNavigation(
          () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) {
                _logParticipationTrace(
                  stage: 'push_play_page_invoked',
                  attemptId: attemptId,
                  gameId: gameId,
                  detail:
                      'resultMessage=${response.data?.message ?? ''} resultMessageBonus=${response.data?.messageBonus ?? ''} isWin=${response.data?.isWin == true} prizeId=${response.data?.prizeId ?? ''}',
                );
                return PlayJoueurPageWidget(
                  game: widget.gameDoc,
                  resultParticipation:
                      ResultParticipationGameStruct.maybeFromMap(
                    response.jsonBody,
                  ),
                  source: widget.source,
                  attemptId: attemptId,
                  alreadyParticipatedToday: outcome.alreadyParticipatedToday,
                  onGameScreenMounted: () {
                    if (!mountedBy.isCompleted) {
                      mountedBy.complete();
                    }
                  },
                );
              },
            ),
          ),
        )
            .then((value) {
          _logParticipationTrace(
            stage: 'after_push_play_page',
            attemptId: attemptId,
            gameId: gameId,
          );
          return value;
        });
      },
      awaitReturn: (pushFuture) async {
        await pushFuture;
        if (!mounted) {
          _logParticipationTrace(
            stage: 'after_push_return_not_mounted',
            attemptId: attemptId,
            gameId: gameId,
          );
          return;
        }
        try {
          _logParticipationTrace(
            stage: 'before_refreshCurrentUserDocument',
            attemptId: attemptId,
            gameId: gameId,
          );
          await refreshCurrentUserDocument();
          DateTime? refreshedLastPlay;
          bool? refreshedHasPlayedToday;
          if (currentUserUid.isNotEmpty && widget.gameDoc != null) {
            final participantDetailSnapshot = await widget.gameDoc!.reference
                .collection('participants_details')
                .doc(currentUserUid)
                .get();
            refreshedLastPlay =
                _coerceDateTime(participantDetailSnapshot.data()?['last_play']);
            refreshedHasPlayedToday = _computeHasPlayedToday(
              refreshedLastPlay,
              DateTime.now(),
            );
          }
          _logParticipationTrace(
            stage: 'after_refreshCurrentUserDocument',
            attemptId: attemptId,
            gameId: gameId,
            lastPlay: refreshedLastPlay,
            hasPlayedToday: refreshedHasPlayedToday,
          );
        } catch (error) {}
        if (mounted) {
          _logParticipationTrace(
            stage: 'after_return_before_safeSetState',
            attemptId: attemptId,
            gameId: gameId,
          );
          safeSetState(() {});
        }
      },
    );
  }

  Future<void> _showLaunchErrorDialog(GameParticipationOutcome outcome) async {
    if (!mounted) {
      return;
    }
    final response =
        outcome.raw as ParticipateInGameTransactionCloudFunctionCallResponse?;
    await showDialog(
      context: context,
      builder: (alertDialogContext) {
        return WebViewAware(
          child: AlertDialog(
            title: Text(
              response?.data?.message.isNotEmpty == true
                  ? response!.data!.message
                  : (outcome.errorMessage?.isNotEmpty == true
                      ? outcome.errorMessage!
                      : "Une erreur est survenue (${outcome.errorCode ?? 'inconnue'})."),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(alertDialogContext),
                child: const Text('Ok'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showNavigationFailureDialog() async {
    if (!mounted) {
      return;
    }
    await showDialog(
      context: context,
      builder: (alertDialogContext) {
        return WebViewAware(
          child: AlertDialog(
            title: const Text(
              "Le jeu n'a pas pu s'afficher. Si le probleme persiste, "
              "contactez le support : votre partie a peut-etre ete "
              "comptabilisee sans avoir pu s'afficher.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(alertDialogContext),
                child: const Text('Ok'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _trackViewOnce() async {
    if (_hasTrackedView) {
      return;
    }
    _hasTrackedView = true;
    await trackGamePresentationView(
      widget.gameDoc,
      'ShareJeuPage',
      source: widget.source,
    );
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => ShareJeuPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'ShareJeuPage'});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trackViewOnce();
    });
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ParticipantsDetailsRecord>>(
      future: queryParticipantsDetailsRecordOnce(
        parent: widget.gameDoc?.reference,
        queryBuilder: (participantsDetailsRecord) =>
            participantsDetailsRecord.where(
          'user_id',
          isEqualTo: currentUserReference,
        ),
        singleRecord: true,
      ),
      builder: (context, snapshot) {
        // Customize what your widget looks like when it[s loading.
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
            body: const Center(
              child: SizedBox(
                width: 50.0,
                height: 50.0,
                child: SizedBox.shrink(),
              ),
            ),
          );
        }
        List<ParticipantsDetailsRecord>
            shareJeuPageParticipantsDetailsRecordList = snapshot.data!;
        final shareJeuPageParticipantsDetailsRecord =
            shareJeuPageParticipantsDetailsRecordList.isNotEmpty
                ? shareJeuPageParticipantsDetailsRecordList.first
                : null;

        return GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            FocusManager.instance.primaryFocus?.unfocus();
          },
          child: PopScope(
            canPop: false,
            child: Scaffold(
              key: scaffoldKey,
              backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(100.0),
                child: AppBar(
                  backgroundColor:
                      FlutterFlowTheme.of(context).primaryBackground,
                  automaticallyImplyLeading: false,
                  actions: const [],
                  flexibleSpace: FlexibleSpaceBar(
                    title: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          0.0, 0.0, 0.0, 14.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                0.0, 0.0, 40.0, 8.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    Builder(
                                      builder: (context) {
                                        if (currentUserUid != '') {
                                          return FlutterFlowIconButton(
                                            borderRadius: 12.0,
                                            buttonSize: 48.0,
                                            fillColor:
                                                Colors.white.withOpacity(0.9),
                                            icon: Icon(
                                              Icons.favorite_border_rounded,
                                              color: const Color(0xFFA0134D),
                                              size: 22.0,
                                            ),
                                            onPressed: () async {
                                              await FavoriteGamesRecord
                                                      .createDoc(
                                                          currentUserReference!)
                                                  .set({
                                                ...createFavoriteGamesRecordData(
                                                  gameId:
                                                      widget.gameDoc?.reference,
                                                ),
                                                ...mapToFirestore(
                                                  {
                                                    'added_at': FieldValue
                                                        .serverTimestamp(),
                                                  },
                                                ),
                                              });

                                              await widget.gameDoc!.reference
                                                  .update({
                                                ...mapToFirestore(
                                                  {
                                                    'favorites':
                                                        FieldValue.increment(1),
                                                  },
                                                ),
                                              });
                                            },
                                          );
                                        } else {
                                          return Container(
                                            decoration: const BoxDecoration(),
                                          );
                                        }
                                      },
                                    ),
                                    Builder(
                                      builder: (context) =>
                                          FlutterFlowIconButton(
                                        borderRadius: 12.0,
                                        buttonSize: 48.0,
                                        fillColor: const Color(0xFFA0134D),
                                        icon: const Icon(
                                          Icons.share_sharp,
                                          color: Colors.white,
                                          size: 24.0,
                                        ),
                                        onPressed: () async {
                                          await Share.share(
                                            buildAppShareText(
                                              title:
                                                  '${widget.gameDoc?.name ?? 'ce jeu'} sur ProxiPlay',
                                              description: widget
                                                          .enseigneDoc?.name
                                                          .trim()
                                                          .isNotEmpty ==
                                                      true
                                                  ? 'Disponible chez ${widget.enseigneDoc!.name}.'
                                                  : null,
                                            ),
                                            sharePositionOrigin:
                                                getWidgetBoundingBox(context),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    centerTitle: true,
                    expandedTitleScale: 1.0,
                  ),
                  elevation: 0.0,
                ),
              ),
              body: SafeArea(
                top: true,
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            20.0, 0.0, 20.0, 0.0),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    0.0, 0.0, 0.0, 50.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    Padding(
                                      padding:
                                          const EdgeInsetsDirectional.fromSTEB(
                                              20.0, 0.0, 20.0, 0.0),
                                      child: Container(
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryBackground,
                                          borderRadius:
                                              BorderRadius.circular(10.0),
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(20.0),
                                          child: ProxiplayNetworkImage(
                                            imageUrl: widget.gameDoc!.photo,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Align(
                                      alignment:
                                          const AlignmentDirectional(0.0, 0.0),
                                      child: Builder(
                                        builder: (context) {
                                          if (currentUserUid != '') {
                                            return Builder(
                                              builder: (context) {
                                                if (_showsParticipationEntry) {
                                                  return Visibility(
                                                    visible: widget
                                                            .gameDoc!.endDate! >
                                                        getCurrentTimestamp,
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsetsDirectional
                                                              .fromSTEB(16.0,
                                                              0.0, 16.0, 0.0),
                                                      child: FFButtonWidget(
                                                        onPressed: ((widget
                                                                        .gameDoc!
                                                                        .endDate! <
                                                                    getCurrentTimestamp) ||
                                                                ((shareJeuPageParticipantsDetailsRecord !=
                                                                        null) &&
                                                                    (shareJeuPageParticipantsDetailsRecord
                                                                            .lastPlay! >=
                                                                        getCurrentTimestamp)) ||
                                                                _isLaunchingGame)
                                                            ? null
                                                            : () async {
                                                                if (_isLaunchingGame) {
                                                                  return;
                                                                }
                                                                if (isGuestOrAnonymous) {
                                                                  await showCreateAccountToPlayDialog(
                                                                      context);
                                                                  return;
                                                                }
                                                                if (!await _ensureMinorRestrictedGameEligibility()) {
                                                                  return;
                                                                }
                                                                final attemptId =
                                                                    _newAttemptId();
                                                                final lastPlay =
                                                                    _coerceDateTime(
                                                                  shareJeuPageParticipantsDetailsRecord
                                                                      ?.lastPlay,
                                                                );
                                                                final hasPlayedToday =
                                                                    _computeHasPlayedToday(
                                                                  lastPlay,
                                                                  DateTime
                                                                      .now(),
                                                                );
                                                                _logParticipationTrace(
                                                                  stage:
                                                                      'before_click_play',
                                                                  attemptId:
                                                                      attemptId,
                                                                  gameId: widget
                                                                          .gameDoc
                                                                          ?.reference
                                                                          .id ??
                                                                      'unknown',
                                                                  lastPlay:
                                                                      lastPlay,
                                                                  hasPlayedToday:
                                                                      hasPlayedToday,
                                                                  detail:
                                                                      'source=${widget.source ?? 'unknown'}',
                                                                );
                                                                await _launchGame(
                                                                  attemptId:
                                                                      attemptId,
                                                                  participate:
                                                                      () async {
                                                                    _model.cloudFunction3sn =
                                                                        await _callParticipateInGameTransaction(
                                                                      attemptId:
                                                                          attemptId,
                                                                      payload: {
                                                                        "gameRef": widget
                                                                            .gameDoc!
                                                                            .reference
                                                                            .id,
                                                                        "attemptId":
                                                                            attemptId,
                                                                      },
                                                                    );
                                                                    return _model
                                                                        .cloudFunction3sn!;
                                                                  },
                                                                );
                                                              },
                                                        text: () {
                                                          if (widget.gameDoc!
                                                                  .endDate! <
                                                              getCurrentTimestamp) {
                                                            return 'Le jeu est termin\u00E9';
                                                          } else if ((shareJeuPageParticipantsDetailsRecord !=
                                                                  null) &&
                                                              (shareJeuPageParticipantsDetailsRecord
                                                                      .lastPlay! >=
                                                                  getCurrentTimestamp)) {
                                                            return 'Vous avez d\u00E9j\u00E0 jou\u00E9';
                                                          } else if (_isLaunchingGame) {
                                                            return 'Chargement du jeu\u2026';
                                                          } else if ((shareJeuPageParticipantsDetailsRecord !=
                                                                  null) &&
                                                              (shareJeuPageParticipantsDetailsRecord
                                                                      .lastPlay! <
                                                                  getCurrentTimestamp)) {
                                                            return 'Rejouer';
                                                          } else {
                                                            return 'Participer';
                                                          }
                                                        }(),
                                                        options:
                                                            FFButtonOptions(
                                                          width:
                                                              double.infinity,
                                                          height: 50.0,
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(8.0),
                                                          iconPadding:
                                                              const EdgeInsetsDirectional
                                                                  .fromSTEB(
                                                                  0.0,
                                                                  0.0,
                                                                  0.0,
                                                                  0.0),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .primary,
                                                          textStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
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
                                                                    color: FlutterFlowTheme.of(
                                                                            context)
                                                                        .info,
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
                                                          elevation: 3.0,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      25.0),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                } else {
                                                  return Text(
                                                    'Interdit au mineur',
                                                    style: FlutterFlowTheme.of(
                                                            context)
                                                        .titleLarge
                                                        .override(
                                                          font: GoogleFonts
                                                              .interTight(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleLarge
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleLarge
                                                                    .fontStyle,
                                                          ),
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .titleLarge
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .titleLarge
                                                                  .fontStyle,
                                                        ),
                                                  );
                                                }
                                              },
                                            );
                                          } else {
                                            return Container(
                                              decoration: const BoxDecoration(),
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding:
                                          const EdgeInsetsDirectional.fromSTEB(
                                              20.0, 0.0, 20.0, 0.0),
                                      child: Container(
                                        width: double.infinity,
                                        height: 100.0,
                                        decoration: BoxDecoration(
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryBackground,
                                          borderRadius:
                                              BorderRadius.circular(20.0),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsetsDirectional
                                              .fromSTEB(16.0, 16.0, 16.0, 16.0),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.max,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                widget.gameDoc!.description,
                                                style:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .override(
                                                          font:
                                                              GoogleFonts.inter(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .fontStyle,
                                                          ),
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodyMedium
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodyMedium
                                                                  .fontStyle,
                                                        ),
                                              ),
                                            ].divide(
                                                const SizedBox(height: 8.0)),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding:
                                          const EdgeInsetsDirectional.fromSTEB(
                                              20.0, 0.0, 20.0, 0.0),
                                      child: Container(
                                        width: double.infinity,
                                        decoration: const BoxDecoration(),
                                      ),
                                    ),
                                    Padding(
                                      padding:
                                          const EdgeInsetsDirectional.fromSTEB(
                                              20.0, 0.0, 20.0, 0.0),
                                      child: Container(
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryBackground,
                                          borderRadius:
                                              BorderRadius.circular(20.0),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsetsDirectional
                                              .fromSTEB(10.0, 10.0, 10.0, 10.0),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.max,
                                            children: [
                                              Padding(
                                                padding:
                                                    const EdgeInsetsDirectional
                                                        .fromSTEB(
                                                        0.0, 16.0, 0.0, 16.0),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
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
                                                            widget.enseigneDoc!
                                                                .description,
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
                                                        ].divide(const SizedBox(
                                                            height: 8.0)),
                                                      ),
                                                    ),
                                                  ].divide(const SizedBox(
                                                      width: 16.0)),
                                                ),
                                              ),
                                              FutureBuilder<List<ImagesRecord>>(
                                                future: queryImagesRecordOnce(
                                                  parent: widget
                                                      .enseigneDoc?.reference,
                                                  limit: 5,
                                                ),
                                                builder: (context, snapshot) {
                                                  // Customize what your widget looks like when it[s loading.
                                                  if (!snapshot.hasData) {
                                                    return const Center(
                                                      child: SizedBox(
                                                        width: 50.0,
                                                        height: 50.0,
                                                        child:
                                                            SizedBox.shrink(),
                                                      ),
                                                    );
                                                  }
                                                  List<ImagesRecord>
                                                      rowImagesRecordList =
                                                      snapshot.data!;

                                                  return Row(
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    children: List.generate(
                                                        rowImagesRecordList
                                                            .length,
                                                        (rowIndex) {
                                                      final rowImagesRecord =
                                                          rowImagesRecordList[
                                                              rowIndex];
                                                      return Container(
                                                        width: 100.0,
                                                        height: 100.0,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .secondaryBackground,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      20.0),
                                                        ),
                                                        child: ClipRRect(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      20.0),
                                                          child:
                                                              ProxiplayNetworkImage(
                                                            imageUrl:
                                                                rowImagesRecord
                                                                    .url,
                                                            width: 200.0,
                                                            height: 200.0,
                                                            fit: BoxFit.cover,
                                                          ),
                                                        ),
                                                      );
                                                    }).divide(const SizedBox(
                                                        width: 10.0)),
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (!functions.checkValueIsEmpty(
                                            widget.enseigneDoc!.facebookLink) ||
                                        !functions.checkValueIsEmpty(
                                            widget.enseigneDoc!.twitterLink) ||
                                        !functions.checkValueIsEmpty(
                                            widget.enseigneDoc!.siteWebUrl) ||
                                        !functions.checkValueIsEmpty(
                                            widget.enseigneDoc!.instagramLink))
                                      Padding(
                                        padding: const EdgeInsetsDirectional
                                            .fromSTEB(20.0, 0.0, 20.0, 0.0),
                                        child: Container(
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: FlutterFlowTheme.of(context)
                                                .secondaryBackground,
                                            borderRadius:
                                                BorderRadius.circular(20.0),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(10.0),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.max,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (!functions
                                                    .checkValueIsEmpty(widget
                                                        .enseigneDoc!
                                                        .siteWebUrl))
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    children: [
                                                      Icon(
                                                        Icons.web_outlined,
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .primary,
                                                        size: 24.0,
                                                      ),
                                                      Text(
                                                        widget.enseigneDoc!
                                                            .siteWebUrl,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
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
                                                    ].divide(const SizedBox(
                                                        width: 12.0)),
                                                  ),
                                                if (!functions
                                                    .checkValueIsEmpty(widget
                                                        .enseigneDoc!
                                                        .facebookLink))
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    children: [
                                                      Icon(
                                                        Icons.facebook,
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .primary,
                                                        size: 24.0,
                                                      ),
                                                      Text(
                                                        widget.enseigneDoc!
                                                            .facebookLink,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
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
                                                    ].divide(const SizedBox(
                                                        width: 12.0)),
                                                  ),
                                                if (!functions
                                                    .checkValueIsEmpty(widget
                                                        .enseigneDoc!
                                                        .instagramLink))
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    children: [
                                                      FaIcon(
                                                        FontAwesomeIcons
                                                            .instagram,
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .primary,
                                                        size: 24.0,
                                                      ),
                                                      Text(
                                                        widget.enseigneDoc!
                                                            .instagramLink,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
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
                                                    ].divide(const SizedBox(
                                                        width: 12.0)),
                                                  ),
                                                if (!functions
                                                    .checkValueIsEmpty(widget
                                                        .enseigneDoc!
                                                        .twitterLink))
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    children: [
                                                      FaIcon(
                                                        FontAwesomeIcons
                                                            .twitter,
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .primary,
                                                        size: 24.0,
                                                      ),
                                                      Text(
                                                        widget.enseigneDoc!
                                                            .twitterLink,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
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
                                                    ].divide(const SizedBox(
                                                        width: 12.0)),
                                                  ),
                                              ]
                                                  .divide(const SizedBox(
                                                      height: 12.0))
                                                  .around(const SizedBox(
                                                      height: 12.0)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    Padding(
                                      padding:
                                          const EdgeInsetsDirectional.fromSTEB(
                                              20.0, 0.0, 20.0, 0.0),
                                      child: Container(
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryBackground,
                                          borderRadius:
                                              BorderRadius.circular(20.0),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsetsDirectional
                                              .fromSTEB(16.0, 16.0, 16.0, 16.0),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.max,
                                            children: [
                                              Text(
                                                'Horaires d\'ouverture',
                                                style:
                                                    FlutterFlowTheme.of(context)
                                                        .headlineSmall
                                                        .override(
                                                          font: GoogleFonts
                                                              .interTight(
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
                                              FutureBuilder<
                                                  List<HorairesRecord>>(
                                                future: queryHorairesRecordOnce(
                                                  parent: widget
                                                      .enseigneDoc?.reference,
                                                ),
                                                builder: (context, snapshot) {
                                                  // Customize what your widget looks like when it[s loading.
                                                  if (!snapshot.hasData) {
                                                    return const Center(
                                                      child: SizedBox(
                                                        width: 50.0,
                                                        height: 50.0,
                                                        child:
                                                            SizedBox.shrink(),
                                                      ),
                                                    );
                                                  }
                                                  List<HorairesRecord>
                                                      listViewHorairesRecordList =
                                                      snapshot.data!;

                                                  return ListView.builder(
                                                    padding: EdgeInsets.zero,
                                                    primary: false,
                                                    shrinkWrap: true,
                                                    scrollDirection:
                                                        Axis.vertical,
                                                    itemCount:
                                                        listViewHorairesRecordList
                                                            .length,
                                                    itemBuilder: (context,
                                                        listViewIndex) {
                                                      final listViewHorairesRecord =
                                                          listViewHorairesRecordList[
                                                              listViewIndex];
                                                      return Padding(
                                                        padding:
                                                            const EdgeInsetsDirectional
                                                                .fromSTEB(8.0,
                                                                0.0, 8.0, 0.0),
                                                        child: Container(
                                                          width:
                                                              double.infinity,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .secondaryBackground,
                                                          ),
                                                          child: Padding(
                                                            padding:
                                                                const EdgeInsetsDirectional
                                                                    .fromSTEB(
                                                                    8.0,
                                                                    8.0,
                                                                    8.0,
                                                                    8.0),
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .max,
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .spaceBetween,
                                                              children: [
                                                                Text(
                                                                  listViewHorairesRecord
                                                                      .day!
                                                                      .name,
                                                                  style: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyLarge
                                                                      .override(
                                                                        font: GoogleFonts
                                                                            .inter(
                                                                          fontWeight: FlutterFlowTheme.of(context)
                                                                              .bodyLarge
                                                                              .fontWeight,
                                                                          fontStyle: FlutterFlowTheme.of(context)
                                                                              .bodyLarge
                                                                              .fontStyle,
                                                                        ),
                                                                        letterSpacing:
                                                                            0.0,
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .bodyLarge
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .bodyLarge
                                                                            .fontStyle,
                                                                      ),
                                                                ),
                                                                Builder(
                                                                  builder:
                                                                      (context) {
                                                                    if (listViewHorairesRecord
                                                                        .isOpen) {
                                                                      return Builder(
                                                                        builder:
                                                                            (context) {
                                                                          if (listViewHorairesRecord
                                                                              .isFullDay) {
                                                                            return Text(
                                                                              '${dateTimeFormat(
                                                                                "Hm",
                                                                                listViewHorairesRecord.openingDay,
                                                                                locale: FFLocalizations.of(context).languageCode,
                                                                              )} - ${dateTimeFormat(
                                                                                "Hm",
                                                                                listViewHorairesRecord.closingDay,
                                                                                locale: FFLocalizations.of(context).languageCode,
                                                                              )}',
                                                                              style: FlutterFlowTheme.of(context).bodyMedium.override(
                                                                                    font: GoogleFonts.inter(
                                                                                      fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                                    ),
                                                                                    letterSpacing: 0.0,
                                                                                    fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                                    fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                                  ),
                                                                            );
                                                                          } else {
                                                                            return Column(
                                                                              mainAxisSize: MainAxisSize.max,
                                                                              crossAxisAlignment: CrossAxisAlignment.end,
                                                                              children: [
                                                                                Text(
                                                                                  '${dateTimeFormat(
                                                                                    "Hm",
                                                                                    listViewHorairesRecord.openingMorning,
                                                                                    locale: FFLocalizations.of(context).languageCode,
                                                                                  )} - ${dateTimeFormat(
                                                                                    "Hm",
                                                                                    listViewHorairesRecord.closingMorning,
                                                                                    locale: FFLocalizations.of(context).languageCode,
                                                                                  )}',
                                                                                  style: FlutterFlowTheme.of(context).bodyMedium.override(
                                                                                        font: GoogleFonts.inter(
                                                                                          fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                                          fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                                        ),
                                                                                        letterSpacing: 0.0,
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                                      ),
                                                                                ),
                                                                                Text(
                                                                                  '${dateTimeFormat(
                                                                                    "Hm",
                                                                                    listViewHorairesRecord.openingAfternoon,
                                                                                    locale: FFLocalizations.of(context).languageCode,
                                                                                  )} - ${dateTimeFormat(
                                                                                    "Hm",
                                                                                    listViewHorairesRecord.closingAfternoon,
                                                                                    locale: FFLocalizations.of(context).languageCode,
                                                                                  )}',
                                                                                  style: FlutterFlowTheme.of(context).bodyMedium.override(
                                                                                        font: GoogleFonts.inter(
                                                                                          fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                                          fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                                        ),
                                                                                        letterSpacing: 0.0,
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                                      ),
                                                                                ),
                                                                              ],
                                                                            );
                                                                          }
                                                                        },
                                                                      );
                                                                    } else {
                                                                      return Text(
                                                                        'Ferm\u00E9',
                                                                        style: FlutterFlowTheme.of(context)
                                                                            .bodyMedium
                                                                            .override(
                                                                              font: GoogleFonts.inter(
                                                                                fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                                fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                              ),
                                                                              letterSpacing: 0.0,
                                                                              fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                            ),
                                                                      );
                                                                    }
                                                                  },
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  );
                                                },
                                              ),
                                            ].divide(
                                                const SizedBox(height: 16.0)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ].divide(const SizedBox(height: 20.0)),
                                ),
                              ),
                            ].divide(const SizedBox(height: 20.0)),
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
              ),
            ),
          ),
        );
      },
    );
  }
}
