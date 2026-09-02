import 'dart:async';

import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/animation_utils.dart';
import '/backend/custom_cloud_functions/custom_cloud_function_response_manager.dart';
import '/backend/schema/enums/enums.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/utils/create_account_to_play_dialog.dart';
import '/utils/game_launch_coordinator.dart';
import '/utils/minor_restricted_game_access.dart';
import '/utils/share_links.dart';
import '/utils/game_view_tracker.dart';
import '/utils/winner_identity.dart';
import '/widgets/proxiplay_network_image.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/index.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webviewx_plus/webviewx_plus.dart';
import 'jeu_detail_joueur_page_model.dart';
export 'jeu_detail_joueur_page_model.dart';

/// remplir le container sous l[image par une liste de text
class JeuDetailJoueurPageWidget extends StatefulWidget {
  const JeuDetailJoueurPageWidget({
    super.key,
    required this.gameDoc,
    this.enseigneDoc,
    this.source,
    this.fromQr = false,
  });

  final GamesRecord? gameDoc;
  final EnseignesRecord? enseigneDoc;
  final String? source;
  final bool fromQr;

  static String routeName = 'JeuDetailJoueurPage';
  static String routePath = 'jeuDetailJoueurPage';

  @override
  State<JeuDetailJoueurPageWidget> createState() =>
      _JeuDetailJoueurPageWidgetState();
}

class _JeuDetailJoueurPageWidgetState extends State<JeuDetailJoueurPageWidget> {
  late JeuDetailJoueurPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  // Meme cle utilisee dans les deux branches mutuellement exclusives (avec/
  // sans effectiveEnseigneDoc) de la carte "Regles du jeu" -- une seule est
  // jamais montee a la fois, donc une seule GlobalKey suffit pour y faire
  // defiler la page depuis le lien compact "voir les regles du jeu".
  final _rulesCardKey = GlobalKey();
  bool _hasTrackedView = false;
  bool _isLaunchingGame = false;
  final GameLaunchCoordinator _launchCoordinator =
      GameLaunchCoordinator(screenName: 'JeuDetailJoueurPage');

  // --- Instrumentation temporaire (aucun changement de comportement) ---
  // Trace un attemptId unique sur tout le parcours d'une tentative de
  // participation (avant clic -> appel CF -> navigation -> retour) pour
  // reconstruire la chronologie exacte en cas d'echec d'affichage de la
  // carte a gratter. A retirer une fois le diagnostic termine.
  String? _currentAttemptId;
  String? _pendingPostReturnLogAttemptId;

  String _newAttemptId() {
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${widget.gameDoc?.reference.id ?? 'unknown'}';
    _currentAttemptId = id;
    return id;
  }

  void _logTrace(String stage, Map<String, Object?> details) {}

  Future<void> _trackViewOnce() async {
    if (_hasTrackedView) {
      return;
    }
    _hasTrackedView = true;
    await trackGamePresentationView(
      widget.gameDoc,
      'JeuDetailJoueurPage',
      source: widget.source,
    );
  }

  bool _hasUnlimitedAccess(UsersRecord? user, DateTime now) {
    if (isGuestOrAnonymous || user == null) {
      return false;
    }
    final allGamesAccessUntil = user.allGamesAccessUntil;
    return allGamesAccessUntil != null && allGamesAccessUntil.isAfter(now);
  }

  bool _hasNoRemainingParts(UsersRecord? user, DateTime now) {
    if (isGuestOrAnonymous) {
      return false;
    }
    final animationId = widget.gameDoc?.animationId ?? '';
    if (animationId.trim().isNotEmpty) {
      return false;
    }
    return getSafeRemainingPart(
              user,
              triggerRepair: true,
              source: 'jeu_detail_joueur',
            ) <=
            0 &&
        !_hasUnlimitedAccess(user, now);
  }

  void _setLaunchingGame(bool value) {
    if (!mounted || _isLaunchingGame == value) {
      return;
    }
    safeSetState(() {
      _isLaunchingGame = value;
    });
  }

  String _createAttemptId(String gameId) {
    final safeGameId = gameId.isEmpty ? 'unknown' : gameId;
    return '${DateTime.now().toUtc().microsecondsSinceEpoch}_$safeGameId';
  }

  bool _computeHasPlayedToday(DateTime? lastPlay, DateTime now) {
    return lastPlay != null &&
        lastPlay.year == now.year &&
        lastPlay.month == now.month &&
        lastPlay.day == now.day;
  }

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

