import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/custom_cloud_functions/custom_cloud_function_response_manager.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/utils/create_account_to_play_dialog.dart';
import '/utils/share_links.dart';
import '/widgets/proxiplay_network_image.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/index.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webviewx_plus/webviewx_plus.dart';
import 'jeu_detail_joueur_page_model.dart';
export 'jeu_detail_joueur_page_model.dart';

/// remplir le container sous l'image par une liste de text
class JeuDetailJoueurPageWidget extends StatefulWidget {
  const JeuDetailJoueurPageWidget({
    super.key,
    required this.gameDoc,
    this.enseigneDoc,
  });

  final GamesRecord? gameDoc;
  final EnseignesRecord? enseigneDoc;

  static String routeName = 'JeuDetailJoueurPage';
  static String routePath = 'jeuDetailJoueurPage';

  @override
  State<JeuDetailJoueurPageWidget> createState() =>
      _JeuDetailJoueurPageWidgetState();
}

class _JeuDetailJoueurPageWidgetState extends State<JeuDetailJoueurPageWidget> {
  late JeuDetailJoueurPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

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
    return valueOrDefault(user?.remainingPart, 0) <= 0 &&
        !_hasUnlimitedAccess(user, now);
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => JeuDetailJoueurPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'JeuDetailJoueurPage'});
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ParticipantsDetailsRecord>>(
      future: (widget.gameDoc?.reference == null || currentUserReference == null)
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
        // Customize what your widget looks like when it's loading.
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
        final endWindowEnd = endDate?.add(const Duration(hours: 48));
        final isWithinEndWindow = endDate != null &&
            getCurrentTimestamp.isAfter(endDate) &&
            (endWindowEnd != null &&
                getCurrentTimestamp.isBefore(endWindowEnd));
        final hasWinnerAnnouncement = isWithinEndWindow &&
            (widget.gameDoc?.hasWinner ?? false) &&
            (widget.gameDoc?.mainPrizeWinner != null);
        final hasMainPrizeFlag = widget.gameDoc?.hasMainPrize == true;
        final prizeValue = widget.gameDoc?.prizeValue ?? 0;
        final mainPrizeTitle = (widget.gameDoc?.name ?? '').trim();
        // Regle produit :
        // Le lot principal doit etre monetaire.
        // On affiche uniquement si hasMainPrize == true ET prizeValue > 0
        final shouldShowMainPrize =
            hasMainPrizeFlag && prizeValue > 0 && mainPrizeTitle.isNotEmpty;
        final secondaryPrizes = widget.gameDoc?.secondaryPrizes ?? const [];
        final validSecondaryPrizes = secondaryPrizes.where((item) {
          final name = (item['name'] ?? '').toString().trim();
          final countValue = item['count'];
          final parsedCount = countValue is num
              ? countValue.toInt()
              : int.tryParse((countValue ?? '').toString()) ?? 0;
          return name.isNotEmpty && parsedCount > 0;
        }).toList();
        final secondaryPrizeCount =
            validSecondaryPrizes.fold<int>(0, (total, item) {
          final countValue = item['count'];
          final parsedCount = countValue is num
              ? countValue.toInt()
              : int.tryParse((countValue ?? '').toString()) ?? 0;
          return total + parsedCount;
        });
        final hasSecondaryPrizeContent = validSecondaryPrizes.isNotEmpty;
        final secondaryPrizeRulesText = secondaryPrizeCount > 0
            ? shouldShowMainPrize
                ? '$secondaryPrizeCount ${secondaryPrizeCount > 1 ? 'gagnants' : 'gagnant'} ${secondaryPrizeCount > 1 ? 'sont' : 'est'} à gagner instantanément'
                : '$secondaryPrizeCount lot${secondaryPrizeCount > 1 ? 's' : ''} ${secondaryPrizeCount > 1 ? 'sont' : 'est'} à gagner instantanément'
            : shouldShowMainPrize
                ? 'Des gagnants sont à gagner instantanément'
                : 'Des lots sont à gagner instantanément';
        String getLotsTitle(int totalLots) =>
            totalLots == 1 ? 'Présentation du lot' : 'Présentation des lots';
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
        Widget buildMainPrizeWidget(String title) {
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
                      title,
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
                  color: const Color(0xFFFFF4E6),
                  borderRadius: BorderRadius.circular(20.0),
                ),
                child: Text(
                  'Tirage au sort',
                  style: GoogleFonts.inter(
                    fontSize: 11.0,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFF9500),
                  ),
                ),
              ),
            ],
          );
        }
        Widget buildSecondaryPrizeWidget(
          Map<String, dynamic> prize, {
          required bool showBadge,
        }) {
          final name = (prize['name'] ?? '').toString().trim();
          final countValue = prize['count'];
          final count = countValue is num
              ? countValue.toInt()
              : int.tryParse((countValue ?? '').toString()) ?? 0;
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
                            '$count ${count > 1 ? 'gagnants' : 'gagnant'}',
                            style: detailItemTitleStyle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      name,
                      style: detailBodyStyle,
                    ),
                  ],
                ),
              ),
              if (showBadge)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10.0,
                    vertical: 4.0,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAFBF2),
                    borderRadius: BorderRadius.circular(20.0),
                  ),
                  child: Text(
                    'Gains immédiats',
                    style: GoogleFonts.inter(
                      fontSize: 11.0,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ),
            ],
          );
        }
        final totalLots = (shouldShowMainPrize ? 1 : 0) + secondaryPrizeCount;
        final leftActionVisible = (() {
          final isGuest = currentUserUid == '';
          if (isGuest) return true;
          final endDate = widget.gameDoc?.endDate;
          final isGameOpen = endDate != null
              ? endDate.isAfter(getCurrentTimestamp)
              : true;
          final isMinorBlocked =
              (widget.gameDoc?.prohibitedForMinors ?? false) &&
                  (currentUserDocument?.birthday == null ||
                      !functions.isAdult(currentUserDocument!.birthday!));
          return isGameOpen || isMinorBlocked;
        })();
        return GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            FocusManager.instance.primaryFocus?.unfocus();
          },
          child: Scaffold(
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
                    constraints:
                        const BoxConstraints.tightFor(width: 48.0, height: 48.0),
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: FlutterFlowTheme.of(context).primaryText,
                      size: 18.0,
                    ),
                    onPressed: () async {
                      context.pop();
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
                          List<FavoriteGamesRecord> favoriteGamesList = snapshot.data!;
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
                                constraints:
                                    const BoxConstraints.tightFor(width: 48.0, height: 48.0),
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
                                                      await FavoriteGamesRecord
                                        .createDoc(currentUserReference!)
                                                          .set({
                                                        ...createFavoriteGamesRecordData(
                                        gameId: widget.gameDoc?.reference,
                                      ),
                                      ...mapToFirestore({
                                        'added_at': FieldValue.serverTimestamp(),
                                      }),
                                    });

                                    await widget.gameDoc!.reference.update({
                                      ...mapToFirestore({
                                        'favorites': FieldValue.increment(1),
                                      }),
                                    });
                                    safeSetState(() => _model.firestoreRequestCompleter = null);
                                    await _model.waitForFirestoreRequestCompleted();
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
                  child: IconButton(
                                      padding: EdgeInsets.zero,
                                      style: IconButton.styleFrom(
                                        backgroundColor:
                                            FlutterFlowTheme.of(context).primary,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(48.0, 48.0),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12.0),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.share_rounded,
                                        size: 22.0,
                                      ),
                                      onPressed: () async {
                                        await Share.share(
                                          buildAppShareText(
                                            title:
                                                '${widget.gameDoc?.name ?? 'ce jeu'} sur ProxiPlay',
                                            description: widget.enseigneDoc?.name
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
            body: SafeArea(
              top: true,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      FlutterFlowTheme.of(context).primaryBackground,
                      FlutterFlowTheme.of(context).primaryBackground.withOpacity(0.95),
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
                            // Hero Image Section
                            ProxiplayNetworkImage(
                              imageUrl: widget.gameDoc!.photo,
                              width: double.infinity,
                              height: 320.0,
                              fit: BoxFit.cover,
                            ),
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
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    24.0,
                                    32.0,
                                    24.0,
                                    24.0,
                                  ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.max,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Game Title
                                    Text(
                                      widget.gameDoc!.name, 
                                      style: GoogleFonts.inter(
                                        fontSize:  widget.gameDoc!.name.isEmpty ? 0.0 : 28.0,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF1A1A1A),
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 24.0),
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
                                                    builder: (context) {
                                                      if (isGuestOrAnonymous ||
                                                          ((currentUserDocument
                                                                      ?.birthday !=
                                                                  null) &&
                                                              functions.isAdult(
                                                                  currentUserDocument!
                                                                      .birthday!))) {
                                                        return Visibility(
                                                          visible: widget
                                                                  .gameDoc!
                                                                  .endDate! >
                                                              getCurrentTimestamp,
                                                          child: FFButtonWidget(
                                                            onPressed: ((widget
                                                                            .gameDoc!
                                                                            .endDate! <
                                                                        getCurrentTimestamp) ||
                                                                    hasPlayedToday ||
                                                                    noRemainingParts)
                                                                ? null
                                                                : () async {
                                                                    if (isGuestOrAnonymous) {
                                                                      await showCreateAccountToPlayDialog(
                                                                          context);
                                                                      return;
                                                                    }
                                                                    try {
                                                                      final result = await FirebaseFunctions
                                                                          .instance
                                                                          .httpsCallable(
                                                                              'participateInGameTransaction')
                                                                          .call({
                                                                        "gameRef": widget
                                                                            .gameDoc!
                                                                            .reference
                                                                            .id,
                                                                      });
                                                                      _model.cloudFunction3sn =
                                                                          ParticipateInGameTransactionCloudFunctionCallResponse(
                                                                        data: ResultParticipationGameStruct.fromMap(
                                                                            result.data),
                                                                        succeeded:
                                                                            true,
                                                                        resultAsString: result
                                                                            .data
                                                                            .toString(),
                                                                        jsonBody:
                                                                            result.data,
                                                                      );
                                                                    } on FirebaseFunctionsException catch (error) {
                                                                      _model.cloudFunction3sn =
                                                                          ParticipateInGameTransactionCloudFunctionCallResponse(
                                                                        data: createResultParticipationGameStruct(
                                                                          message: error.message ??
                                                                              "Erreur (${error.code})",
                                                                        ),
                                                                        errorCode:
                                                                            error.code,
                                                                        succeeded:
                                                                            false,
                                                                      );
                                                                    }

                                                                    if (!context.mounted) {
                                                                      return;
                                                                    }
                                                                    if (_model
                                                                        .cloudFunction3sn!
                                                                        .succeeded!) {
                                                                      await refreshCurrentUserDocument();
                                                                      if (!context.mounted) {
                                                                        return;
                                                                      }
                                                                      safeSetState(() {});
                                                                      context
                                                                          .pushNamed(
                                                                        PlayJoueurPageWidget
                                                                            .routeName,
                                                                        queryParameters:
                                                                            {
                                                                          'game':
                                                                              serializeParam(
                                                                            widget.gameDoc,
                                                                            ParamType.Document,
                                                                          ),
                                                                          'resultParticipation':
                                                                              serializeParam(
                                                                            ResultParticipationGameStruct.maybeFromMap(_model.cloudFunction3sn?.jsonBody),
                                                                            ParamType.DataStruct,
                                                                          ),
                                                                        }.withoutNulls,
                                                                        extra: <String,
                                                                            dynamic>{
                                                                          'game':
                                                                              widget.gameDoc,
                                                                        },
                                                                      );
                                                                    } else {
                                                                      await showDialog(
                                                                        context:
                                                                            context,
                                                                        builder:
                                                                            (alertDialogContext) {
                                                                          return WebViewAware(
                                                                            child:
                                                                                AlertDialog(
                                                                              title: Text(
                                                                                _model.cloudFunction3sn?.data?.message.isNotEmpty == true
                                                                                    ? _model.cloudFunction3sn!.data!.message
                                                                                    : "Une erreur est survenue (${_model.cloudFunction3sn?.errorCode ?? 'inconnue'}).",
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

                                                                    safeSetState(
                                                                        () {});
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
                                                              } else {
                                                                return 'Jouer';
                                                              }
                                                            }(),
                                                            options:
                                                                FFButtonOptions(
                                                              width: double
                                                                  .infinity,
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
                                                                              fontWeight: FontWeight.w600,
                                                                            ),
                                                                            color: Colors.white,
                                                                        letterSpacing:
                                                                            0.0,
                                                                      ),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                              16.0),
                                                                  elevation: 4.0,
                                                            ),
                                                          ),
                                                        );
                                                      } else {
                                                            return Container(
                                                              height: 56.0,
                                                              decoration: BoxDecoration(
                                                                color: FlutterFlowTheme.of(context).primary,
                                                                borderRadius: BorderRadius.circular(16.0),
                                                              ),
                                                              child: Center(
                                                                child: Text(
                                                          'Interdit au mineur',
                                                                  style: GoogleFonts.inter(
                                                                    fontWeight: FontWeight.w600,
                                                                    color: Colors.white,
                                                                  ),
                                                                ),
                                                              ),
                                                        );
                                                      }
                                                    },
                                                  );
                                                } else {
                                                  return Visibility(
                                                    visible: widget
                                                            .gameDoc!.endDate! >
                                                        getCurrentTimestamp,
                                                    child: AuthUserStreamWidget(
                                                      builder: (context) {
                                                        final noRemainingPartsLive =
                                                            _hasNoRemainingParts(
                                                          currentUserDocument,
                                                          getCurrentTimestamp,
                                                        );
                                                        return FFButtonWidget(
                                                          onPressed: ((widget
                                                                        .gameDoc!
                                                                        .endDate! <
                                                                    getCurrentTimestamp) ||
                                                                hasPlayedToday ||
                                                                noRemainingPartsLive)
                                                            ? null
                                                            : () async {
                                                                if (isGuestOrAnonymous) {
                                                                  await showCreateAccountToPlayDialog(
                                                                      context);
                                                                  return;
                                                                }
                                                                try {
                                                                  final result = await FirebaseFunctions
                                                                      .instance
                                                                      .httpsCallable(
                                                                          'participateInGameTransaction')
                                                                      .call({
                                                                    "gameRef": widget
                                                                        .gameDoc!
                                                                        .reference
                                                                        .id,
                                                                  });
                                                                  _model.cloudFunction3sn2 =
                                                                      ParticipateInGameTransactionCloudFunctionCallResponse(
                                                                    data: ResultParticipationGameStruct
                                                                        .fromMap(
                                                                            result.data),
                                                                    succeeded:
                                                                        true,
                                                                    resultAsString:
                                                                        result
                                                                            .data
                                                                            .toString(),
                                                                    jsonBody:
                                                                        result
                                                                            .data,
                                                                  );
                                                                } on FirebaseFunctionsException catch (error) {
                                                                  _model.cloudFunction3sn2 =
                                                                      ParticipateInGameTransactionCloudFunctionCallResponse(
                                                                    data: createResultParticipationGameStruct(
                                                                      message: error.message ??
                                                                          "Erreur (${error.code})",
                                                                    ),
                                                                    errorCode:
                                                                        error
                                                                            .code,
                                                                    succeeded:
                                                                        false,
                                                                  );
                                                                }

                                                                if (!context.mounted) {
                                                                  return;
                                                                }
                                                                if (_model
                                                                    .cloudFunction3sn2!
                                                                    .succeeded!) {
                                                                  await refreshCurrentUserDocument();
                                                                  if (!context.mounted) {
                                                                    return;
                                                                  }
                                                                  safeSetState(() {});
                                                                  context
                                                                      .pushNamed(
                                                                    PlayJoueurPageWidget
                                                                        .routeName,
                                                                    queryParameters:
                                                                        {
                                                                      'game':
                                                                          serializeParam(
                                                                        widget
                                                                            .gameDoc,
                                                                        ParamType
                                                                            .Document,
                                                                      ),
                                                                      'resultParticipation':
                                                                          serializeParam(
                                                                        ResultParticipationGameStruct.maybeFromMap(_model
                                                                            .cloudFunction3sn2
                                                                            ?.jsonBody),
                                                                        ParamType
                                                                            .DataStruct,
                                                                      ),
                                                                    }.withoutNulls,
                                                                    extra: <String,
                                                                        dynamic>{
                                                                      'game': widget
                                                                          .gameDoc,
                                                                    },
                                                                  );
                                                                } else {
                                                                  await showDialog(
                                                                    context:
                                                                        context,
                                                                    builder:
                                                                        (alertDialogContext) {
                                                                      return WebViewAware(
                                                                            child:
                                                                                AlertDialog(
                                                                              title: Text(
                                                                                _model.cloudFunction3sn2?.data?.message.isNotEmpty == true
                                                                                    ? _model.cloudFunction3sn2!.data!.message
                                                                                    : "Une erreur est survenue (${_model.cloudFunction3sn2?.errorCode ?? 'inconnue'}).",
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

                                                                safeSetState(
                                                                    () {});
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
                                                            } else {
                                                              return 'Jouer';
                                                            }
                                                          }(),
                                                          options:
                                                              FFButtonOptions(
                                                            width:
                                                                double.infinity,
                                                            height: 56.0,
                                                            padding:
                                                                const EdgeInsets.all(
                                                                    0.0),
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
                                                                            fontWeight: FontWeight.w600,
                                                                          ),
                                                                      color: Colors.white,
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
                                                      },
                                                    ),
                                                  );
                                                }
                                              },
                                            );
                                          } else {
                                            return FFButtonWidget(
                                              onPressed: () async {
                                                await showCreateAccountToPlayDialog(
                                                    context);
                                              },
                                              text: 'Jouer',
                                              options: FFButtonOptions(
                                                width: double.infinity,
                                                    height: 56.0,
                                                padding: const EdgeInsets.all(0.0),
                                                iconPadding:
                                                    const EdgeInsetsDirectional
                                                        .fromSTEB(
                                                            0.0, 0.0, 0.0, 0.0),
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primary,
                                                textStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .titleMedium
                                                        .override(
                                                          font: GoogleFonts
                                                                  .inter(
                                                                fontWeight: FontWeight.w600,
                                                              ),
                                                              color: Colors.white,
                                                          letterSpacing: 0.0,
                                                        ),
                                                borderRadius:
                                                        BorderRadius.circular(16.0),
                                                    elevation: 4.0,
                                              ),
                                            );
                                          }
                                        },
                                      // ),
                                    ),
                                        // if (leftActionVisible)

                                          const SizedBox(height: 12.0),
                                        SizedBox(
                                          // width: 220.0,
                                          child: InkWell(
                                      splashColor: Colors.transparent,
                                      focusColor: Colors.transparent,
                                      hoverColor: Colors.transparent,
                                      highlightColor: Colors.transparent,
                                      onTap: () async {
                                        context.pushNamed(
                                          EnseigneDetailJoueurPageWidget
                                              .routeName,
                                          queryParameters: {
                                            'enseigneDoc': serializeParam(
                                              widget.enseigneDoc,
                                              ParamType.Document,
                                            ),
                                          }.withoutNulls,
                                          extra: <String, dynamic>{
                                            'enseigneDoc': widget.enseigneDoc,
                                          },
                                        );
                                      },
                                      child: Container(
                                                constraints: const BoxConstraints(minHeight: 56.0),
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 12.0,
                                                  vertical: 8.0,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(16.0),
                                                  border: Border.all(
                                                    color: const Color(0xFFA0134D),
                                                    width: 2.0,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.05),
                                                      blurRadius: 10.0,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.store_rounded,
                                                      color: const Color(0xFFA0134D),
                                                      size: 20.0,
                                                    ),
                                                    const SizedBox(width: 8.0),
                                                    Flexible(
                                                      child: Text(
                                                        //  here name of the store
                                                        widget.enseigneDoc?.name ??
                                                            'Enseigne partenaire',
                                                        maxLines: 2,
                                                        softWrap: true,
                                                        overflow: TextOverflow.ellipsis,
                                                        textAlign: TextAlign.center,
                                                        style: GoogleFonts.inter(
                                                          fontSize: 16.0,
                                                          fontWeight: FontWeight.w600,
                                                          color: const Color(0xFFA0134D),
                                                          letterSpacing: 0.0,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24.0),
                                    // Winner Announcement Section
                                    if (hasWinnerAnnouncement)
                                      Container(
                                        width: double.infinity,
                                        margin: const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 24.0),
                                        padding: const EdgeInsets.all(20.0),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              FlutterFlowTheme.of(context).primary.withOpacity(0.1),
                                              FlutterFlowTheme.of(context).primary.withOpacity(0.05),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(16.0),
                                          border: Border.all(
                                            color: FlutterFlowTheme.of(context).primary.withOpacity(0.3),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Padding(
                                          padding:
                                              const EdgeInsetsDirectional.fromSTEB(
                                                  16.0, 16.0, 16.0, 16.0),
                                          child: FutureBuilder<UsersRecord>(
                                            future: UsersRecord.getDocumentOnce(
                                                widget
                                                    .gameDoc!.mainPrizeWinner!),
                                            builder: (context, snapshot) {
                                              final winnerName =
                                                  snapshot.hasData
                                                      ? snapshot.data!.firstName
                                                      : '';
                                              return Column(
                                            mainAxisSize: MainAxisSize.max,
                                            children: [
                                              if (winnerName.isNotEmpty)
                                                    // Text(
                                                    //   'FÃ©licitations Ã  $winnerName de ${snapshot.data!.city} !',
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
                                                  Text(textAlign: TextAlign.center,
                                                    'F\u00E9licitations \u00E0 $winnerName de ${snapshot.data!.city} !',
                                                  style: FlutterFlowTheme.of(
                                                          context)
                                                        .titleMedium
                                                      .override(
                                                        font: GoogleFonts
                                                            .interTight(
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                    .titleMedium
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                    .titleMedium
                                                                  .fontStyle,
                                                        ),
                                                        letterSpacing: 0.0,
                                                        fontWeight:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                  .titleMedium
                                                                .fontWeight,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                  .titleMedium
                                                                .fontStyle,
                                                      ),
                                                ),
                                                  
                                              Text(
                                                    'Le jeu est termin\u00E9. Revenez bient\u00F4t pour d\u00E9couvrir les prochains jeux !',
                                                    textAlign: TextAlign.center,
                                                    style: FlutterFlowTheme.of(
                                                            context)
                                                        .bodySmall
                                                        .override(
                                                          font:
                                                              GoogleFonts.inter(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodySmall
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodySmall
                                                                    .fontStyle,
                                                          ),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .secondaryText,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodySmall
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodySmall
                                                                  .fontStyle,
                                                        ),
                                              ),
                                            ].divide(const SizedBox(height: 8.0)),
                                              );
                                            },
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
                                        if (widget.enseigneDoc != null) {
                                          return Column(
                                            mainAxisSize: MainAxisSize.max,
                                            children: [
                                              // Website Link Card
                                              if (!functions
                                                  .checkValueIsEmpty(
                                                      widget
                                                          .enseigneDoc!
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
                                                future: queryHorairesRecordOnce(
                                                  parent: widget
                                                      .enseigneDoc?.reference,
                                                  queryBuilder:
                                                      (horairesRecord) =>
                                                          horairesRecord.orderBy(
                                                              'created_time'),
                                                ),
                                                builder: (context, snapshot) {
                                                  // Customize what your widget looks like when it's loading.
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
return Container(
                                                    decoration: const BoxDecoration(),
                                                  );
                                                },
                                              ),
                                              FutureBuilder<
                                                  List<HorairesRecord>>(
                                                future: queryHorairesRecordOnce(
                                                  parent: widget
                                                      .enseigneDoc?.reference,
                                                  queryBuilder:
                                                      (horairesRecord) =>
                                                          horairesRecord.orderBy(
                                                              'created_time'),
                                                ),
                                                builder: (context, snapshot) {
                                                  // Customize what your widget looks like when it's loading.
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
                                                  //             'Horaires d\'ouverture',
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
                                                  //                                                 '${dateTimeFormat(
                                                  //                                                   "Hm",
                                                  //                                                   addHoraireCommercantPageVarItem.openingDay,
                                                  //                                                   locale: FFLocalizations.of(context).languageCode,
                                                  //                                                 )} - ${dateTimeFormat(
                                                  //                                                   "Hm",
                                                  //                                                   addHoraireCommercantPageVarItem.closingDay,
                                                  //                                                   locale: FFLocalizations.of(context).languageCode,
                                                  //                                                 )}',
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
                                                  //                                                     '${dateTimeFormat(
                                                  //                                                       "Hm",
                                                  //                                                       addHoraireCommercantPageVarItem.openingMorning,
                                                  //                                                       locale: FFLocalizations.of(context).languageCode,
                                                  //                                                     )} - ${dateTimeFormat(
                                                  //                                                       "Hm",
                                                  //                                                       addHoraireCommercantPageVarItem.closingMorning,
                                                  //                                                       locale: FFLocalizations.of(context).languageCode,
                                                  //                                                     )}',
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
                                                  //                                                     '${dateTimeFormat(
                                                  //                                                       "Hm",
                                                  //                                                       addHoraireCommercantPageVarItem.openingAfternoon,
                                                  //                                                       locale: FFLocalizations.of(context).languageCode,
                                                  //                                                     )} - ${dateTimeFormat(
                                                  //                                                       "Hm",
                                                  //                                                       addHoraireCommercantPageVarItem.closingAfternoon,
                                                  //                                                       locale: FFLocalizations.of(context).languageCode,
                                                  //                                                     )}',
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
                                                  //                                           'FermÃ©',
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
  if (shouldShowMainPrize || hasSecondaryPrizeContent)
                                      Container(
                                        width: double.infinity,
                                        margin:
                                            const EdgeInsets.only(bottom: 16.0),
                                        padding: const EdgeInsets.all(16.0),
                                        decoration: detailCardDecoration,
                                                            child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                                              children: [
                                            Text(
                                              getLotsTitle(totalLots),
                                              style: detailSectionTitleStyle,
                                            ),
                                            const SizedBox(height: 12.0),
                                            if (shouldShowMainPrize)
                                              buildMainPrizeWidget(mainPrizeTitle),
                                            if (hasSecondaryPrizeContent)
                                              const SizedBox(height: 10.0),
                                            if (hasSecondaryPrizeContent)
                                              ...List.generate(
                                                validSecondaryPrizes.length,
                                                (index) => Padding(
                                                  padding: EdgeInsets.only(
                                                    bottom: index ==
                                                            validSecondaryPrizes
                                                                    .length -
                                                                1
                                                        ? 0.0
                                                        : 10.0,
                                                  ),
                                                  child: buildSecondaryPrizeWidget(
                                                    validSecondaryPrizes[index],
                                                    showBadge: index == 0,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                              
                                              Container(
                                                width: double.infinity,
                                                margin:
                                                    const EdgeInsets.only(bottom: 16.0),
                                                padding: const EdgeInsets.all(16.0),
                                                decoration: detailCardDecoration,

                                                
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                                                                      children: [
                                                    
                                                                                                        Text(
                                                      'R\u00E8gles du jeu',
                                                      style:
                                                          detailSectionTitleStyle,
                                                    ),
                                                    const SizedBox(height: 12.0),
                                                    Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        const Icon(
                                                          Icons
                                                              .access_time_rounded,
                                                          size: 16.0,
                                                          color: Color(0xFF6B7280),
                                                        ),
                                                        const SizedBox(width: 8.0),
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
                                                    const SizedBox(height: 8.0),
                                                    Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        const Icon(
                                                          Icons
                                                              .pan_tool_alt_rounded,
                                                          size: 16.0,
                                                          color: Color(0xFF6B7280),
                                                        ),
                                                        const SizedBox(width: 8.0),
                                                        Expanded(
                                                          child: Text(
                                                            'Grattez la zone ci-dessus pour d\u00E9couvrir si vous avez gagn\u00E9',
                                                            style:
                                                                detailBodyStyle,
                                                          ),
                                                                                    ),
                                                                                  ],
                                                                                ),
                                                    const SizedBox(height: 8.0),
                                               if (shouldShowMainPrize)       Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                       const Icon(
                                                          Icons
                                                              .card_giftcard_rounded,
                                                          size: 16.0,
                                                          color: Color(0xFF6B7280),
                                                        ),
                                                        const SizedBox(width: 8.0),
                                                      
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
                                                                  height: 4.0),
                                                              Text(
                                                                'Plus vous participez, plus vous augmentez vos chances lors du tirage au sort',
                                                                style:
                                                                    detailBodyStyle,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8.0),
                                                 
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
                                                          color: Color(0xFF6B7280),
                                                        ),
                                                        const SizedBox(width: 8.0),
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
                                            ].divide(const SizedBox(height: 10.0)),
                                          );
                                        } else {
                                          return Container(
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .secondaryBackground,
                                              borderRadius:
                                                  BorderRadius.circular(20.0),
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(10.0),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.max,
                                                children: [
                                                  Text(
                                                    'Cette enseigne n\'existe plus.',
                                                    style: FlutterFlowTheme.of(
                                                            context)
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
                                                    const SizedBox(height: 10.0)),
                                              ),
                                            ),
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
        );
      },
    );
  }
}





