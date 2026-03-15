import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/components/custom_nav_bar_commercant2_widget.dart';
import '/components/list_empty_component_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'mes_enseignes_commercant_page_model.dart';
export 'mes_enseignes_commercant_page_model.dart';

class MesEnseignesCommercantPageWidget extends StatefulWidget {
  const MesEnseignesCommercantPageWidget({super.key});

  static String routeName = 'MesEnseignesCommercantPage';
  static String routePath = 'mesEnseignesCommercantPage';

  @override
  State<MesEnseignesCommercantPageWidget> createState() =>
      _MesEnseignesCommercantPageWidgetState();
}

class _MesEnseignesCommercantPageWidgetState
    extends State<MesEnseignesCommercantPageWidget> {
  late MesEnseignesCommercantPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => MesEnseignesCommercantPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'MesEnseignesCommercantPage'});
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EnseignesRecord>>(
      stream: queryEnseignesRecord(
        queryBuilder: (enseignesRecord) => enseignesRecord.where(
          'owner',
          isEqualTo: currentUserReference,
        ),
        limit: 15,
      ),
      builder: (context, snapshot) {
        // Customize what your widget looks like when it's loading.
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: SizedBox(
                width: 50.0,
                height: 50.0,
                child: SizedBox.shrink(),
              ),
            ),
          );
        }
        List<EnseignesRecord> mesEnseignesCommercantPageEnseignesRecordList =
            snapshot.data!;

        return GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            FocusManager.instance.primaryFocus?.unfocus();
          },
          child: Scaffold(
            key: scaffoldKey,
            appBar: AppBar(
              automaticallyImplyLeading: false,
              leading: FlutterFlowIconButton(
                borderColor: Colors.transparent,
                borderRadius: 30.0,
                borderWidth: 1.0,
                buttonSize: 60.0,
                icon: Icon(
                  Icons.chevron_left_rounded,
                  color: FlutterFlowTheme.of(context).primary,
                  size: 30.0,
                ),
                onPressed: () async {
                  context.pop();
                },
              ),
              title: Text(
                'Mon point de vente',
                style: FlutterFlowTheme.of(context).headlineMedium.override(
                      font: GoogleFonts.interTight(
                        fontWeight: FlutterFlowTheme.of(context)
                            .headlineMedium
                            .fontWeight,
                        fontStyle: FlutterFlowTheme.of(context)
                            .headlineMedium
                            .fontStyle,
                      ),
                      color: FlutterFlowTheme.of(context).primaryText,
                      fontSize: 22.0,
                      letterSpacing: 0.0,
                      fontWeight: FlutterFlowTheme.of(context)
                          .headlineMedium
                          .fontWeight,
                      fontStyle:
                          FlutterFlowTheme.of(context).headlineMedium.fontStyle,
                    ),
              ),
              actions: [
                Visibility(
                  visible:
                      mesEnseignesCommercantPageEnseignesRecordList.isEmpty,
                  child: FlutterFlowIconButton(
                    borderRadius: 8.0,
                    buttonSize: 40.0,
                    icon: Icon(
                      Icons.add,
                      color: FlutterFlowTheme.of(context).primary,
                      size: 22.0,
                    ),
                    onPressed: () async {
                      context.pushNamed(
                        AddEnseigneCommercantPageWidget.routeName,
                        extra: <String, dynamic>{
                          kTransitionInfoKey: const TransitionInfo(
                            hasTransition: true,
                            transitionType: PageTransitionType.rightToLeft,
                            duration: Duration(milliseconds: 1000),
                          ),
                        },
                      );
                    },
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: Image.asset(
                    'assets/images/Background.png',
                    fit: BoxFit.cover,
                    alignment: const Alignment(1.0, -1.0),
                  ),
                ),
              ),
              centerTitle: false,
            ),
            body: SafeArea(
              top: true,
              child: Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    fit: BoxFit.cover,
                    alignment: const AlignmentDirectional(-1.0, 1.0),
                    image: Image.asset(
                      'assets/images/Background.png',
                    ).image,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            20.0, 0.0, 20.0, 0.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Builder(
                              builder: (context) {
                                if (mesEnseignesCommercantPageEnseignesRecordList
                                    .isNotEmpty) {
                                  return Container(
                                    decoration: const BoxDecoration(),
                                    child: Builder(
                                      builder: (context) {
                                        final mesEnseignesCommercantPageVar =
                                            mesEnseignesCommercantPageEnseignesRecordList
                                                .toList();
                                        if (mesEnseignesCommercantPageVar
                                            .isEmpty) {
                                          return const Center(
                                            child: ListEmptyComponentWidget(
                                              title: 'Aucun points de vente ',
                                              description:
                                                  'Votre liste est actuellement vide',
                                            ),
                                          );
                                        }

                                        return ListView.separated(
                                          padding: EdgeInsets.zero,
                                          shrinkWrap: true,
                                          scrollDirection: Axis.vertical,
                                          itemCount:
                                              mesEnseignesCommercantPageVar
                                                  .length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(height: 10.0),
                                          itemBuilder: (context,
                                              mesEnseignesCommercantPageVarIndex) {
                                            final mesEnseignesCommercantPageVarItem =
                                                mesEnseignesCommercantPageVar[
                                                    mesEnseignesCommercantPageVarIndex];
                                            return InkWell(
                                              splashColor: Colors.transparent,
                                              focusColor: Colors.transparent,
                                              hoverColor: Colors.transparent,
                                              highlightColor:
                                                  Colors.transparent,
                                              onTap: () async {
                                                context.pushNamed(
                                                  UpdateEnseigneCommercantPageWidget
                                                      .routeName,
                                                  queryParameters: {
                                                    'enseigneDocument':
                                                        serializeParam(
                                                      mesEnseignesCommercantPageVarItem,
                                                      ParamType.Document,
                                                    ),
                                                  }.withoutNulls,
                                                  extra: <String, dynamic>{
                                                    'enseigneDocument':
                                                        mesEnseignesCommercantPageVarItem,
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
                                                          20.0),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      flex: 1,
                                                      child: Container(
                                                        height: 120.0,
                                                        decoration:
                                                            const BoxDecoration(),
                                                        child: FutureBuilder<
                                                            List<ImagesRecord>>(
                                                          future:
                                                              queryImagesRecordOnce(
                                                            parent:
                                                                mesEnseignesCommercantPageVarItem
                                                                    .reference,
                                                            singleRecord: true,
                                                          ),
                                                          builder: (context,
                                                              snapshot) {
                                                            // Customize what your widget looks like when it's loading.
                                                            if (!snapshot
                                                                .hasData) {
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
                                                                imageImagesRecordList =
                                                                snapshot.data!;
                                                            // Return an empty Container when the item does not exist.
                                                            if (snapshot.data!
                                                                .isEmpty) {
                                                              return Container();
                                                            }
                                                            final imageImagesRecord =
                                                                imageImagesRecordList
                                                                        .isNotEmpty
                                                                    ? imageImagesRecordList
                                                                        .first
                                                                    : null;

                                                            return ClipRRect(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8.0),
                                                              child:
                                                                  CachedNetworkImage(
                                                                fadeInDuration:
                                                                    const Duration(
                                                                        milliseconds:
                                                                            500),
                                                                fadeOutDuration:
                                                                    const Duration(
                                                                        milliseconds:
                                                                            500),
                                                                imageUrl:
                                                                    imageImagesRecord!
                                                                        .url,
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 2,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsetsDirectional
                                                                .fromSTEB(
                                                                    10.0,
                                                                    0.0,
                                                                    0.0,
                                                                    0.0),
                                                        child: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.max,
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .start,
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              mesEnseignesCommercantPageVarItem
                                                                  .name,
                                                              style: FlutterFlowTheme
                                                                      .of(context)
                                                                  .bodyLarge
                                                                  .override(
                                                                    font: GoogleFonts
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
                                                            Column(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .max,
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .spaceEvenly,
                                                              children: [
                                                                Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .max,
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .location_on,
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primaryText,
                                                                      size:
                                                                          18.0,
                                                                    ),
                                                                    Text(
                                                                      mesEnseignesCommercantPageVarItem
                                                                          .city,
                                                                      style: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodySmall
                                                                          .override(
                                                                            font:
                                                                                GoogleFonts.inter(
                                                                              fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                            ),
                                                                            letterSpacing:
                                                                                0.0,
                                                                            fontWeight:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                            fontStyle:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                          ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .max,
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .card_giftcard_rounded,
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primaryText,
                                                                      size:
                                                                          18.0,
                                                                    ),
                                                                    Text(
                                                                      ' Nombres de jeux : ',
                                                                      style: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodySmall
                                                                          .override(
                                                                            font:
                                                                                GoogleFonts.inter(
                                                                              fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                            ),
                                                                            letterSpacing:
                                                                                0.0,
                                                                            fontWeight:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                            fontStyle:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                          ),
                                                                    ),
                                                                    FutureBuilder<
                                                                        int>(
                                                                      future:
                                                                          queryEnseigneGameRecordCount(
                                                                        parent:
                                                                            mesEnseignesCommercantPageVarItem.reference,
                                                                      ),
                                                                      builder:
                                                                          (context,
                                                                              snapshot) {
                                                                        // Customize what your widget looks like when it's loading.
                                                                        if (!snapshot
                                                                            .hasData) {
                                                                          return const Center(
                                                                            child:
                                                                                SizedBox(
                                                                              width: 50.0,
                                                                              height: 50.0,
                                                                              child: SizedBox.shrink(),
                                                                            ),
                                                                          );
                                                                        }
                                                                        int textCount =
                                                                            snapshot.data!;

                                                                        return Text(
                                                                          valueOrDefault<
                                                                              String>(
                                                                            textCount.toString(),
                                                                            '0',
                                                                          ),
                                                                          style: FlutterFlowTheme.of(context)
                                                                              .bodySmall
                                                                              .override(
                                                                                font: GoogleFonts.inter(
                                                                                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                ),
                                                                                letterSpacing: 0.0,
                                                                                fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                              ),
                                                                        );
                                                                      },
                                                                    ),
                                                                  ],
                                                                ),
                                                              ].divide(const SizedBox(
                                                                  height: 5.0)),
                                                            ),
                                                          ]
                                                              .divide(const SizedBox(
                                                                  height: 10.0))
                                                              .addToStart(
                                                                  const SizedBox(
                                                                      height:
                                                                          10.0)),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  );
                                } else {
                                  return SizedBox(
                                    height: 200.0,
                                    child: wrapWithModel(
                                      model: _model.listEmptyComponentModel,
                                      updateCallback: () => safeSetState(() {}),
                                      child: const ListEmptyComponentWidget(
                                        title: 'Liste vide',
                                        description: 'Pas de point de vente',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ].divide(const SizedBox(height: 20.0)),
                        ),
                      ),
                    ),
                    wrapWithModel(
                      model: _model.customNavBarCommercant2Model,
                      updateCallback: () => safeSetState(() {}),
                      child: const CustomNavBarCommercant2Widget(),
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