  DateTime? _coerceDateTime(dynamic value) {
    if (value is DateTime) {
      return value;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }

  void _logParticipationTrace({
    required String stage,
    required String attemptId,
    required String gameId,
    DateTime? lastPlay,
    bool? hasPlayedToday,
    String? detail,
  }) {
    final now = DateTime.now();
    final remainingPart = getSafeRemainingPart(
      currentUserDocument,
      triggerRepair: true,
      source: 'jeu_detail_trace',
    );
    final suffix =
        (detail != null && detail.isNotEmpty) ? ' detail=$detail' : '';
    debugPrint(
      '[PARTICIPATION_TRACE] '
      'stage=$stage '
      'attemptId=$attemptId '
      'screen=JeuDetailJoueurPage '
      'gameId=$gameId '
      'remaining_part=$remainingPart '
      'lastPlay=${lastPlay?.toIso8601String() ?? 'null'} '
      'hasPlayedToday=${hasPlayedToday?.toString() ?? 'null'} '
      'local=${now.toIso8601String()} '
      'utc=${now.toUtc().toIso8601String()}'
      '$suffix',
    );
  }

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

  // ignore: unused_element
  Future<void> _showQrOnlyGameDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return WebViewAware(
          child: AlertDialog(
            title: const Text('Scanner le QR code'),
            content: const Text(
              'Scannez le QR code affich\u00E9 en boutique pour jouer et valider votre visite.',
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
  }

  Future<EnseignesRecord?> _loadEnseigneForGame(GamesRecord game) async {
    if (game.enseigneId != null) {
      try {
        final enseigne =
            await EnseignesRecord.getDocumentOnce(game.enseigneId!);
        if (enseigne.name.trim().isNotEmpty) {
          return enseigne;
        }
      } catch (_) {}
    }

    final enseigneName = game.enseigneName.trim();
    if (enseigneName.isEmpty) {
      return null;
    }

    try {
      final enseignes = await queryEnseignesRecordOnce(
        queryBuilder: (query) => query.where('name', isEqualTo: enseigneName),
        singleRecord: true,
      );
      if (enseignes.isNotEmpty) {
        return enseignes.first;
      }
    } catch (_) {}

    return null;
  }

  GamesRecord _buildPresentationGame(
    GamesRecord game, {
    EnseignesRecord? enseigne,
  }) {
    final prizeDescription =
        (game.snapshotData['prize_description'] as String? ?? '').trim();
    final prizePresentation =
        (game.snapshotData['prize_presentation'] as String? ?? '').trim();
    final prizeCount = game.snapshotData['prize_count'];
    final countInt = prizeCount is int
        ? prizeCount
        : int.tryParse(prizeCount?.toString() ?? '') ?? 1;
    final snapshotSecondaryPrizes =
        game.snapshotData['secondary_prizes'] as List<dynamic>? ?? const [];

    String presentationDescription() {
      for (final item in game.secondaryPrizes) {
        final presentation = (item['presentation'] as String? ?? '').trim();
        if (presentation.isNotEmpty) {
          return presentation;
        }
      }

      final secondaryDescription = game.secondaryPrizeDescription.trim();
      if (secondaryDescription.isNotEmpty) {
        return secondaryDescription;
      }

      if (prizeDescription.isNotEmpty) {
        return prizeDescription;
      }

      return game.description;
    }

    return GamesRecord.getDocumentFromData(
      <String, dynamic>{
        ...game.snapshotData,
        'name': prizeDescription.isNotEmpty ? prizeDescription : game.name,
        'description': presentationDescription(),
        if (enseigne != null) 'enseigne_id': enseigne.reference,
        if (enseigne != null) 'enseigne_name': enseigne.name,
        if (snapshotSecondaryPrizes.isEmpty && prizeDescription.isNotEmpty)
          'secondary_prizes': [
            <String, dynamic>{
              'name': prizeDescription,
              'count': countInt,
              'presentation': prizePresentation,
            },
          ],
      },
      game.reference,
    );
  }

  Future<void> _openScannedGameDetail(String gameId) async {
    final gameRef = GamesRecord.collection.doc(gameId);
    final scannedGameDoc = await GamesRecord.getDocumentOnce(gameRef);
    final enseigne = await _loadEnseigneForGame(scannedGameDoc);
    final presentationGame = _buildPresentationGame(
      scannedGameDoc,
      enseigne: enseigne,
    );
    if (!mounted) {
      return;
    }

    await context.pushNamed(
      JeuDetailJoueurPageWidget.routeName,
      queryParameters: {
        'gameDoc': serializeParam(
          presentationGame,
          ParamType.Document,
        ),
        if (enseigne != null)
          'enseigneDoc': serializeParam(
            enseigne,
            ParamType.Document,
          ),
        'fromQr': serializeParam(
          true,
          ParamType.bool,
        ),
      }.withoutNulls,
      extra: <String, dynamic>{
        'gameDoc': presentationGame,
        if (enseigne != null) 'enseigneDoc': enseigne,
        'source': 'qr_scan',
      },
    );
  }

  // Un ticket = une participation validee un jour donne (games/{id}/participants,
  // un doc par cle "{dayKey}_{uid}"). Plus un joueur revient sur plusieurs
  // jours, plus il accumule de tickets pour le tirage au sort du lot
  // principal (voir pickMainPrizeWinners cote Cloud Functions).
  Widget _buildYourTicketsRow(TextStyle bodyStyle) {
    final gameDoc = widget.gameDoc;
    final userRef = currentUserReference;
    if (gameDoc == null || userRef == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<QuerySnapshot>(
      stream: gameDoc.reference
          .collection('participants')
          .where('user_id', isEqualTo: userRef)
          .snapshots(),
      builder: (context, snapshot) {
        final ticketCount = snapshot.data?.docs.length ?? 0;
        if (ticketCount <= 0) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.confirmation_number_outlined,
                size: 16.0,
                color: Color(0xFF6B7280),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(
                  'Vos tickets pour ce tirage : $ticketCount',
                  style: bodyStyle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQrOnlyPrimaryButton() {
    if (widget.fromQr) {
      return SizedBox(
        width: double.infinity,
        height: 52.0,
        child: ElevatedButton.icon(
          icon: _isLaunchingGame
              ? const SizedBox(
                  width: 18.0,
                  height: 18.0,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
          label: Text(_isLaunchingGame ? 'Chargement du jeu\u2026' : 'Jouer'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFC0392B),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14.0),
            ),
          ),
          onPressed: _isLaunchingGame
              ? null
              : () async {
                  final attemptId = _newAttemptId();
                  _logTrace('avant_clic_jouer', {
                    'source': 'qr_only_direct_button',
                    'gameId': widget.gameDoc?.reference.id ?? 'unknown',
                    'remaining_part': currentUserDocument?.remainingPart,
                    'lastPlay': 'n_a_qr_only_flow',
                    'hasPlayedToday': 'n_a_qr_only_flow',
                  });
                  if (isGuestOrAnonymous) {
                    await showCreateAccountToPlayDialog(context);
                    return;
                  }
                  if (!await _ensureMinorRestrictedGameEligibility()) {
                    return;
                  }
                  await _launchGame(
                    attemptId: attemptId,
                    participate: () async {
                      _logTrace('avant_appel_cf', {
                        'gameRef': widget.gameDoc!.reference.id,
                        'from_qr': true,
                        'attemptId': attemptId,
                      });
                      try {
                        final result = await FirebaseFunctions.instance
                            .httpsCallable(
                          'participateInGameTransaction',
                        )
                            .call({
                          "gameRef": widget.gameDoc!.reference.id,
                          "from_qr": true,
                          "attemptId": attemptId,
                        });
                        _logTrace('retour_cf', {
                          'succeeded': true,
                          'rawData': result.data,
                        });
                        _model.cloudFunction3sn =
                            ParticipateInGameTransactionCloudFunctionCallResponse(
                          data: ResultParticipationGameStruct.fromMap(
                            result.data,
                          ),
                          succeeded: true,
                          resultAsString: result.data.toString(),
                          jsonBody: result.data,
                        );
                      } on FirebaseFunctionsException catch (error) {
                        _logTrace('retour_cf', {
                          'succeeded': false,
                          'errorCode': error.code,
                          'errorMessage': error.message,
                        });
                        _model.cloudFunction3sn =
                            ParticipateInGameTransactionCloudFunctionCallResponse(
                          data: createResultParticipationGameStruct(
                            message: error.message ?? "Erreur (${error.code})",
                          ),
                          errorCode: error.code,
                          succeeded: false,
                        );
                      }
                      return _model.cloudFunction3sn!;
                    },
                  );
                },
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 52.0,
      child: ElevatedButton.icon(
        icon: const Icon(
          Icons.qr_code_scanner_rounded,
          color: Colors.white,
        ),
        label: const Text('Scanner le QR code en boutique'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFC0392B),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.0),
          ),
        ),
        onPressed: () async {
          if (_isLaunchingGame) {
            return;
          }

          var handled = false;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (scannerContext) {
                return StatefulBuilder(
                  builder: (context, setScannerState) {
                    return Scaffold(
                      appBar: AppBar(
                        title: const Text('Scanner le QR code'),
                        backgroundColor: const Color(0xFF1A1A4E),
                        foregroundColor: Colors.white,
                      ),
                      body: MobileScanner(
                        onDetect: (capture) async {
                          if (handled) {
                            return;
                          }
                          final barcode = capture.barcodes.isNotEmpty
                              ? capture.barcodes.first
                              : null;
                          final url = barcode?.rawValue;
                          if (url == null || url.isEmpty) {
                            return;
                          }
                          if (!url.contains('proxiplay.fr/j/')) {
                            return;
                          }

                          final uri = Uri.tryParse(url);
                          if (uri == null) {
                            return;
                          }
                          final segments = uri.pathSegments;
                          final jIndex = segments.indexOf('j');
                          if (jIndex == -1 || jIndex + 1 >= segments.length) {
                            return;
                          }

                          final scannedGameId = segments[jIndex + 1].trim();
                          if (scannedGameId.isEmpty) {
                            return;
                          }

                          handled = true;
                          setScannerState(() {});

                          Navigator.of(scannerContext).pop();
                          if (!mounted) {
                            return;
                          }

                          if (scannedGameId ==
                              (widget.gameDoc?.reference.id ?? '')) {
                            if (isGuestOrAnonymous) {
                              await showCreateAccountToPlayDialog(context);
                              return;
                            }
                            if (!await _ensureMinorRestrictedGameEligibility()) {
                              return;
                            }
                            final attemptId = _newAttemptId();
                            _logParticipationTrace(
                              stage: 'before_click_play',
                              attemptId: attemptId,
                              gameId: widget.gameDoc?.reference.id ?? 'unknown',
                              detail:
                                  'source=qr_scanner fromQr=true scannedGameId=$scannedGameId',
                            );
                            await _launchGame(
                              attemptId: attemptId,
                              participate: () async {
                                _model.cloudFunction3sn =
                                    await _callParticipateInGameTransaction(
                                  attemptId: attemptId,
                                  payload: {
                                    "gameRef": widget.gameDoc!.reference.id,
                                    "from_qr": true,
                                    "attemptId": attemptId,
                                  },
                                );
                                return _model.cloudFunction3sn!;
                              },
                            );
                            return;
                          }

                          await _openScannedGameDetail(scannedGameId);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Launches a game through [GameLaunchCoordinator]: single-flight lock,
  /// timeout, and explicit logging are handled centrally there. This method
  /// only wires the page-specific participate/navigate/error behavior.
  ///
  /// IMPORTANT: the server-side participation (remaining_part decrement +
  /// participants doc) is already committed by the time [participate]
  /// returns a successful outcome — see the audit notes on
  /// [GameParticipationOutcome]. Nothing here can undo that; this method's
  /// job is to never *compound* that risk (no premature "already played"
  /// local state, no duplicate calls, no stuck loading lock) and to log
  /// precisely enough to tell a real incident from a normal play.
  Future<void> _launchGame({
    required String attemptId,
    required Future<ParticipateInGameTransactionCloudFunctionCallResponse>
            Function()
        participate,
  }) async {
    final gameId = widget.gameDoc?.reference.id ?? 'unknown';
    _logParticipationTrace(
      stage: 'launchGame_enter',
      attemptId: attemptId,
      gameId: gameId,
    );

    await _launchCoordinator.launch(
      gameId: gameId,
      attemptId: attemptId,
      onLaunchingChanged: _setLaunchingGame,
      participate: () async {
        final response = await participate();
        return GameParticipationOutcome(
          succeeded: response.succeeded == true,
          alreadyParticipatedToday: response.jsonBody is Map &&
              (response.jsonBody as Map)['alreadyParticipatedToday'] == true,
          attemptId: attemptId,
          errorCode: response.errorCode,
          errorMessage: response.data?.message,
          raw: response,
        );
      },
      navigate: _navigateToGameScreen,
      onParticipationError: _showLaunchErrorDialog,
      onNavigationFailed: _showNavigationFailureDialog,
      onMountTimedOut: () {
        // Diagnostic only for now (see audit): we deliberately do not
        // trigger any compensation here, only observability. A decision on
        // server-side compensation requires production data first.
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

  /// Pushes [PlayJoueurPageWidget] and waits (bounded) for its mount
  /// confirmation. Any refresh of *this* page's own state (which is what
  /// surfaces "Vous avez deja joue" locally) is deferred to
  /// [awaitReturn] below, i.e. it only happens once the player has actually
  /// come back from a screen that did mount — never before.
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
    _logParticipationTrace(
      stage: 'before_push_play_page',
      attemptId: attemptId,
      gameId: gameId,
      detail: 'alreadyParticipatedToday=${outcome.alreadyParticipatedToday}',
    );

    return GameLaunchCoordinator.runNavigation(
      mountedBy: mountedBy,
      mountTimeout: _launchCoordinator.mountTimeout,
      push: () {
        _logParticipationTrace(
          stage: 'push_play_page_invoked',
          attemptId: attemptId,
          gameId: gameId,
          detail:
              'resultMessage=${response.data?.message ?? ''} resultMessageBonus=${response.data?.messageBonus ?? ''} isWin=${response.data?.isWin == true} prizeId=${response.data?.prizeId ?? ''}',
        );
        final pushFuture =
            AppStateNotifier.instance.runWithCriticalImperativeNavigation(
          () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PlayJoueurPageWidget(
                game: widget.gameDoc,
                resultParticipation: ResultParticipationGameStruct.maybeFromMap(
                  response.jsonBody,
                ),
                source: widget.source,
                attemptId: attemptId,
                onGameScreenMounted: () {
                  if (!mountedBy.isCompleted) {
                    mountedBy.complete();
                  }
                },
              ),
            ),
          ),
        );
        _logParticipationTrace(
          stage: 'after_push_play_page',
          attemptId: attemptId,
          gameId: gameId,
        );
        return pushFuture;
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
          final participantDetailSnapshot = await widget.gameDoc!.reference
              .collection('participants_details')
              .doc(currentUserUid)
              .get();
          final refreshedLastPlay =
              _coerceDateTime(participantDetailSnapshot.data()?['last_play']);
          final refreshedHasPlayedToday =
              _computeHasPlayedToday(refreshedLastPlay, DateTime.now());
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

  Widget _buildLaunchingOverlay(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.14),
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28.0),
          padding: const EdgeInsets.symmetric(
            horizontal: 20.0,
            vertical: 18.0,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20.0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28.0,
                height: 28.0,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: FlutterFlowTheme.of(context).primary,
                ),
              ),
              const SizedBox(height: 14.0),
              Text(
                'Pr\u00E9paration du jeu\u2026',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 15.0,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1F2937),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => JeuDetailJoueurPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'JeuDetailJoueurPage'});
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
      future:
          (widget.gameDoc?.reference == null || currentUserReference == null)
              ? Future.value(const <ParticipantsDetailsRecord>[])
              : queryParticipantsDetailsRecordOnce(
                  parent: widget.gameDoc?.reference,
                  queryBuilder: (participantsDetailsRecord) =>
                      participantsDetailsRecord.where(
                    'user_id',
                    isEqualTo: currentUserReference,
                  ),
                  singleRecord: true,
                ).catchError((_) => <ParticipantsDetailsRecord>[]),
      builder: (context, snapshot) {
        // Customize what your widget looks like when it[s loading.
        if (!snapshot.hasData && !snapshot.hasError) {
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
        if (widget.gameDoc == null) {
          return Scaffold(
            backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
            body: const Center(child: SizedBox.shrink()),
          );
        }
        List<ParticipantsDetailsRecord>
            jeuDetailJoueurPageParticipantsDetailsRecordList =
            snapshot.data ?? const <ParticipantsDetailsRecord>[];
        final jeuDetailJoueurPageParticipantsDetailsRecord =
            jeuDetailJoueurPageParticipantsDetailsRecordList.isNotEmpty
                ? jeuDetailJoueurPageParticipantsDetailsRecordList.first
                : null;
        final now = getCurrentTimestamp;
        final lastPlay = jeuDetailJoueurPageParticipantsDetailsRecord?.lastPlay;
        final hasPlayedToday = lastPlay != null &&
            lastPlay.year == now.year &&
            lastPlay.month == now.month &&
            lastPlay.day == now.day;
        final hasPlayedBefore = lastPlay != null && !hasPlayedToday;
        final noRemainingParts = _hasNoRemainingParts(currentUserDocument, now);

        final endDate = widget.gameDoc?.endDate;
        final gameDoc = widget.gameDoc!;
        final effectiveEnseigneDoc = widget.enseigneDoc ??
            (gameDoc.enseigneId != null
                ? EnseignesRecord.getDocumentFromData(
                    <String, dynamic>{
                      'name': gameDoc.enseigneName,
                    },
                    gameDoc.enseigneId!,
                  )
                : null);
        final gameName = gameDoc.name;
        final gamePhoto = gameDoc.photo;
        final enseigneDisplayName =
            effectiveEnseigneDoc?.name.trim().isNotEmpty == true
                ? effectiveEnseigneDoc!.name.trim()
                : gameDoc.enseigneName.trim();
        final hasWinnerAnnouncement = endDate != null &&
            getCurrentTimestamp.isAfter(endDate) &&
            gameDoc.hasWinner &&
            (gameDoc.mainPrizeWinner != null);
        final hasMainPrizeFlag = gameDoc.hasMainPrize == true;
        final prizeValue = gameDoc.prizeValue;
        final mainPrizeDescription = gameDoc.description.trim();
        // Regle produit :
        // Le lot principal doit etre monetaire.
        // On affiche uniquement si hasMainPrize == true ET prizeValue > 0
        final shouldShowMainPrize = hasMainPrizeFlag &&
            prizeValue > 0 &&
            mainPrizeDescription.isNotEmpty;
        final shouldShowAllPrizesAttributedAnnouncement = endDate != null &&
            getCurrentTimestamp.isAfter(endDate) &&
            !shouldShowMainPrize &&
            !hasWinnerAnnouncement;
        final secondaryPrizes = gameDoc.secondaryPrizes;
        final validSecondaryPrizeItems =
            secondaryPrizes.fold<List<Map<String, dynamic>>>([], (items, item) {
          final name = (item['name'] ?? '').toString().trim();
          final presentation = (item['presentation'] ?? '').toString().trim();
          final countValue = item['count'];
          final count = countValue is num
              ? countValue.toInt()
              : int.tryParse((countValue ?? '').toString()) ?? 0;
          if (name.isEmpty || count <= 0) {
            return items;
          }
          items.add({
            'name': name,
            'presentation': presentation,
            'count': count,
            'countLabel': '$count ${count > 1 ? 'lots' : 'lot'}',
          });
          return items;
        });
        final secondaryPrizeCount = validSecondaryPrizeItems.fold<int>(
          0,
          (total, item) => total + (item['count'] as int),
        );
        final hasSecondaryPrizeContent = validSecondaryPrizeItems.isNotEmpty;
        final secondaryPrizeRulesText = secondaryPrizeCount > 0
            ? '$secondaryPrizeCount lot${secondaryPrizeCount > 1 ? 's' : ''} ${secondaryPrizeCount > 1 ? 'sont' : 'est'} \u00e0 gagner imm\u00e9diatement'
            : 'Des lots sont \u00e0 gagner imm\u00e9diatement';
        String getLotsTitle(int totalLots) =>
            totalLots == 1 ? 'Lot \u00e0 gagner' : 'Lots \u00e0 gagner';
        final detailCardDecoration = BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.0),
          border: Border.all(
            color: const Color(0xFFE5E7EB),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12.0,
              offset: const Offset(0, 2),
            ),
          ],
        );
        // Encart "Offert par" uniquement -- teinte rose tres claire (meme
        // famille que les puces de categorie, 0xFFFCE9F1) pour le distinguer
        // visuellement des cartes neutres (regles du jeu, lots) qui gardent
        // detailCardDecoration.
        final merchantCardDecoration = BoxDecoration(
          color: const Color(0xFFFCE9F1),
          borderRadius: BorderRadius.circular(20.0),
          border: Border.all(
            color: const Color(0xFFF6C9DC),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12.0,
              offset: const Offset(0, 2),
            ),
          ],
        );
        final detailSectionTitleStyle = GoogleFonts.inter(
          fontSize: 20.0,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1F2937),
        );
        final detailItemTitleStyle = GoogleFonts.inter(
          fontSize: 14.0,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF111827),
        );
        final detailBodyStyle = GoogleFonts.inter(
          fontSize: 13.0,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF374151),
          height: 1.35,
        );
        Widget buildMainPrizeWidget(
          String description, {
          bool showDescription = true,
        }) {
          if (!showDescription) {
            return const SizedBox.shrink();
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.workspace_premium_rounded,
                          size: 15.0,
                          color: Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 6.0),
                        Text(
                          'Lot principal',
                          style: detailItemTitleStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6.0),
                    Text(
                      description,
                      style: detailBodyStyle,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10.0,
                  vertical: 4.0,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFA0134D),
                  borderRadius: BorderRadius.circular(20.0),
                ),
                child: Text(
                  'Tirage au sort',
                  style: GoogleFonts.inter(
                    fontSize: 11.0,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          );
        }

        Widget buildSecondaryPrizeWidget({
          required String countLabel,
          required String name,
          String? presentation,
        }) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.emoji_events_outlined,
                          size: 15.0,
                          color: Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 6.0),
                        Expanded(
                          child: Text(
                            name,
                            style: detailItemTitleStyle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6.0),
                    Text(
                      countLabel,
                      style: detailBodyStyle,
                    ),
                    if ((presentation ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4.0),
                      Text(
                        presentation!,
                        style: detailBodyStyle,
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10.0,
                  vertical: 4.0,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B285F),
                  borderRadius: BorderRadius.circular(20.0),
                ),
                child: Text(
                  'Gains imm\u00e9diats',
                  style: GoogleFonts.inter(
                    fontSize: 11.0,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          );
        }

        final totalLots =
            (shouldShowMainPrize ? 1 : 0) + validSecondaryPrizeItems.length;
        final lotsTitle = getLotsTitle(totalLots);
        const bool showShopCard = true;
        final secondaryPrizeWidgets = List<Widget>.generate(
          validSecondaryPrizeItems.length,
          (index) => Padding(
            padding: EdgeInsets.only(
              bottom: index == validSecondaryPrizeItems.length - 1 ? 0.0 : 10.0,
            ),
            child: buildSecondaryPrizeWidget(
              countLabel:
                  validSecondaryPrizeItems[index]['countLabel'] as String,
              name: validSecondaryPrizeItems[index]['name'] as String,
              presentation:
                  validSecondaryPrizeItems[index]['presentation'] as String?,
            ),
          ),
        );
        final heroImage = RepaintBoundary(
          child: ProxiplayNetworkImage(
            imageUrl: gamePhoto,
            width: double.infinity,
            height: 320.0,
            fit: BoxFit.cover,
          ),
        );
        final leftActionVisible = (() {
          final isGuest = currentUserUid == '';
          if (isGuest) return true;
          final endDate = widget.gameDoc?.endDate;
          final isGameOpen =
              endDate != null ? endDate.isAfter(getCurrentTimestamp) : true;
          return isGameOpen;
        })();
        return GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            FocusManager.instance.primaryFocus?.unfocus();
          },
          child: Stack(
            children: [
              Scaffold(
                key: scaffoldKey,
                backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leadingWidth: 60.0,
                  leading: Padding(
                    padding: const EdgeInsets.only(left: 16.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10.0,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                            width: 48.0, height: 48.0),
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: FlutterFlowTheme.of(context).primaryText,
                          size: 18.0,
                        ),
                        onPressed: () async {
                          if (widget.source == 'qr_link') {
                            final isLoggedIn =
                                AppStateNotifier.instance.loggedIn ||
                                    FirebaseAuth.instance.currentUser != null;
                            if (isLoggedIn) {
                              context.goNamed(HomeJoueurPageWidget.routeName);
                            } else {
                              context.goNamed(LoginPageWidget.routeName);
                            }
                          } else if (context.canPop()) {
                            context.pop();
                          } else {
                            context.goNamed(HomeJoueurPageWidget.routeName);
                          }
                        },
                      ),
                    ),
                  ),
                  centerTitle: true,
                  title: Padding(
                    padding: const EdgeInsets.only(right: 20.0),
                    child: SizedBox(
                      height: 40.0,
                      child: Image.asset(
                        'assets/images/logo_D_secondaire.png',
                        height: 40.0,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  actions: [
                    Builder(
                      builder: (context) {
                        if (currentUserUid != '') {
                          return StreamBuilder<List<FavoriteGamesRecord>>(
                            stream: queryFavoriteGamesRecord(
                              parent: currentUserReference,
                              queryBuilder: (favoriteGamesRecord) =>
                                  favoriteGamesRecord.where(
                                'game_id',
                                isEqualTo: widget.gameDoc?.reference,
                              ),
                              singleRecord: true,
                            ),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: Container(
                                    width: 48.0,
                                    height: 48.0,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(12.0),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 10.0,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: SizedBox(
                                        width: 18.0,
                                        height: 18.0,
                                        child: SizedBox.shrink(),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              List<FavoriteGamesRecord> favoriteGamesList =
                                  snapshot.data!;
                              final favoriteGame = favoriteGamesList.isNotEmpty
                                  ? favoriteGamesList.first
                                  : null;

                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: Container(
                                  width: 48.0,
                                  height: 48.0,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(12.0),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 10.0,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                        width: 48.0, height: 48.0),
                                    icon: Icon(
                                      favoriteGame != null
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      color: favoriteGame != null
                                          ? const Color(0xFFA0134D)
                                          : const Color(0xFFA0134D),
                                      size: 20.0,
                                    ),
                                    onPressed: () async {
                                      if (favoriteGame != null) {
                                        await favoriteGame.reference.delete();
                                      } else {
                                        await FavoriteGamesRecord.createDoc(
                                                currentUserReference!)
                                            .set({
                                          ...createFavoriteGamesRecordData(
                                            gameId: widget.gameDoc?.reference,
                                          ),
                                          ...mapToFirestore({
                                            'added_at':
                                                FieldValue.serverTimestamp(),
                                          }),
                                        });

                                        await widget.gameDoc!.reference.update({
                                          ...mapToFirestore({
                                            'favorites':
                                                FieldValue.increment(1),
                                          }),
                                        });
                                        safeSetState(() => _model
                                            .firestoreRequestCompleter = null);
                                        await _model
                                            .waitForFirestoreRequestCompleted();
                                      }
                                    },
                                  ),
                                ),
                              );
                            },
                          );
                        } else {
                          return const SizedBox.shrink();
                        }
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: Container(
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
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 48.0, height: 48.0),
                          icon: const Icon(
                            Icons.share_rounded,
                            color: Colors.white,
                            size: 22.0,
                          ),
                          onPressed: () async {
                            await Share.share(
                              buildAppShareText(
                                title:
                                    '${widget.gameDoc?.name ?? 'ce jeu'} sur ProxiPlay',
                                description: enseigneDisplayName.isNotEmpty
                                    ? 'Disponible chez $enseigneDisplayName.'
                                    : null,
                              ),
                              sharePositionOrigin:
                                  getWidgetBoundingBox(context),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                body: SafeArea(
                  top: true,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          FlutterFlowTheme.of(context).primaryBackground,
                          FlutterFlowTheme.of(context)
                              .primaryBackground
                              .withOpacity(0.95),
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.zero,
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 12.0),
                                // Hero Image Section
                                heroImage,
                                // Main Content Card (White) - Overlapping using Transform
                                Transform.translate(
                                  offset: const Offset(0, -30.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(30.0),
                                        topRight: Radius.circular(30.0),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 30.0,
                                          offset: const Offset(0, -5),
                                          spreadRadius: 0,
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding:
                                          const EdgeInsetsDirectional.fromSTEB(
                                        24.0,
                                        32.0,
                                        24.0,
                                        24.0,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.max,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Game Title
                                          Text(
                                            gameName,
                                            style: GoogleFonts.inter(
                                              fontSize:
                                                  gameName.isEmpty ? 0.0 : 28.0,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF1A1A1A),
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                          const SizedBox(height: 12.0),
                                              if (showShopCard &&
                                                  effectiveEnseigneDoc !=
                                                      null) ...[
                                                const SizedBox(height: 4.0),
                                                Material(
                                                  color: Colors.transparent,
                                                  child: InkWell(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            16.0),
                                                    onTap: () async {
                                                      context.pushNamed(
                                                        EnseigneDetailJoueurPageWidget
                                                            .routeName,
                                                        queryParameters: {
                                                          'enseigneDoc':
                                                              serializeParam(
                                                            effectiveEnseigneDoc,
                                                            ParamType.Document,
                                                          ),
                                                        }.withoutNulls,
                                                        extra: <String,
                                                            dynamic>{
                                                          'enseigneDoc':
                                                              effectiveEnseigneDoc,
                                                        },
                                                      );
                                                    },
                                                    child: Container(
                                                      constraints:
                                                          const BoxConstraints(
                                                              minHeight: 72.0),
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 12.0,
                                                        vertical: 10.0,
                                                      ),
                                                      decoration:
                                                          merchantCardDecoration,
                                                      child: Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          ClipRRect(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        12.0),
                                                            child: SizedBox(
                                                              width: 52.0,
                                                              height: 52.0,
                                                              child: FutureBuilder<
                                                                  List<
                                                                      ImagesRecord>>(
                                                                future:
                                                                    queryImagesRecordOnce(
                                                                  parent: effectiveEnseigneDoc
                                                                      .reference,
                                                                  singleRecord:
                                                                      true,
                                                                ),
                                                                builder: (context,
                                                                    snapshot) {
                                                                  if (snapshot
                                                                          .data
                                                                          ?.isNotEmpty ==
                                                                      true) {
                                                                    return ProxiplayNetworkImage(
                                                                      imageUrl: snapshot
                                                                          .data!
                                                                          .first
                                                                          .url,
                                                                      fit: BoxFit
                                                                          .cover,
                                                                    );
                                                                  }

                                                                  return Container(
                                                                    color: const Color(
                                                                        0xFFF5F6FB),
                                                                    alignment:
                                                                        Alignment
                                                                            .center,
                                                                    child:
                                                                        const Icon(
                                                                      Icons
                                                                          .storefront_rounded,
                                                                      color: Color(
                                                                          0xFFA0134D),
                                                                      size:
                                                                          22.0,
                                                                    ),
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 12.0),
                                                          Expanded(
                                                            child: Column(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  'Offert par',
                                                                  style: GoogleFonts
                                                                      .inter(
                                                                    fontSize:
                                                                        11.0,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: const Color(
                                                                        0xFFA0134D),
                                                                    letterSpacing:
                                                                        0.2,
                                                                  ),
                                                                ),
                                                                Text(
                                                                  effectiveEnseigneDoc
                                                                          .name
                                                                          .trim()
                                                                          .isNotEmpty
                                                                      ? effectiveEnseigneDoc
                                                                          .name
                                                                      : 'Enseigne partenaire',
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontSize:
                                                                        15.0,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color: const Color(
                                                                        0xFF1F2937),
                                                                    letterSpacing:
                                                                        0.0,
                                                                  ),
                                                                ),
                                                                if (effectiveEnseigneDoc.city.trim().isNotEmpty ||
                                                                    effectiveEnseigneDoc
                                                                        .hasGoogleRating())
                                                                  Padding(
                                                                    padding: const EdgeInsets
                                                                        .only(
                                                                        top:
                                                                            4.0),
                                                                    child: Row(
                                                                      children: [
                                                                        if (effectiveEnseigneDoc
                                                                            .city
                                                                            .trim()
                                                                            .isNotEmpty) ...[
                                                                          const Icon(
                                                                            Icons
                                                                                .location_on_sharp,
                                                                            size:
                                                                                14.0,
                                                                            color:
                                                                                Color(0xFF6B7280),
                                                                          ),
                                                                          const SizedBox(
                                                                              width:
                                                                                  4.0),
                                                                          Text(
                                                                            effectiveEnseigneDoc
                                                                                .city,
                                                                            maxLines:
                                                                                1,
                                                                            overflow:
                                                                                TextOverflow.ellipsis,
                                                                            style:
                                                                                GoogleFonts.inter(
                                                                              fontSize: 13.0,
                                                                              fontWeight: FontWeight.w500,
                                                                              color: const Color(0xFF6B7280),
                                                                              letterSpacing: 0.0,
                                                                            ),
                                                                          ),
                                                                        ],
                                                                        if (effectiveEnseigneDoc.city.trim().isNotEmpty &&
                                                                            effectiveEnseigneDoc.hasGoogleRating())
                                                                          Padding(
                                                                            padding: const EdgeInsets
                                                                                .symmetric(
                                                                                horizontal:
                                                                                    6.0),
                                                                            child:
                                                                                Text(
                                                                              '|',
                                                                              style: GoogleFonts.inter(
                                                                                fontSize: 13.0,
                                                                                color: const Color(0xFFD1D5DB),
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        if (effectiveEnseigneDoc
                                                                            .hasGoogleRating()) ...[
                                                                          const Icon(
                                                                            Icons
                                                                                .star_rounded,
                                                                            size:
                                                                                15.0,
                                                                            color:
                                                                                Color(0xFFF59E0B),
                                                                          ),
                                                                          const SizedBox(
                                                                              width:
                                                                                  3.0),
                                                                          Flexible(
                                                                            child:
                                                                                Text(
                                                                              '${formattedGoogleRating(effectiveEnseigneDoc) ?? ''}'
                                                                              '${effectiveEnseigneDoc.googleReviewsCount > 0 ? ' (${effectiveEnseigneDoc.googleReviewsCount} avis)' : ''}',
                                                                              maxLines: 1,
                                                                              overflow: TextOverflow.ellipsis,
                                                                              style: GoogleFonts.inter(
                                                                                fontSize: 13.0,
                                                                                fontWeight: FontWeight.w500,
                                                                                color: const Color(0xFF6B7280),
                                                                                letterSpacing: 0.0,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ],
                                                                    ),
                                                                  ),
                                                                if (effectiveEnseigneDoc
                                                                    .description
                                                                    .trim()
                                                                    .isNotEmpty)
                                                                  Padding(
                                                                    padding: const EdgeInsets
                                                                        .only(
                                                                        top:
                                                                            6.0),
                                                                    child: Text(
                                                                      effectiveEnseigneDoc
                                                                          .description,
                                                                      maxLines:
                                                                          2,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                      style: GoogleFonts
                                                                          .inter(
                                                                        fontSize:
                                                                            12.5,
                                                                        fontWeight:
                                                                            FontWeight.w400,
                                                                        color:
                                                                            const Color(0xFF6B7280),
                                                                        letterSpacing:
                                                                            0.0,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                if (effectiveEnseigneDoc
                                                                    .category
                                                                    .isNotEmpty)
                                                                  Padding(
                                                                    padding: const EdgeInsets
                                                                        .only(
                                                                        top:
                                                                            8.0),
                                                                    child: Wrap(
                                                                      spacing:
                                                                          6.0,
                                                                      runSpacing:
                                                                          6.0,
                                                                      children: effectiveEnseigneDoc
                                                                          .category
                                                                          .take(
                                                                              3)
                                                                          .map(
                                                                            (tag) =>
                                                                                Container(
                                                                              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                                                                              decoration: BoxDecoration(
                                                                                color: const Color(0xFFFCE9F1),
                                                                                borderRadius: BorderRadius.circular(999.0),
                                                                              ),
                                                                              child: Text(
                                                                                tag,
                                                                                style: GoogleFonts.inter(
                                                                                  fontSize: 11.0,
                                                                                  fontWeight: FontWeight.w600,
                                                                                  color: const Color(0xFFA0134D),
                                                                                  letterSpacing: 0.0,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                          )
                                                                          .toList(),
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 8.0),
                                                          // Deuxieme photo (si
                                                          // l'enseigne en a
                                                          // au moins 2) --
                                                          // rien n'est
                                                          // affiche/reserve
                                                          // tant qu'elle n'est
                                                          // pas confirmee
                                                          // disponible.
                                                          FutureBuilder<
                                                              List<
                                                                  ImagesRecord>>(
                                                            future:
                                                                queryImagesRecordOnce(
                                                              parent: effectiveEnseigneDoc
                                                                  .reference,
                                                              limit: 2,
                                                            ),
                                                            builder: (context,
                                                                snapshot) {
                                                              final images =
                                                                  snapshot
                                                                          .data ??
                                                                      const <
                                                                          ImagesRecord>[];
                                                              if (images
                                                                      .length <
                                                                  2) {
                                                                return const SizedBox
                                                                    .shrink();
                                                              }
                                                              return Padding(
                                                                padding: const EdgeInsets
                                                                    .only(
                                                                    right:
                                                                        8.0),
                                                                child: ClipRRect(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              12.0),
                                                                  child:
                                                                      SizedBox(
                                                                    width:
                                                                        56.0,
                                                                    height:
                                                                        56.0,
                                                                    child:
                                                                        ProxiplayNetworkImage(
                                                                      imageUrl:
                                                                          images[1]
                                                                              .url,
                                                                      fit: BoxFit
                                                                          .cover,
                                                                    ),
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                          const Icon(
                                                            Icons
                                                                .chevron_right_rounded,
                                                            color: Color(
                                                                0xFF9CA3AF),
                                                            size: 22.0,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                          const SizedBox(height: 20.0),
                                          // Action Buttons Column
                                          Column(
                                            children: [
                                              if (leftActionVisible)
                                                //     Expanded(
                                                // child:
                                                Builder(
                                                  builder: (context) {
                                                    if (currentUserUid != '') {
                                                      return Builder(
                                                        builder: (context) {
                                                          if (widget.gameDoc
                                                                  ?.prohibitedForMinors ??
                                                              false) {
                                                            return Builder(
                                                              builder:
                                                                  (context) {
                                                                if (widget
                                                                        .gameDoc!
                                                                        .accessMode ==
                                                                    AccessMode
                                                                        .qr_only) {
                                                                  return Visibility(
                                                                    visible: widget
                                                                            .gameDoc!
                                                                            .endDate! >
                                                                        getCurrentTimestamp,
                                                                    child:
                                                                        _buildQrOnlyPrimaryButton(),
                                                                  );
                                                                }
                                                                return Visibility(
                                                                  visible: widget
                                                                          .gameDoc!
                                                                          .endDate! >
                                                                      getCurrentTimestamp,
                                                                  child:
                                                                      FFButtonWidget(
                                                                    showLoadingIndicator:
                                                                        false,
                                                                    onPressed: ((widget.gameDoc!.endDate! <
                                                                                getCurrentTimestamp) ||
                                                                            (noRemainingParts &&
                                                                                !hasPlayedToday) ||
                                                                            _isLaunchingGame)
                                                                        ? null
                                                                        : () async {
                                                                            if (_isLaunchingGame) {
                                                                              return;
                                                                            }
                                                                            if (isGuestOrAnonymous) {
                                                                              await showCreateAccountToPlayDialog(context);
                                                                              return;
                                                                            }
                                                                            if (!await _ensureMinorRestrictedGameEligibility()) {
                                                                              return;
                                                                            }
                                                                            debugPrint(
                                                                              '[GAME_FLOW_DEBUG] participate_start screen=JeuDetailJoueurPage gameId=${widget.gameDoc?.reference.id ?? 'unknown'} source=${widget.source ?? 'unknown'}',
                                                                            );
                                                                            await _launchGame(
                                                                              attemptId: _newAttemptId(),
                                                                              participate: () async {
                                                                                final attemptId = _currentAttemptId ??
                                                                                    _createAttemptId(
                                                                                      widget.gameDoc?.reference.id ?? 'unknown',
                                                                                    );
                                                                                final lastPlay = _coerceDateTime(
                                                                                  jeuDetailJoueurPageParticipantsDetailsRecord?.lastPlay,
                                                                                );
                                                                                final now = DateTime.now();
                                                                                final hasPlayedTodayNow = _computeHasPlayedToday(
                                                                                  lastPlay,
                                                                                  now,
                                                                                );
                                                                                _logParticipationTrace(
                                                                                  stage: 'before_click_play',
                                                                                  attemptId: attemptId,
                                                                                  gameId: widget.gameDoc?.reference.id ?? 'unknown',
                                                                                  lastPlay: lastPlay,
                                                                                  hasPlayedToday: hasPlayedTodayNow,
                                                                                  detail: 'source=${widget.source ?? 'unknown'} fromQr=${widget.fromQr}',
                                                                                );
                                                                                _model.cloudFunction3sn = await _callParticipateInGameTransaction(
                                                                                  attemptId: attemptId,
                                                                                  payload: {
                                                                                    "gameRef": widget.gameDoc!.reference.id,
                                                                                    "from_qr": widget.fromQr,
                                                                                    "attemptId": attemptId,
                                                                                  },
                                                                                );
                                                                                return _model.cloudFunction3sn!;
                                                                              },
                                                                            );
                                                                          },
                                                                    text: () {
                                                                      final noRemainingPartsLive =
                                                                          _hasNoRemainingParts(
                                                                        currentUserDocument,
                                                                        getCurrentTimestamp,
                                                                      );
                                                                      if (noRemainingPartsLive) {
                                                                        return 'Vous n\'avez plus de parties';
                                                                      } else if (widget
                                                                              .gameDoc!
                                                                              .endDate! <
                                                                          getCurrentTimestamp) {
                                                                        return 'Le jeu est termin\u00E9';
                                                                      } else if (hasPlayedToday) {
                                                                        return 'Vous avez d\u00E9j\u00E0 jou\u00E9';
                                                                      } else if (hasPlayedBefore) {
                                                                        return 'Rejouer';
                                                                      } else if (_isLaunchingGame) {
                                                                        return 'Chargement du jeu\u2026';
                                                                      } else {
                                                                        return 'Jouer';
                                                                      }
                                                                    }(),
                                                                    icon: _isLaunchingGame
                                                                        ? SizedBox(
                                                                            width:
                                                                                18.0,
                                                                            height:
                                                                                18.0,
                                                                            child:
                                                                                CircularProgressIndicator(
                                                                              strokeWidth: 2.2,
                                                                              color: Colors.white,
                                                                            ),
                                                                          )
                                                                        : null,
                                                                    options:
                                                                        FFButtonOptions(
                                                                      width: double
                                                                          .infinity,
                                                                      height:
                                                                          56.0,
                                                                      padding: const EdgeInsets
                                                                          .all(
                                                                          0.0),
                                                                      iconPadding: const EdgeInsetsDirectional
                                                                          .fromSTEB(
                                                                          0.0,
                                                                          0.0,
                                                                          0.0,
                                                                          0.0),
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primary,
                                                                      textStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleMedium
                                                                          .override(
                                                                            font:
                                                                                GoogleFonts.inter(
                                                                              fontWeight: FontWeight.w600,
                                                                            ),
                                                                            color:
                                                                                Colors.white,
                                                                            letterSpacing:
                                                                                0.0,
                                                                          ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              16.0),
                                                                      elevation:
                                                                          4.0,
                                                                      disabledColor: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primary
                                                                          .withValues(
                                                                            alpha:
                                                                                0.7,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                );
                                                              },
                                                            );
                                                          } else {
                                                            if (widget.gameDoc!
                                                                    .accessMode ==
                                                                AccessMode
                                                                    .qr_only) {
                                                              return Visibility(
                                                                visible: widget
                                                                        .gameDoc!
                                                                        .endDate! >
                                                                    getCurrentTimestamp,
                                                                child:
                                                                    _buildQrOnlyPrimaryButton(),
                                                              );
                                                            }
                                                            return Visibility(
                                                              visible: widget
                                                                      .gameDoc!
                                                                      .endDate! >
                                                                  getCurrentTimestamp,
                                                              child:
                                                                  AuthUserStreamWidget(
                                                                builder:
                                                                    (context) {
                                                                  final noRemainingPartsLive =
                                                                      _hasNoRemainingParts(
                                                                    currentUserDocument,
                                                                    getCurrentTimestamp,
                                                                  );
                                                                  return FFButtonWidget(
                                                                    showLoadingIndicator:
                                                                        false,
                                                                    onPressed: ((widget.gameDoc!.endDate! <
                                                                                getCurrentTimestamp) ||
                                                                            (noRemainingPartsLive &&
                                                                                !hasPlayedToday) ||
                                                                            _isLaunchingGame)
                                                                        ? null
                                                                        : () async {
                                                                            if (_isLaunchingGame) {
                                                                              return;
                                                                            }
                                                                            if (isGuestOrAnonymous) {
                                                                              await showCreateAccountToPlayDialog(context);
                                                                              return;
                                                                            }
                                                                            debugPrint(
                                                                              '[GAME_FLOW_DEBUG] participate_start screen=JeuDetailJoueurPage gameId=${widget.gameDoc?.reference.id ?? 'unknown'} source=${widget.source ?? 'unknown'}',
                                                                            );
                                                                            await _launchGame(
                                                                              attemptId: _newAttemptId(),
                                                                              participate: () async {
                                                                                final attemptId = _currentAttemptId ??
                                                                                    _createAttemptId(
                                                                                      widget.gameDoc?.reference.id ?? 'unknown',
                                                                                    );
                                                                                final lastPlay = _coerceDateTime(
                                                                                  jeuDetailJoueurPageParticipantsDetailsRecord?.lastPlay,
                                                                                );
                                                                                final now = DateTime.now();
                                                                                final hasPlayedTodayNow = _computeHasPlayedToday(
                                                                                  lastPlay,
                                                                                  now,
                                                                                );
                                                                                _logParticipationTrace(
                                                                                  stage: 'before_click_play',
                                                                                  attemptId: attemptId,
                                                                                  gameId: widget.gameDoc?.reference.id ?? 'unknown',
                                                                                  lastPlay: lastPlay,
                                                                                  hasPlayedToday: hasPlayedTodayNow,
                                                                                  detail: 'source=${widget.source ?? 'unknown'} fromQr=${widget.fromQr}',
                                                                                );
                                                                                _model.cloudFunction3sn2 = await _callParticipateInGameTransaction(
                                                                                  attemptId: attemptId,
                                                                                  payload: {
                                                                                    "gameRef": widget.gameDoc!.reference.id,
                                                                                    "from_qr": widget.fromQr,
                                                                                    "attemptId": attemptId,
                                                                                  },
                                                                                );
                                                                                return _model.cloudFunction3sn2!;
                                                                              },
                                                                            );
                                                                          },
                                                                    text: () {
                                                                      if (noRemainingPartsLive) {
                                                                        return 'Vous n\'avez plus de parties';
                                                                      } else if (widget
                                                                              .gameDoc!
                                                                              .endDate! <
                                                                          getCurrentTimestamp) {
                                                                        return 'Le jeu est termin\u00E9';
                                                                      } else if (hasPlayedToday) {
                                                                        return 'Vous avez d\u00E9j\u00E0 jou\u00E9';
                                                                      } else if (hasPlayedBefore) {
                                                                        return 'Rejouer';
                                                                      } else if (_isLaunchingGame) {
                                                                        return 'Chargement du jeu\u2026';
                                                                      } else {
                                                                        return 'Jouer';
                                                                      }
                                                                    }(),
                                                                    icon: _isLaunchingGame
                                                                        ? SizedBox(
                                                                            width:
                                                                                18.0,
                                                                            height:
                                                                                18.0,
                                                                            child:
                                                                                CircularProgressIndicator(
                                                                              strokeWidth: 2.2,
                                                                              color: Colors.white,
                                                                            ),
                                                                          )
                                                                        : null,
                                                                    options:
                                                                        FFButtonOptions(
                                                                      width: double
                                                                          .infinity,
                                                                      height:
                                                                          56.0,
                                                                      padding: const EdgeInsets
                                                                          .all(
                                                                          0.0),
                                                                      iconPadding: const EdgeInsetsDirectional
                                                                          .fromSTEB(
                                                                          0.0,
                                                                          0.0,
                                                                          0.0,
                                                                          0.0),
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primary,
                                                                      textStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleMedium
                                                                          .override(
                                                                            font:
                                                                                GoogleFonts.inter(
                                                                              fontWeight: FontWeight.w600,
                                                                            ),
                                                                            color:
                                                                                Colors.white,
                                                                            letterSpacing:
                                                                                0.0,
                                                                          ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              16.0),
                                                                      elevation:
                                                                          4.0,
                                                                      disabledColor: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primary
                                                                          .withValues(
                                                                              alpha: 0.7),
                                                                    ),
                                                                  );
                                                                },
                                                              ),
                                                            );
                                                          }
                                                        },
                                                      );
                                                    } else {
                                                      if (widget.gameDoc!
                                                              .accessMode ==
                                                          AccessMode.qr_only) {
                                                        return _buildQrOnlyPrimaryButton();
                                                      }
                                                      // Jeu classique (pas qr_only) : le texte etait
                                                      // reste sur 'Scanner', copie-colle de la branche
                                                      // qr_only ci-dessus jamais ajuste. onPressed est
                                                      // deja correct (propose la creation de compte) ;
                                                      // 'Jouer' est le libelle deja utilise pour ce
                                                      // meme bouton une fois connecte (voir plus haut).
                                                      return FFButtonWidget(
                                                        onPressed: () async {
                                                          await showCreateAccountToPlayDialog(
                                                              context);
                                                        },
                                                        text: 'Jouer',
                                                        options:
                                                            FFButtonOptions(
                                                          width:
                                                              double.infinity,
                                                          height: 56.0,
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(0.0),
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
                                                                        .inter(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                    ),
                                                                    color: Colors
                                                                        .white,
                                                                    letterSpacing:
                                                                        0.0,
                                                                  ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      16.0),
                                                          elevation: 4.0,
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  // ),
                                                ),
                                              // if (leftActionVisible)

                                            ],
                                          ),
                                          const SizedBox(height: 16.0),
                                          // Date de fin + acces rapide aux
                                          // regles (meme carte que plus bas,
                                          // atteinte via _rulesCardKey).
                                          Row(
                                            children: [
                                              if (widget.gameDoc?.endDate !=
                                                  null) ...[
                                                const Icon(
                                                  Icons.access_time_rounded,
                                                  size: 16.0,
                                                  color: Color(0xFF6B7280),
                                                ),
                                                const SizedBox(width: 6.0),
                                                Text(
                                                  'Jusqu\'au ${dateTimeFormat("d/M/y", widget.gameDoc!.endDate, locale: FFLocalizations.of(context).languageCode)}',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13.0,
                                                    fontWeight: FontWeight.w500,
                                                    color: const Color(
                                                        0xFF6B7280),
                                                    letterSpacing: 0.0,
                                                  ),
                                                ),
                                                const SizedBox(width: 8.0),
                                                Text(
                                                  '|',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13.0,
                                                    color: const Color(
                                                        0xFFD1D5DB),
                                                  ),
                                                ),
                                                const SizedBox(width: 8.0),
                                              ],
                                              InkWell(
                                                onTap: () {
                                                  final rulesContext =
                                                      _rulesCardKey
                                                          .currentContext;
                                                  if (rulesContext != null) {
                                                    Scrollable.ensureVisible(
                                                      rulesContext,
                                                      duration: const Duration(
                                                          milliseconds: 400),
                                                      curve: Curves.easeInOut,
                                                    );
                                                  }
                                                },
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'voir les règles du jeu',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 13.0,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: const Color(
                                                            0xFFA0134D),
                                                        letterSpacing: 0.0,
                                                      ),
                                                    ),
                                                    const Icon(
                                                      Icons
                                                          .chevron_right_rounded,
                                                      size: 16.0,
                                                      color:
                                                          Color(0xFFA0134D),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 24.0),
                                          // Winner Announcement Section
                                          if (hasWinnerAnnouncement)
                                            Container(
                                              width: double.infinity,
                                              margin:
                                                  const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                      0.0, 0.0, 0.0, 24.0),
                                              padding:
                                                  const EdgeInsets.all(20.0),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    FlutterFlowTheme.of(context)
                                                        .primary
                                                        .withOpacity(0.1),
                                                    FlutterFlowTheme.of(context)
                                                        .primary
                                                        .withOpacity(0.05),
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(16.0),
                                                border: Border.all(
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .primary
                                                      .withOpacity(0.3),
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsetsDirectional
                                                        .fromSTEB(
                                                        16.0, 16.0, 16.0, 16.0),
                                                child:
                                                    FutureBuilder<UsersRecord?>(
                                                  future:
                                                      fetchWinnerUserIfNeeded(
                                                    gameData: widget
                                                        .gameDoc!.snapshotData,
                                                    winnerRef: widget.gameDoc!
                                                        .mainPrizeWinner,
                                                  ),
                                                  builder: (context, snapshot) {
                                                    final winnerMessage =
                                                        buildWinnerCongratulationsFromSources(
                                                      gameData: widget.gameDoc!
                                                          .snapshotData,
                                                      user: snapshot.data,
                                                      fallback:
                                                          'F\u00E9licitations !',
                                                    );
                                                    return Column(
                                                      mainAxisSize:
                                                          MainAxisSize.max,
                                                      children: [
                                                        if (winnerMessage
                                                            .isNotEmpty)
                                                          // Text(
                                                          //   'Félicitations $winnerName de ${snapshot.data!.city} !',
                                                          //   textAlign:
                                                          //       TextAlign.center,
                                                          //   style:
                                                          //       FlutterFlowTheme.of(
                                                          //               context)
                                                          //           .bodyMedium
                                                          //           .override(
                                                          //             font:
                                                          //                 GoogleFonts
                                                          //                     .inter(
                                                          //               fontWeight: FlutterFlowTheme.of(
                                                          //                       context)
                                                          //                   .bodyMedium
                                                          //                   .fontWeight,
                                                          //               fontStyle: FlutterFlowTheme.of(
                                                          //                       context)
                                                          //                   .bodyMedium
                                                          //                   .fontStyle,
                                                          //             ),
                                                          //             color: FlutterFlowTheme.of(
                                                          //                     context)
                                                          //                 .secondaryText,
                                                          //             letterSpacing:
                                                          //                 0.0,
                                                          //             fontWeight: FlutterFlowTheme.of(
                                                          //                     context)
                                                          //                 .bodyMedium
                                                          //                 .fontWeight,
                                                          //             fontStyle: FlutterFlowTheme.of(
                                                          //                     context)
                                                          //                 .bodyMedium
                                                          //                 .fontStyle,
                                                          //           ),
                                                          // ),
                                                          Text(
                                                            textAlign: TextAlign
                                                                .center,
                                                            winnerMessage,
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
                                                          'Le jeu est termin\u00E9. Revenez bient\u00F4t pour d\u00E9couvrir les prochains jeux !',
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
                                                          height: 8.0)),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          if (shouldShowAllPrizesAttributedAnnouncement)
                                            Container(
                                              width: double.infinity,
                                              margin:
                                                  const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                      0.0, 0.0, 0.0, 24.0),
                                              padding:
                                                  const EdgeInsets.all(20.0),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    FlutterFlowTheme.of(context)
                                                        .primary
                                                        .withOpacity(0.1),
                                                    FlutterFlowTheme.of(context)
                                                        .primary
                                                        .withOpacity(0.05),
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(16.0),
                                                border: Border.all(
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .primary
                                                      .withOpacity(0.3),
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsetsDirectional
                                                        .fromSTEB(
                                                        16.0, 16.0, 16.0, 16.0),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
                                                  children: [
                                                    Text(
                                                      'Tous les lots ont \u00E9t\u00E9 attribu\u00E9s, bravo aux heureux gagnants !',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style:
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
                                                      'Le jeu est terminé. Revenez bientôt pour découvrir les prochains jeux !',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style:
                                                          FlutterFlowTheme.of(
                                                                  context)
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
                                                      height: 8.0)),
                                                ),
                                              ),
                                            ),
                                          // Store Information Section
                                          // if (widget.enseigneDoc != null)
                                          //   Column(
                                          //     mainAxisSize: MainAxisSize.max,
                                          //     crossAxisAlignment: CrossAxisAlignment.start,
                                          //     children: [
                                          // Store Name in Container
                                          // Container(
                                          //   width: double.infinity,
                                          //   margin: EdgeInsets.only(bottom: 16.0),
                                          //   padding: EdgeInsets.all(20.0),
                                          //   decoration: BoxDecoration(
                                          //     color: Colors.white,
                                          //     borderRadius: BorderRadius.circular(24.0),
                                          //     boxShadow: [
                                          //       BoxShadow(
                                          //         color: Colors.black.withOpacity(0.05),
                                          //         blurRadius: 20.0,
                                          //         offset: Offset(0, 4),
                                          //         spreadRadius: 0,
                                          //       ),
                                          //     ],
                                          //   ),
                                          //   child: Text(
                                          //     widget.enseigneDoc!.name,
                                          //     style: GoogleFonts.inter(
                                          //       fontSize: 22.0,
                                          //       fontWeight: FontWeight.bold,
                                          //       color: Color(0xFF1A1A1A),
                                          //       letterSpacing: -0.5,
                                          //     ),
                                          //   ),
                                          // ),
                                          // Store Images - Outside Container
                                          //   FutureBuilder<List<ImagesRecord>>(
                                          //     future: (_model
                                          //                 .firestoreRequestCompleter ??=
                                          //             Completer<
                                          //                 List<ImagesRecord>>()
                                          //               ..complete(
                                          //                   queryImagesRecordOnce(
                                          //                 parent: widget
                                          //                     .enseigneDoc
                                          //                     ?.reference,
                                          //                 limit: 5,
                                          //               )))
                                          //         .future,
                                          //     builder: (context, snapshot) {
                                          //       if (!snapshot.hasData) {
                                          //         return Center(
                                          //         child: Padding(
                                          //           padding: EdgeInsets.all(20.0),
                                          //           child: SizedBox(
                                          //             width: 40.0,
                                          //             height: 40.0,
                                          //             child:
                                          //                 const SizedBox.shrink(),
                                          //             ),
                                          //           ),
                                          //         );
                                          //       }
                                          //       List<ImagesRecord>
                                          //           rowImagesRecordList =
                                          //           snapshot.data!;

                                          //     if (rowImagesRecordList.isEmpty) {
                                          //       return const SizedBox.shrink();
                                          //     }

                                          //     return Container(
                                          //       margin: EdgeInsets.only(bottom: 16.0),
                                          //       child: SingleChildScrollView(
                                          //         scrollDirection:
                                          //             Axis.horizontal,
                                          //         padding: EdgeInsets.symmetric(horizontal: 4.0),
                                          //         child: Row(
                                          //           mainAxisSize:
                                          //               MainAxisSize.max,
                                          //           children: List.generate(
                                          //               rowImagesRecordList.length > 2 ? 2 : rowImagesRecordList.length,
                                          //               (rowIndex) {
                                          //             final rowImagesRecord =
                                          //                 rowImagesRecordList[
                                          //                     rowIndex];
                                          //             return Container(
                                          //               width: (MediaQuery.of(context).size.width - 64.0) * 0.48,
                                          //               height: 160.0,
                                          //               margin: EdgeInsets.only(right: 12.0),
                                          //               decoration: BoxDecoration(
                                          //                 borderRadius:
                                          //                     BorderRadius
                                          //                         .circular(20.0),
                                          //                 boxShadow: [
                                          //                   BoxShadow(
                                          //                     color: Colors.black.withOpacity(0.12),
                                          //                     blurRadius: 20.0,
                                          //                     offset: Offset(0, 4),
                                          //                     spreadRadius: 0,
                                          //                   ),
                                          //                 ],
                                          //               ),
                                          //               child: ClipRRect(
                                          //                 borderRadius:
                                          //                     BorderRadius
                                          //                         .circular(20.0),
                                          //                 child: Image.network(
                                          //                   rowImagesRecord.url,
                                          //                   width: double.infinity,
                                          //                   height: 160.0,
                                          //                   fit: BoxFit.cover,
                                          //                 ),
                                          //               ),
                                          //             );
                                          //           }),
                                          //         ),
                                          //         ),
                                          //       );
                                          //     },
                                          //   ),
                                          // ],
                                          // ),
                                          Builder(
                                            builder: (context) {
                                              if (effectiveEnseigneDoc !=
                                                  null) {
                                                return Column(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
                                                  children: [
                                                    // Website Link Card
                                                    if (!functions
                                                        .checkValueIsEmpty(
                                                            effectiveEnseigneDoc
                                                                .siteWebUrl))
                                                      // Container(
                                                      //   width: double.infinity,
                                                      //   margin: EdgeInsets.only(bottom: 16.0),
                                                      //   decoration: BoxDecoration(
                                                      //     color: Colors.white,
                                                      //     borderRadius: BorderRadius.circular(20.0),
                                                      //     border: Border.all(
                                                      //       color: FlutterFlowTheme.of(context).primary.withOpacity(0.2),
                                                      //       width: 1.5,
                                                      //     ),
                                                      //     boxShadow: [
                                                      //       BoxShadow(
                                                      //         color: Colors.black.withOpacity(0.06),
                                                      //         blurRadius: 20.0,
                                                      //         offset: Offset(0, 4),
                                                      //         spreadRadius: 0,
                                                      //       ),
                                                      //     ],
                                                      //   ),
                                                      //   child: InkWell(
                                                      //     splashColor: Colors.transparent,
                                                      //     focusColor: Colors.transparent,
                                                      //     hoverColor: Colors.transparent,
                                                      //     highlightColor: Colors.transparent,
                                                      //     onTap: () async {
                                                      //       await launchURL(widget
                                                      //           .enseigneDoc!
                                                      //           .siteWebUrl);
                                                      //     },
                                                      //     child: Padding(
                                                      //       padding: EdgeInsets.all(18.0),
                                                      //       child: Row(
                                                      //         mainAxisSize: MainAxisSize.max,
                                                      //         children: [
                                                      //           Container(
                                                      //             width: 48.0,
                                                      //             height: 48.0,
                                                      //             decoration: BoxDecoration(
                                                      //               gradient: LinearGradient(
                                                      //                 begin: Alignment.topLeft,
                                                      //                 end: Alignment.bottomRight,
                                                      //                 colors: [
                                                      //                   FlutterFlowTheme.of(context).primary,
                                                      //                   FlutterFlowTheme.of(context).primary.withOpacity(0.8),
                                                      //                 ],
                                                      //               ),
                                                      //               borderRadius: BorderRadius.circular(14.0),
                                                      //               boxShadow: [
                                                      //                 BoxShadow(
                                                      //                   color: FlutterFlowTheme.of(context).primary.withOpacity(0.3),
                                                      //                   blurRadius: 8.0,
                                                      //                   offset: Offset(0, 2),
                                                      //                 ),
                                                      //               ],
                                                      //             ),
                                                      //             child: Icon(
                                                      //               Icons.language_rounded,
                                                      //               color: Colors.white,
                                                      //               size: 24.0,
                                                      //             ),
                                                      //           ),
                                                      //           SizedBox(width: 16.0),
                                                      //           Expanded(
                                                      //             child: Column(
                                                      //               mainAxisSize: MainAxisSize.min,
                                                      //               crossAxisAlignment: CrossAxisAlignment.start,
                                                      //               children: [
                                                      //                 Text(
                                                      //                   'Site Web',
                                                      //                   style: GoogleFonts.inter(
                                                      //                     fontSize: 12.0,
                                                      //                     fontWeight: FontWeight.w500,
                                                      //                     color: Color(0xFF6B7280),
                                                      //                     letterSpacing: 0.5,
                                                      //                   ),
                                                      //                 ),
                                                      //                 SizedBox(height: 4.0),
                                                      //                 Text(
                                                      //                   widget
                                                      //                       .enseigneDoc!
                                                      //                       .siteWebUrl,
                                                      //                   style: GoogleFonts.inter(
                                                      //                     fontSize: 15.0,
                                                      //                     fontWeight: FontWeight.w600,
                                                      //                     color: Color(0xFF1A1A1A),
                                                      //                     letterSpacing: 0.0,
                                                      //                   ),
                                                      //                   maxLines: 1,
                                                      //                   overflow: TextOverflow.ellipsis,
                                                      //                 ),
                                                      //               ],
                                                      //             ),
                                                      //           ),
                                                      //           Container(
                                                      //             width: 36.0,
                                                      //             height: 36.0,
                                                      //             decoration: BoxDecoration(
                                                      //               color: FlutterFlowTheme.of(context).primary.withOpacity(0.1),
                                                      //               borderRadius: BorderRadius.circular(10.0),
                                                      //             ),
                                                      //             child: Icon(
                                                      //               Icons.open_in_new_rounded,
                                                      //               color: FlutterFlowTheme.of(context).primary,
                                                      //               size: 20.0,
                                                      //             ),
                                                      //           ),
                                                      //         ],
                                                      //       ),
                                                      //     ),
                                                      //   ),
                                                      // ),

                                                      // Social Media Links
                                                      // if (!functions.checkValueIsEmpty(
                                                      //         widget.enseigneDoc!
                                                      //             .facebookLink) ||
                                                      //     !functions.checkValueIsEmpty(
                                                      //         widget.enseigneDoc!
                                                      //             .twitterLink) ||
                                                      //     !functions.checkValueIsEmpty(
                                                      //         widget.enseigneDoc!
                                                      //             .instagramLink))
                                                      //   Container(
                                                      //       width: double.infinity,
                                                      //     margin: EdgeInsets.only(bottom: 16.0),
                                                      //     padding: EdgeInsets.all(16.0),
                                                      //       decoration: BoxDecoration(
                                                      //       color: Colors.white,
                                                      //       borderRadius: BorderRadius.circular(16.0),
                                                      //       boxShadow: [
                                                      //         BoxShadow(
                                                      //           color: Colors.black.withOpacity(0.05),
                                                      //           blurRadius: 15.0,
                                                      //           offset: Offset(0, 2),
                                                      //           spreadRadius: 0,
                                                      //         ),
                                                      //       ],
                                                      //     ),
                                                      //     child: Wrap(
                                                      //       spacing: 12.0,
                                                      //       runSpacing: 12.0,
                                                      //           children: [
                                                      //             if (!functions
                                                      //             .checkValueIsEmpty(widget
                                                      //                         .enseigneDoc!
                                                      //                 .facebookLink))
                                                      //                     InkWell(
                                                      //             splashColor: Colors.transparent,
                                                      //             focusColor: Colors.transparent,
                                                      //             hoverColor: Colors.transparent,
                                                      //             highlightColor: Colors.transparent,
                                                      //             onTap: () async {
                                                      //                         await launchURL(widget
                                                      //                             .enseigneDoc!
                                                      //                   .facebookLink);
                                                      //             },
                                                      //             child: Container(
                                                      //               padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                                      //               decoration: BoxDecoration(
                                                      //                 color: Color(0xFF1877F2).withOpacity(0.1),
                                                      //                 borderRadius: BorderRadius.circular(12.0),
                                                      //               ),
                                                      //                 child: Row(
                                                      //                 mainAxisSize: MainAxisSize.min,
                                                      //                   children: [
                                                      //                     Icon(
                                                      //                     Icons.facebook,
                                                      //                     color: Color(0xFF1877F2),
                                                      //                     size: 18.0,
                                                      //                   ),
                                                      //                   SizedBox(width: 6.0),
                                                      //                   Text(
                                                      //                     'Facebook',
                                                      //                     style: GoogleFonts.inter(
                                                      //                       fontSize: 13.0,
                                                      //                       fontWeight: FontWeight.w600,
                                                      //                       color: Color(0xFF1877F2),
                                                      //                     ),
                                                      //                   ),
                                                      //                 ],
                                                      //               ),
                                                      //                 ),
                                                      //               ),
                                                      //             if (!functions
                                                      //                 .checkValueIsEmpty(widget
                                                      //                     .enseigneDoc!
                                                      //                     .instagramLink))
                                                      //                     InkWell(
                                                      //             splashColor: Colors.transparent,
                                                      //             focusColor: Colors.transparent,
                                                      //             hoverColor: Colors.transparent,
                                                      //             highlightColor: Colors.transparent,
                                                      //             onTap: () async {
                                                      //                         await launchURL(widget
                                                      //                             .enseigneDoc!
                                                      //                             .instagramLink);
                                                      //                       },
                                                      //             child: Container(
                                                      //               padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                                      //               decoration: BoxDecoration(
                                                      //                 color: Color(0xFFE4405F).withOpacity(0.1),
                                                      //                 borderRadius: BorderRadius.circular(12.0),
                                                      //               ),
                                                      //               child: Row(
                                                      //                 mainAxisSize: MainAxisSize.min,
                                                      //                 children: [
                                                      //                   FaIcon(
                                                      //                     FontAwesomeIcons.instagram,
                                                      //                     color: Color(0xFFE4405F),
                                                      //                     size: 18.0,
                                                      //                   ),
                                                      //                   SizedBox(width: 6.0),
                                                      //                   Text(
                                                      //                     'Instagram',
                                                      //                     style: GoogleFonts.inter(
                                                      //                       fontSize: 13.0,
                                                      //                       fontWeight: FontWeight.w600,
                                                      //                       color: Color(0xFFE4405F),
                                                      //                     ),
                                                      //                   ),
                                                      //                 ],
                                                      //               ),
                                                      //                 ),
                                                      //               ),
                                                      //             if (!functions
                                                      //                 .checkValueIsEmpty(widget
                                                      //                     .enseigneDoc!
                                                      //                     .twitterLink))
                                                      //                     InkWell(
                                                      //             splashColor: Colors.transparent,
                                                      //             focusColor: Colors.transparent,
                                                      //             hoverColor: Colors.transparent,
                                                      //             highlightColor: Colors.transparent,
                                                      //             onTap: () async {
                                                      //                         await launchURL(widget
                                                      //                             .enseigneDoc!
                                                      //                             .twitterLink);
                                                      //                       },
                                                      //             child: Container(
                                                      //               padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                                      //               decoration: BoxDecoration(
                                                      //                 color: Color(0xFF1DA1F2).withOpacity(0.1),
                                                      //                 borderRadius: BorderRadius.circular(12.0),
                                                      //               ),
                                                      //               child: Row(
                                                      //                 mainAxisSize: MainAxisSize.min,
                                                      //                 children: [
                                                      //                   FaIcon(
                                                      //                     FontAwesomeIcons.twitter,
                                                      //                     color: Color(0xFF1DA1F2),
                                                      //                     size: 18.0,
                                                      //                   ),
                                                      //                   SizedBox(width: 6.0),
                                                      //                   Text(
                                                      //                     'Twitter',
                                                      //                     style: GoogleFonts.inter(
                                                      //                       fontSize: 13.0,
                                                      //                       fontWeight: FontWeight.w600,
                                                      //                       color: Color(0xFF1DA1F2),
                                                      //                     ),
                                                      //                   ),
                                                      //                 ],
                                                      //               ),
                                                      //             ),
                                                      //           ),
                                                      //       ],
                                                      //     ),
                                                      //   ),
                                                      FutureBuilder<
                                                          List<HorairesRecord>>(
                                                        future:
                                                            queryHorairesRecordOnce(
                                                          parent:
                                                              effectiveEnseigneDoc
                                                                  .reference,
                                                          queryBuilder:
                                                              (horairesRecord) =>
                                                                  horairesRecord
                                                                      .orderBy(
                                                                          'created_time'),
                                                        ),
                                                        builder: (context,
                                                            snapshot) {
                                                          // Customize what your widget looks like when it[s loading.
                                                          if (!snapshot
                                                              .hasData) {
                                                            return const Center(
                                                              child: SizedBox(
                                                                width: 50.0,
                                                                height: 50.0,
                                                                child: SizedBox
                                                                    .shrink(),
                                                              ),
                                                            );
                                                          }
                                                          return Container(
                                                            decoration:
                                                                const BoxDecoration(),
                                                          );
                                                        },
                                                      ),
                                                    FutureBuilder<
                                                        List<HorairesRecord>>(
                                                      future:
                                                          queryHorairesRecordOnce(
                                                        parent:
                                                            effectiveEnseigneDoc
                                                                .reference,
                                                        queryBuilder:
                                                            (horairesRecord) =>
                                                                horairesRecord
                                                                    .orderBy(
                                                                        'created_time'),
                                                      ),
                                                      builder:
                                                          (context, snapshot) {
                                                        // Customize what your widget looks like when it[s loading.
                                                        if (!snapshot.hasData) {
                                                          return const Center(
                                                            child: SizedBox(
                                                              width: 50.0,
                                                              height: 50.0,
                                                              child: SizedBox
                                                                  .shrink(),
                                                            ),
                                                          );
                                                        }
                                                        // List<HorairesRecord>
                                                        //     containerHorairesRecordList =
                                                        //     snapshot.data!;

                                                        // return Visibility(
                                                        //   visible:
                                                        //       containerHorairesRecordList
                                                        //           .isNotEmpty,
                                                        //   child: Container(
                                                        //     width: double.infinity,
                                                        //     margin: EdgeInsets.only(bottom: 16.0),
                                                        //     decoration: BoxDecoration(
                                                        //       color: Colors.white,
                                                        //       borderRadius: BorderRadius.circular(24.0),
                                                        //       boxShadow: [
                                                        //         BoxShadow(
                                                        //           color: Colors.black.withOpacity(0.05),
                                                        //           blurRadius: 20.0,
                                                        //           offset: Offset(0, 4),
                                                        //           spreadRadius: 0,
                                                        //         ),
                                                        //       ],
                                                        //     ),
                                                        //     child: Padding(
                                                        //       padding: EdgeInsets.all(20.0),
                                                        //       child: Column(
                                                        //         mainAxisSize:
                                                        //             MainAxisSize.max,
                                                        //         crossAxisAlignment: CrossAxisAlignment.start,
                                                        //         children: [
                                                        //           Text(
                                                        //             'Horaires d\'ouverture[,
                                                        //             style: GoogleFonts.inter(
                                                        //               fontSize: 20.0,
                                                        //               fontWeight: FontWeight.bold,
                                                        //               color: Color(0xFF1A1A1A),
                                                        //               letterSpacing: -0.5,
                                                        //             ),
                                                        //           ),
                                                        //           SizedBox(height: 20.0),
                                                        //               Builder(
                                                        //                 builder:
                                                        //                     (context) {
                                                        //                   final addHoraireCommercantPageVar =
                                                        //                       containerHorairesRecordList
                                                        //                           .toList();

                                                        //                   return ListView
                                                        //                       .separated(
                                                        //                     padding:
                                                        //                         EdgeInsets
                                                        //                             .zero,
                                                        //                     primary:
                                                        //                         false,
                                                        //                     shrinkWrap:
                                                        //                         true,
                                                        //                     scrollDirection:
                                                        //                         Axis.vertical,
                                                        //                     itemCount:
                                                        //                         addHoraireCommercantPageVar
                                                        //                             .length,
                                                        //                     separatorBuilder: (_,
                                                        //                             __) =>
                                                        //                         SizedBox(
                                                        //                             height: 10.0),
                                                        //                     itemBuilder:
                                                        //                         (context,
                                                        //                             addHoraireCommercantPageVarIndex) {
                                                        //                       final addHoraireCommercantPageVarItem =
                                                        //                           addHoraireCommercantPageVar[addHoraireCommercantPageVarIndex];
                                                        //                       return InkWell(
                                                        //                         splashColor: Colors.transparent,
                                                        //                         focusColor: Colors.transparent,
                                                        //                         hoverColor: Colors.transparent,
                                                        //                         highlightColor: Colors.transparent,
                                                        //                         onTap: () async {
                                                        //                           await showModalBottomSheet(
                                                        //                             isScrollControlled: true,
                                                        //                             backgroundColor: Colors.transparent,
                                                        //                             enableDrag: false,
                                                        //                             context: context,
                                                        //                             builder: (context) {
                                                        //                               return WebViewAware(
                                                        //                                 child: GestureDetector(
                                                        //                                   onTap: () {
                                                        //                                     FocusScope.of(context).unfocus();
                                                        //                                     FocusManager.instance.primaryFocus?.unfocus();
                                                        //                                   },
                                                        //                                   child: Padding(
                                                        //                                     padding: MediaQuery.viewInsetsOf(context),
                                                        //                                     child: Container(
                                                        //                                       height: MediaQuery.sizeOf(context).height * 0.7,
                                                        //                                       child: UpdateHoraireCardWidget(
                                                        //                                         day: addHoraireCommercantPageVarItem,
                                                        //                                       ),
                                                        //                                     ),
                                                        //                                   ),
                                                        //                                 ),
                                                        //                               );
                                                        //                             },
                                                        //                           ).then((value) => safeSetState(() {}));
                                                        //                         },
                                                        //                         child: Container(
                                                        //                           width: double.infinity,
                                                        //                           padding: EdgeInsets.symmetric(vertical: 12.0),
                                                        //                           child: Row(
                                                        //                             mainAxisSize: MainAxisSize.max,
                                                        //                             mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        //                             crossAxisAlignment: CrossAxisAlignment.start,
                                                        //                             children: [
                                                        //                               Text(
                                                        //                                 addHoraireCommercantPageVarItem.day!.name,
                                                        //                                 style: GoogleFonts.inter(
                                                        //                                   fontSize: 15.0,
                                                        //                                   fontWeight: FontWeight.w600,
                                                        //                                   color: Color(0xFF1A1A1A),
                                                        //                                   letterSpacing: 0.0,
                                                        //                                 ),
                                                        //                               ),
                                                        //                               Expanded(
                                                        //                                 child: Align(
                                                        //                                   alignment: Alignment.centerRight,
                                                        //                                   child: Builder(
                                                        //                                     builder: (context) {
                                                        //                                       if (addHoraireCommercantPageVarItem.isOpen) {
                                                        //                                         return Builder(
                                                        //                                           builder: (context) {
                                                        //                                             if (!addHoraireCommercantPageVarItem.isFullDay) {
                                                        //                                               return Text(
                                                        //                                                 [${dateTimeFormat(
                                                        //                                                   "Hm",
                                                        //                                                   addHoraireCommercantPageVarItem.openingDay,
                                                        //                                                   locale: FFLocalizations.of(context).languageCode,
                                                        //                                                 )} - ${dateTimeFormat(
                                                        //                                                   "Hm",
                                                        //                                                   addHoraireCommercantPageVarItem.closingDay,
                                                        //                                                   locale: FFLocalizations.of(context).languageCode,
                                                        //                                                 )}[,
                                                        //                                                 textAlign: TextAlign.right,
                                                        //                                                 style: GoogleFonts.inter(
                                                        //                                                   fontSize: 14.0,
                                                        //                                                   fontWeight: FontWeight.w500,
                                                        //                                                   color: Color(0xFF6B7280),
                                                        //                                                   letterSpacing: 0.0,
                                                        //                                                 ),
                                                        //                                               );
                                                        //                                             } else {
                                                        //                                               return Column(
                                                        //                                                 mainAxisSize: MainAxisSize.min,
                                                        //                                                 crossAxisAlignment: CrossAxisAlignment.end,
                                                        //                                                 children: [
                                                        //                                                   Text(
                                                        //                                                     [${dateTimeFormat(
                                                        //                                                       "Hm",
                                                        //                                                       addHoraireCommercantPageVarItem.openingMorning,
                                                        //                                                       locale: FFLocalizations.of(context).languageCode,
                                                        //                                                     )} - ${dateTimeFormat(
                                                        //                                                       "Hm",
                                                        //                                                       addHoraireCommercantPageVarItem.closingMorning,
                                                        //                                                       locale: FFLocalizations.of(context).languageCode,
                                                        //                                                     )}[,
                                                        //                                                     textAlign: TextAlign.right,
                                                        //                                                     style: GoogleFonts.inter(
                                                        //                                                       fontSize: 14.0,
                                                        //                                                       fontWeight: FontWeight.w500,
                                                        //                                                       color: Color(0xFF6B7280),
                                                        //                                                       letterSpacing: 0.0,
                                                        //                                                     ),
                                                        //                                                   ),
                                                        //                                                   SizedBox(height: 4.0),
                                                        //                                                   Text(
                                                        //                                                     [${dateTimeFormat(
                                                        //                                                       "Hm",
                                                        //                                                       addHoraireCommercantPageVarItem.openingAfternoon,
                                                        //                                                       locale: FFLocalizations.of(context).languageCode,
                                                        //                                                     )} - ${dateTimeFormat(
                                                        //                                                       "Hm",
                                                        //                                                       addHoraireCommercantPageVarItem.closingAfternoon,
                                                        //                                                       locale: FFLocalizations.of(context).languageCode,
                                                        //                                                     )}[,
                                                        //                                                     textAlign: TextAlign.right,
                                                        //                                                     style: GoogleFonts.inter(
                                                        //                                                       fontSize: 14.0,
                                                        //                                                       fontWeight: FontWeight.w500,
                                                        //                                                       color: Color(0xFF6B7280),
                                                        //                                                       letterSpacing: 0.0,
                                                        //                                                     ),
                                                        //                                                   ),
                                                        //                                                 ],
                                                        //                                               );
                                                        //                                             }
                                                        //                                           },
                                                        //                                         );
                                                        //                                       } else {
                                                        //                                         return Text(
                                                        //                                           'Fermé',
                                                        //                                           textAlign: TextAlign.right,
                                                        //                                           style: GoogleFonts.inter(
                                                        //                                             fontSize: 14.0,
                                                        //                                             fontWeight: FontWeight.w500,
                                                        //                                             color: Color(0xFF9CA3AF),
                                                        //                                             letterSpacing: 0.0,
                                                        //                                           ),
                                                        //                                         );
                                                        //                                       }
                                                        //                                     },
                                                        //                                   ),
                                                        //                                 ),
                                                        //                               ),
                                                        //                             ],
                                                        //                           ),
                                                        //                         ),
                                                        //                       );
                                                        //                     },
                                                        //                   );
                                                        //                 },
                                                        //               ),
                                                        //         ],
                                                        //       ),
                                                        //     ),
                                                        //   ),
                                                        // );
                                                        return Container();
                                                      },
                                                    ),
                                                    if (hasSecondaryPrizeContent ||
                                                        shouldShowMainPrize)
                                                      Container(
                                                        width: double.infinity,
                                                        margin: const EdgeInsets
                                                            .only(bottom: 16.0),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      20.0),
                                                          border: Border.all(
                                                            color: const Color(
                                                                0xFFE7EAF3),
                                                          ),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              blurRadius: 18.0,
                                                              color: const Color(
                                                                      0xFF1F3A5F)
                                                                  .withOpacity(
                                                                      0.06),
                                                              offset:
                                                                  const Offset(
                                                                      0.0,
                                                                      10.0),
                                                            ),
                                                          ],
                                                        ),
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(16.0),
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                lotsTitle,
                                                                style:
                                                                    detailSectionTitleStyle,
                                                              ),
                                                              if (shouldShowMainPrize) ...[
                                                                const SizedBox(
                                                                    height:
                                                                        14.0),
                                                                buildMainPrizeWidget(
                                                                  mainPrizeDescription,
                                                                ),
                                                              ],
                                                              if (hasSecondaryPrizeContent) ...[
                                                                const SizedBox(
                                                                    height:
                                                                        14.0),
                                                                ...secondaryPrizeWidgets,
                                                              ],
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    Container(
                                                      key: _rulesCardKey,
                                                      width: double.infinity,
                                                      margin:
                                                          const EdgeInsets.only(
                                                              bottom: 16.0),
                                                      padding:
                                                          const EdgeInsets.all(
                                                              16.0),
                                                      decoration:
                                                          detailCardDecoration,
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            'R\u00E8gles du jeu',
                                                            style:
                                                                detailSectionTitleStyle,
                                                          ),
                                                          const SizedBox(
                                                              height: 12.0),
                                                          Row(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              const Icon(
                                                                Icons
                                                                    .access_time_rounded,
                                                                size: 16.0,
                                                                color: Color(
                                                                    0xFF6B7280),
                                                              ),
                                                              const SizedBox(
                                                                  width: 8.0),
                                                              Expanded(
                                                                child: Text(
                                                                  shouldShowMainPrize
                                                                      ? 'D\u00E9but du jeu le ${widget.gameDoc?.startDate != null ? dateTimeFormat("d/M/y", widget.gameDoc!.startDate, locale: FFLocalizations.of(context).languageCode) : '-'}'
                                                                      : 'Fin du jeu le ${widget.gameDoc?.endDate != null ? dateTimeFormat("d/M/y", widget.gameDoc!.endDate, locale: FFLocalizations.of(context).languageCode) : '-'}',
                                                                  style:
                                                                      detailBodyStyle,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                              height: 8.0),
                                                          Row(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Icon(
                                                                widget.gameDoc
                                                                            ?.accessMode ==
                                                                        AccessMode
                                                                            .qr_only
                                                                    ? Icons
                                                                        .qr_code_scanner_rounded
                                                                    : Icons
                                                                        .pan_tool_alt_rounded,
                                                                size: 16.0,
                                                                color: const Color(
                                                                    0xFF6B7280),
                                                              ),
                                                              const SizedBox(
                                                                  width: 8.0),
                                                              Expanded(
                                                                child: Text(
                                                                  widget.gameDoc
                                                                              ?.accessMode ==
                                                                          AccessMode
                                                                              .qr_only
                                                                      ? 'Scannez le QR code en boutique pour d\u00E9couvrir si vous avez gagn\u00E9'
                                                                      : 'Grattez la zone ci-dessus pour d\u00E9couvrir si vous avez gagn\u00E9',
                                                                  style:
                                                                      detailBodyStyle,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                              height: 8.0),
                                                          if (shouldShowMainPrize)
                                                            Row(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                const Icon(
                                                                  Icons
                                                                      .card_giftcard_rounded,
                                                                  size: 16.0,
                                                                  color: Color(
                                                                      0xFF6B7280),
                                                                ),
                                                                const SizedBox(
                                                                    width: 8.0),
                                                                Expanded(
                                                                  child: Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    children: [
                                                                      Text(
                                                                        'Le lot principal sera attribu\u00E9 par tirage au sort le ${widget.gameDoc?.endDate != null ? dateTimeFormat("d/M/y", widget.gameDoc!.endDate, locale: FFLocalizations.of(context).languageCode) : '-'}',
                                                                        style:
                                                                            detailBodyStyle,
                                                                      ),
                                                                      const SizedBox(
                                                                          height:
                                                                              4.0),
                                                                      Text(
                                                                        'Plus vous participez, plus vous augmentez vos chances lors du tirage au sort',
                                                                        style:
                                                                            detailBodyStyle,
                                                                      ),
                                                                      _buildYourTicketsRow(
                                                                          detailBodyStyle),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          const SizedBox(
                                                              height: 8.0),
                                                          if (hasSecondaryPrizeContent)
                                                            Row(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                const Icon(
                                                                  Icons
                                                                      .emoji_events_outlined,
                                                                  size: 16.0,
                                                                  color: Color(
                                                                      0xFF6B7280),
                                                                ),
                                                                const SizedBox(
                                                                    width: 8.0),
                                                                Expanded(
                                                                  child: Text(
                                                                    secondaryPrizeRulesText,
                                                                    style:
                                                                        detailBodyStyle,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ].divide(const SizedBox(
                                                      height: 10.0)),
                                                );
                                              } else {
                                                return Column(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
                                                  children: [
                                                    Container(
                                                      width: double.infinity,
                                                      decoration: BoxDecoration(
                                                        color: FlutterFlowTheme
                                                                .of(context)
                                                            .secondaryBackground,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20.0),
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(10.0),
                                                        child: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.max,
                                                          children: [
                                                            Text(
                                                              'Les informations de cette enseigne sont indisponibles pour le moment.',
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
                                                          ].divide(
                                                              const SizedBox(
                                                                  height:
                                                                      10.0)),
                                                        ),
                                                      ),
                                                    ),
                                                    if (hasSecondaryPrizeContent ||
                                                        shouldShowMainPrize)
                                                      Container(
                                                        width: double.infinity,
                                                        margin: const EdgeInsets
                                                            .only(bottom: 16.0),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      20.0),
                                                          border: Border.all(
                                                            color: const Color(
                                                                0xFFE7EAF3),
                                                          ),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              blurRadius: 18.0,
                                                              color: const Color(
                                                                      0xFF1F3A5F)
                                                                  .withOpacity(
                                                                      0.06),
                                                              offset:
                                                                  const Offset(
                                                                      0.0,
                                                                      10.0),
                                                            ),
                                                          ],
                                                        ),
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(16.0),
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                lotsTitle,
                                                                style:
                                                                    detailSectionTitleStyle,
                                                              ),
                                                              if (shouldShowMainPrize) ...[
                                                                const SizedBox(
                                                                    height:
                                                                        14.0),
                                                                buildMainPrizeWidget(
                                                                  mainPrizeDescription,
                                                                ),
                                                              ],
                                                              if (hasSecondaryPrizeContent) ...[
                                                                const SizedBox(
                                                                    height:
                                                                        14.0),
                                                                ...secondaryPrizeWidgets,
                                                              ],
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    Container(
                                                      key: _rulesCardKey,
                                                      width: double.infinity,
                                                      margin:
                                                          const EdgeInsets.only(
                                                              bottom: 16.0),
                                                      padding:
                                                          const EdgeInsets.all(
                                                              16.0),
                                                      decoration:
                                                          detailCardDecoration,
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            'R\u00E8gles du jeu',
                                                            style:
                                                                detailSectionTitleStyle,
                                                          ),
                                                          const SizedBox(
                                                              height: 12.0),
                                                          Row(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              const Icon(
                                                                Icons
                                                                    .access_time_rounded,
                                                                size: 16.0,
                                                                color: Color(
                                                                    0xFF6B7280),
                                                              ),
                                                              const SizedBox(
                                                                  width: 8.0),
                                                              Expanded(
                                                                child: Text(
                                                                  shouldShowMainPrize
                                                                      ? 'D\u00E9but du jeu le ${widget.gameDoc?.startDate != null ? dateTimeFormat("d/M/y", widget.gameDoc!.startDate, locale: FFLocalizations.of(context).languageCode) : '-'}'
                                                                      : 'Fin du jeu le ${widget.gameDoc?.endDate != null ? dateTimeFormat("d/M/y", widget.gameDoc!.endDate, locale: FFLocalizations.of(context).languageCode) : '-'}',
                                                                  style:
                                                                      detailBodyStyle,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                              height: 8.0),
                                                          Row(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Icon(
                                                                widget.gameDoc
                                                                            ?.accessMode ==
                                                                        AccessMode
                                                                            .qr_only
                                                                    ? Icons
                                                                        .qr_code_scanner_rounded
                                                                    : Icons
                                                                        .pan_tool_alt_rounded,
                                                                size: 16.0,
                                                                color: const Color(
                                                                    0xFF6B7280),
                                                              ),
                                                              const SizedBox(
                                                                  width: 8.0),
                                                              Expanded(
                                                                child: Text(
                                                                  widget.gameDoc
                                                                              ?.accessMode ==
                                                                          AccessMode
                                                                              .qr_only
                                                                      ? 'Scannez le QR code en boutique pour découvrir si vous avez gagné'
                                                                      : 'Grattez la zone ci-dessus pour découvrir si vous avez gagné',
                                                                  style:
                                                                      detailBodyStyle,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                              height: 8.0),
                                                          if (shouldShowMainPrize)
                                                            Row(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                const Icon(
                                                                  Icons
                                                                      .emoji_events_outlined,
                                                                  size: 16.0,
                                                                  color: Color(
                                                                      0xFF6B7280),
                                                                ),
                                                                const SizedBox(
                                                                    width: 8.0),
                                                                Expanded(
                                                                  child: Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    children: [
                                                                      Text(
                                                                        'Le lot principal sera attribu\u00E9 par tirage au sort le ${widget.gameDoc?.endDate != null ? dateTimeFormat("d/M/y", widget.gameDoc!.endDate, locale: FFLocalizations.of(context).languageCode) : '-'}',
                                                                        style:
                                                                            detailBodyStyle,
                                                                      ),
                                                                      const SizedBox(
                                                                          height:
                                                                              4.0),
                                                                      Text(
                                                                        'Plus vous participez, plus vous augmentez vos chances lors du tirage au sort',
                                                                        style:
                                                                            detailBodyStyle,
                                                                      ),
                                                                      _buildYourTicketsRow(
                                                                          detailBodyStyle),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          const SizedBox(
                                                              height: 8.0),
                                                          if (hasSecondaryPrizeContent)
                                                            Row(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                const Icon(
                                                                  Icons
                                                                      .emoji_events_outlined,
                                                                  size: 16.0,
                                                                  color: Color(
                                                                      0xFF6B7280),
                                                                ),
                                                                const SizedBox(
                                                                    width: 8.0),
                                                                Expanded(
                                                                  child: Text(
                                                                    secondaryPrizeRulesText,
                                                                    style:
                                                                        detailBodyStyle,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ].divide(const SizedBox(
                                                      height: 10.0)),
                                                );
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
              if (_isLaunchingGame) _buildLaunchingOverlay(context),
            ],
          ),
        );
      },
    );
  }
}
