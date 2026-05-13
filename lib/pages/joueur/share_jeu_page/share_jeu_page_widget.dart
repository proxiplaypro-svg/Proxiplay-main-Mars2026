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

    debugPrint(
      '[GAME_VIEW_PROD_CHECK] build_marker screen=ShareJeuPage marker=fiche_jeu_v2 gameId=${widget.gameDoc?.reference.id ?? 'unknown'} source=${widget.source ?? 'unknown'}',
    );

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
                                        fillColor: FlutterFlowTheme.of(context)
                                            .primary,
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
                                                if (isGuestOrAnonymous ||
                                                    ((currentUserDocument
                                                                ?.birthday !=
                                                            null) &&
                                                        functions.isAdult(
                                                            currentUserDocument!
                                                                .birthday!))) {
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
                                                                        getCurrentTimestamp)))
                                                            ? null
                                                            : () async {
                                                                if (isGuestOrAnonymous) {
                                                                  await showCreateAccountToPlayDialog(
                                                                      context);
                                                                  return;
                                                                }
                                                                debugPrint(
                                                                  '[GAME_FLOW_DEBUG] participate_start screen=ShareJeuPage gameId=${widget.gameDoc?.reference.id ?? 'unknown'} source=${widget.source ?? 'unknown'}',
                                                                );
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
                                                                  _model.cloudFunction3sn =
                                                                      ParticipateInGameTransactionCloudFunctionCallResponse(
                                                                    data:
                                                                        createResultParticipationGameStruct(
                                                                      message: error
                                                                              .message ??
                                                                          "Erreur (${error.code})",
                                                                    ),
                                                                    errorCode:
                                                                        error
                                                                            .code,
                                                                    succeeded:
                                                                        false,
                                                                  );
                                                                }

                                                                if (!context
                                                                    .mounted) {
                                                                  return;
                                                                }
                                                                if (_model
                                                                    .cloudFunction3sn!
                                                                    .succeeded!) {
                                                                  final newlyQualified =
                                                                      widget.gameDoc !=
                                                                              null &&
                                                                          currentUserUid
                                                                              .isNotEmpty
                                                                      ? await updateAnimationProgress(
                                                                          currentUserUid,
                                                                          widget.gameDoc!,
                                                                        )
                                                                      : false;
                                                                  if (!context
                                                                      .mounted) {
                                                                    return;
                                                                  }
                                                                  await refreshCurrentUserDocument();
                                                                  if (context
                                                                      .mounted) {
                                                                    safeSetState(
                                                                        () {});
                                                                  }
                                                                  if (newlyQualified) {
                                                                    await showDialog(
                                                                      context:
                                                                          context,
                                                                      builder:
                                                                          (dialogContext) {
                                                                        return WebViewAware(
                                                                          child:
                                                                              AlertDialog(
                                                                            title:
                                                                                const Text(
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
                                                                    if (!context
                                                                        .mounted) {
                                                                      return;
                                                                    }
                                                                  }
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
                                                                            .cloudFunction3sn
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
                                                                          title:
                                                                              Text(
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
