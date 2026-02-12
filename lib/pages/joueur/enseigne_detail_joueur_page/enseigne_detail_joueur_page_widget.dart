import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/components/list_empty_component_widget.dart';
import '/flutter_flow/flutter_flow_expanded_image_view.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/flutter_flow/custom_functions.dart' as functions;
import '/index.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:page_transition/page_transition.dart';
import 'package:provider/provider.dart';
import 'enseigne_detail_joueur_page_model.dart';
export 'enseigne_detail_joueur_page_model.dart';

/// remplir le container sous l'image par une liste de text
class EnseigneDetailJoueurPageWidget extends StatefulWidget {
  const EnseigneDetailJoueurPageWidget({
    super.key,
    required this.enseigneDoc,
  });

  final EnseignesRecord? enseigneDoc;

  static String routeName = 'EnseigneDetailJoueurPage';
  static String routePath = 'enseigneDetailJoueurPage';

  @override
  State<EnseigneDetailJoueurPageWidget> createState() =>
      _EnseigneDetailJoueurPageWidgetState();
}

class _EnseigneDetailJoueurPageWidgetState
    extends State<EnseigneDetailJoueurPageWidget> {
  late EnseigneDetailJoueurPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => EnseigneDetailJoueurPageModel());

    // Initialize scroll controller for image carousel
    _model.imagesScrollController = ScrollController();
    _model.imagesScrollController?.addListener(() {
      if (_model.imagesScrollController!.hasClients) {
        final scrollPosition = _model.imagesScrollController!.offset;
        final screenWidth = MediaQuery.of(context).size.width;
        final imageWidth = (screenWidth - 40.0 - 32.0) + 10.0; // (screen width - outer padding - card padding) + spacing
        final currentIndex = (scrollPosition / imageWidth).round();
        final clampedIndex = currentIndex.clamp(0, 1000);
        if (clampedIndex != _model.currentImageIndex) {
          safeSetState(() {
            _model.currentImageIndex = clampedIndex;
          });
        }
      }
    });

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'EnseigneDetailJoueurPage'});
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
      child: PopScope(
        canPop: false,
        child: Scaffold(
          key: scaffoldKey,
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(100.0),
            child: AppBar(
              backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
              automaticallyImplyLeading: false,
              actions: [],
              flexibleSpace: FlexibleSpaceBar(
                title: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 14.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding:
                            EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 12.0, 8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Padding(
                              padding: EdgeInsetsDirectional.fromSTEB(
                                  12.0, 0.0, 0.0, 0.0),
                              child: Container(
                                width: 44.0,
                                height: 44.0,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.08),
                                      blurRadius: 10.0,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: FlutterFlowIconButton(
                                  borderColor: Colors.transparent,
                                  borderRadius: 30.0,
                                  borderWidth: 1.0,
                                  buttonSize: 44.0,
                                  icon: Icon(
                                    Icons.chevron_left_rounded,
                                    color:
                                        FlutterFlowTheme.of(context).primaryText,
                                    size: 28.0,
                                  ),
                                  onPressed: () async {
                                    context.pop();
                                  },
                                ),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Image.asset(
                                  'assets/images/logo_D_secondaire.png',
                                  height: 34.0,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            Builder(
                              builder: (context) {
                                if (currentUserUid != null &&
                                    currentUserUid != '') {
                                  return StreamBuilder<
                                      List<FavoriteEnseignesRecord>>(
                                    stream: queryFavoriteEnseignesRecord(
                                      parent: currentUserReference,
                                      queryBuilder: (favoriteEnseignesRecord) =>
                                          favoriteEnseignesRecord.where(
                                        'enseigne_id',
                                        isEqualTo:
                                            widget!.enseigneDoc?.reference,
                                      ),
                                      singleRecord: true,
                                    ),
                                    builder: (context, snapshot) {
                                      // Customize what your widget looks like when it's loading.
                                      if (!snapshot.hasData) {
                                        return Center(
                                          child: SizedBox(
                                            width: 50.0,
                                            height: 50.0,
                                            child: CircularProgressIndicator(
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                FlutterFlowTheme.of(context)
                                                    .primary,
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                      List<FavoriteEnseignesRecord>
                                          conditionalBuilderFavoriteEnseignesRecordList =
                                          snapshot.data!;
                                      final conditionalBuilderFavoriteEnseignesRecord =
                                          conditionalBuilderFavoriteEnseignesRecordList
                                                  .isNotEmpty
                                              ? conditionalBuilderFavoriteEnseignesRecordList
                                                  .first
                                              : null;

                                      return Builder(
                                        builder: (context) {
                                          if (!(conditionalBuilderFavoriteEnseignesRecord !=
                                              null)) {
                                            return FlutterFlowIconButton(
                                              borderRadius: 8.0,
                                              buttonSize: 40.0,
                                              icon: Icon(
                                                Icons.star_border,
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .error,
                                                size: 24.0,
                                              ),
                                              onPressed: () async {
                                                await FavoriteEnseignesRecord
                                                        .createDoc(
                                                            currentUserReference!)
                                                    .set({
                                                  ...createFavoriteEnseignesRecordData(
                                                    enseigneId: widget!
                                                        .enseigneDoc?.reference,
                                                  ),
                                                  ...mapToFirestore(
                                                    {
                                                      'added_at': FieldValue
                                                          .serverTimestamp(),
                                                    },
                                                  ),
                                                });
                                                safeSetState(() => _model
                                                        .firestoreRequestCompleter =
                                                    null);
                                                await _model
                                                    .waitForFirestoreRequestCompleted();
                                              },
                                            );
                                          } else {
                                            return FlutterFlowIconButton(
                                              borderRadius: 8.0,
                                              buttonSize: 40.0,
                                              icon: Icon(
                                                Icons.star,
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .error,
                                                size: 24.0,
                                              ),
                                              onPressed: () async {
                                                await conditionalBuilderFavoriteEnseignesRecord!
                                                    .reference
                                                    .delete();
                                              },
                                            );
                                          }
                                        },
                                      );
                                    },
                                  );
                                } else {
                                  return Container(
                                    decoration: BoxDecoration(),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                background: ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: Image.asset(
                    'assets/images/Background.png',
                    fit: BoxFit.cover,
                    alignment: Alignment(1.0, -1.0),
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
            child: Container(
              decoration: BoxDecoration(
                // gradient: LinearGradient(
                //   begin: Alignment.topCenter,
                //   end: Alignment.bottomCenter,
                //   colors: [
                //     Color(0xFFF4F7FF),
                //     Color(0xFFEFF2FB),
                  // ],
                // ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Padding(
                      padding:
                          EdgeInsetsDirectional.fromSTEB(20.0, 0.0, 20.0, 0.0),
                      child: SingleChildScrollView(
                        primary: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              // decoration: BoxDecoration(
                              //   color: Colors.white,
                              //   borderRadius: BorderRadius.circular(20.0),
                              //   boxShadow: [
                              //     BoxShadow(
                              //       color: Colors.black.withOpacity(0.06),
                              //       blurRadius: 14.0,
                              //       offset: Offset(0, 4),
                              //     ),
                              //   ],
                              // ),
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget!.enseigneDoc!.name,
                                      style: GoogleFonts.inter(
                                        fontSize: 32.0,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF23255E),
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    if (!functions.checkValueIsEmpty(
                                        widget!.enseigneDoc!.city))
                                      Padding(
                                        padding:
                                            EdgeInsetsDirectional.fromSTEB(
                                                0.0, 6.0, 0.0, 0.0),
                                        child: Text(
                                          widget!.enseigneDoc!.city,
                                          style: GoogleFonts.inter(
                                            fontSize: 16.0,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF6B70A7),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20.0),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.06),
                                    blurRadius: 14.0,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: EdgeInsetsDirectional.fromSTEB(
                                    16.0, 16.0, 16.0, 16.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    FutureBuilder<List<ImagesRecord>>(
                                      future: queryImagesRecordOnce(
                                        parent: widget!.enseigneDoc?.reference,
                                        limit: 5,
                                      ),
                                      builder: (context, snapshot) {
                                        // Customize what your widget looks like when it's loading.
                                        if (!snapshot.hasData) {
                                          return Center(
                                            child: SizedBox(
                                              width: 50.0,
                                              height: 50.0,
                                              child: CircularProgressIndicator(
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(
                                                  FlutterFlowTheme.of(context)
                                                      .primary,
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                        List<ImagesRecord> rowImagesRecordList =
                                            snapshot.data!;

                                        final descriptionText =
                                            widget!.enseigneDoc!.description;
                                        final hasDescription =
                                            !functions.checkValueIsEmpty(
                                                descriptionText);
                                        final hasImages =
                                            rowImagesRecordList.isNotEmpty;

                                        if (rowImagesRecordList.length == 1 &&
                                            hasDescription) {
                                          final rowImagesRecord =
                                              rowImagesRecordList.first;
                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: double.infinity,
                                                height: 200.0,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          20.0),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withOpacity(0.10),
                                                      blurRadius: 16.0,
                                                      offset: Offset(0, 4),
                                                    ),
                                                  ],
                                                ),
                                                child: InkWell(
                                                  splashColor:
                                                      Colors.transparent,
                                                  focusColor:
                                                      Colors.transparent,
                                                  hoverColor:
                                                      Colors.transparent,
                                                  highlightColor:
                                                      Colors.transparent,
                                                  onTap: () async {
                                                    await Navigator.push(
                                                      context,
                                                      PageTransition(
                                                        type:
                                                            PageTransitionType
                                                                .fade,
                                                        child:
                                                            FlutterFlowExpandedImageView(
                                                          image: Image.network(
                                                            rowImagesRecord.url,
                                                            fit: BoxFit.contain,
                                                          ),
                                                          allowRotation: false,
                                                          tag: rowImagesRecord
                                                              .url,
                                                          useHeroAnimation:
                                                              true,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  child: Hero(
                                                    tag: rowImagesRecord.url,
                                                    transitionOnUserGestures:
                                                        true,
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20.0),
                                                      child: Image.network(
                                                        rowImagesRecord.url,
                                                        width: double.infinity,
                                                        height: 200.0,
                                                        fit: BoxFit.cover,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(height: 16.0),
                                              Text(
                                                descriptionText,
                                                style: GoogleFonts.inter(
                                                  fontSize: 16.0,
                                                  height: 1.6,
                                                  fontWeight:
                                                      FontWeight.w400,
                                                  color: Color(0xFF2D3250),
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                            ],
                                          );
                                        }

                                        final screenWidth = MediaQuery.of(context).size.width;
                                        // Account for outer padding (20px each side) and card padding (16px each side)
                                        final imageWidth = screenWidth - 40.0 - 32.0;
                                        
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (hasImages)
                                              Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SingleChildScrollView(
                                                    controller: _model.imagesScrollController,
                                                    scrollDirection:
                                                        Axis.horizontal,
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.max,
                                                      children:
                                                          List.generate(
                                                              rowImagesRecordList
                                                                  .length,
                                                              (rowIndex) {
                                                        final rowImagesRecord =
                                                            rowImagesRecordList[
                                                                rowIndex];
                                                        return Container(
                                                          width: imageWidth,
                                                          height: 200.0,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors.white,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        20.0),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: Colors
                                                                    .black
                                                                    .withOpacity(
                                                                        0.10),
                                                                blurRadius: 16.0,
                                                                offset:
                                                                    Offset(0, 4),
                                                              ),
                                                            ],
                                                          ),
                                                          child: InkWell(
                                                            splashColor: Colors
                                                                .transparent,
                                                            focusColor: Colors
                                                                .transparent,
                                                            hoverColor: Colors
                                                                .transparent,
                                                            highlightColor:
                                                                Colors
                                                                    .transparent,
                                                            onTap: () async {
                                                              await Navigator
                                                                  .push(
                                                                context,
                                                                PageTransition(
                                                                  type:
                                                                      PageTransitionType
                                                                          .fade,
                                                                  child:
                                                                      FlutterFlowExpandedImageView(
                                                                    image: Image
                                                                        .network(
                                                                      rowImagesRecord
                                                                          .url,
                                                                      fit: BoxFit
                                                                          .contain,
                                                                    ),
                                                                    allowRotation:
                                                                        false,
                                                                    tag:
                                                                        rowImagesRecord
                                                                            .url,
                                                                    useHeroAnimation:
                                                                        true,
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                            child: Hero(
                                                              tag:
                                                                  rowImagesRecord
                                                                      .url,
                                                              transitionOnUserGestures:
                                                                  true,
                                                              child: ClipRRect(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            20.0),
                                                                child:
                                                                    Image.network(
                                                                  rowImagesRecord
                                                                      .url,
                                                                  width: imageWidth,
                                                                  height: 200.0,
                                                                  fit: BoxFit
                                                                      .cover,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      }).divide(SizedBox(
                                                              width: 10.0)),
                                                    ),
                                                  ),
                                                  if (rowImagesRecordList.length > 1)
                                                    Padding(
                                                      padding: EdgeInsetsDirectional.fromSTEB(0.0, 12.0, 0.0, 0.0),
                                                      child: Row(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: List.generate(
                                                          rowImagesRecordList.length,
                                                          (index) {
                                                            final currentIndex = _model.currentImageIndex.clamp(0, rowImagesRecordList.length - 1);
                                                            final isActive = index == currentIndex;
                                                            return Container(
                                                              width: isActive ? 8.0 : 6.0,
                                                              height: isActive ? 8.0 : 6.0,
                                                              margin: EdgeInsets.symmetric(horizontal: 4.0),
                                                              decoration: BoxDecoration(
                                                                color: isActive 
                                                                    ? Color(0xFF6B70A7)
                                                                    : Color(0xFF6B70A7).withOpacity(0.3),
                                                                shape: BoxShape.circle,
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            if (hasDescription)
                                              Padding(
                                                padding: EdgeInsetsDirectional.fromSTEB(0.0, hasImages ? 16.0 : 0.0, 0.0, 0.0),
                                                child: Text(
                                                  descriptionText,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 16.0,
                                                    height: 1.6,
                                                    fontWeight: FontWeight.w400,
                                                    color: Color(0xFF2D3250),
                                                    letterSpacing: 0.2,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              width: double.infinity,
                              // decoration: BoxDecoration(
                              //   color: Colors.white,
                              //   borderRadius: BorderRadius.circular(20.0),
                              //   boxShadow: [
                              //     BoxShadow(
                              //       color: Colors.black.withOpacity(0.06),
                              //       blurRadius: 14.0,
                              //       offset: Offset(0, 4),
                              //     ),
                              //   ],
                              // ),
                              child: Padding(
                                padding: EdgeInsets.all(5.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.max,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: EdgeInsets.all(14.0),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(14.0),
                                        border: Border.all(
                                          color: Color(0xFFE3E8F7),
                                          width: 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 36.0,
                                            height: 36.0,
                                            decoration: BoxDecoration(
                                              color: FlutterFlowTheme.of(context)
                                                  .primary
                                                  .withOpacity(0.12),
                                              borderRadius:
                                                  BorderRadius.circular(10.0),
                                            ),
                                            child: Icon(
                                              Icons.place_rounded,
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .primary,
                                              size: 20.0,
                                            ),
                                          ),
                                          SizedBox(width: 12.0),
                                          Expanded(
                                            child: Text(
                                              '${widget!.enseigneDoc?.city} · ${widget!.enseigneDoc?.address}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 15.0,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF3B3F74),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    InkWell(
                                      splashColor: Colors.transparent,
                                      focusColor: Colors.transparent,
                                      hoverColor: Colors.transparent,
                                      highlightColor: Colors.transparent,
                                      onTap: () async {
                                        await launchURL(
                                            'tel:${widget!.enseigneDoc!.phoneNumber}');
                                      },
                                      child: Container(
                                        width: double.infinity,
                                        padding: EdgeInsets.all(14.0),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(14.0),
                                          border: Border.all(
                                            color: Color(0xFFE3E8F7),
                                            width: 1.0,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 36.0,
                                              height: 36.0,
                                              decoration: BoxDecoration(
                                                color: FlutterFlowTheme.of(
                                                        context)
                                                    .primary
                                                    .withOpacity(0.12),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        10.0),
                                              ),
                                              child: Icon(
                                                Icons.phone_rounded,
                                                color: FlutterFlowTheme.of(
                                                        context)
                                                    .primary,
                                                size: 20.0,
                                              ),
                                            ),
                                            SizedBox(width: 12.0),
                                            Expanded(
                                              child: Text(
                                                widget!.enseigneDoc!.phoneNumber,
                                                style: GoogleFonts.inter(
                                                  fontSize: 15.0,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF3B3F74),
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              Icons.call_rounded,
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .primary,
                                              size: 18.0,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ]
                                      .divide(SizedBox(height: 12.0))
                                      .around(SizedBox(height: 6.0)),
                                ),
                              ),
                            ),
                            if (!functions.checkValueIsEmpty(
                                    widget!.enseigneDoc!.facebookLink) ||
                                !functions.checkValueIsEmpty(
                                    widget!.enseigneDoc!.twitterLink) ||
                                !functions.checkValueIsEmpty(
                                    widget!.enseigneDoc!.siteWebUrl) ||
                                !functions.checkValueIsEmpty(
                                    widget!.enseigneDoc!.instagramLink))
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20.0),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 14.0,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: 
                                  
                                     Column(
                                      mainAxisSize: MainAxisSize.max,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        
                                    
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    mainAxisSize: MainAxisSize.max,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      
                                      if (!functions.checkValueIsEmpty(
                                          widget!.enseigneDoc!.siteWebUrl))
                                        InkWell(
                                          splashColor: Colors.transparent,
                                          focusColor: Colors.transparent,
                                          hoverColor: Colors.transparent,
                                          highlightColor: Colors.transparent,
                                          onTap: () async {
                                            await launchURL(widget!
                                                .enseigneDoc!.siteWebUrl);
                                          },
                                          child: Container(
                                                            padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                                            decoration: BoxDecoration(
                                                              color: Color(0xFF1DA1F2).withOpacity(0.1),
                                                              borderRadius: BorderRadius.circular(12.0),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                FaIcon(
                                                                  FontAwesomeIcons.globe,
                                                                  color: Color(0xFF1DA1F2),
                                                                  size: 18.0,
                                                                ),
                                                                SizedBox(width: 6.0),
                                                                Text(
                                                                  'WEBSITE',
                                                                  style: GoogleFonts.inter(
                                                                    fontSize: 13.0,
                                                                    fontWeight: FontWeight.w600,
                                                                    color: Color(0xFF1DA1F2),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                          // child: Container(
                                          //   width: double.infinity,
                                          //   padding: EdgeInsets.all(14.0),
                                          //   decoration: BoxDecoration(
                                          //     color: Color(0xFFF7FAFF),
                                          //     borderRadius:
                                          //         BorderRadius.circular(14.0),
                                          //     border: Border.all(
                                          //       color: Color(0xFFE3E8F7),
                                          //       width: 1.0,
                                          //     ),
                                          //   ),
                                          //   child: Row(
                                          //     children: [
                                          //       Container(
                                          //         width: 36.0,
                                          //         height: 36.0,
                                          //         decoration: BoxDecoration(
                                          //           color: FlutterFlowTheme.of(
                                          //                   context)
                                          //               .primary
                                          //               .withOpacity(0.12),
                                          //           borderRadius:
                                          //               BorderRadius.circular(
                                          //                   10.0),
                                          //         ),
                                          //         child: Icon(
                                          //           Icons.language_rounded,
                                          //           color: FlutterFlowTheme.of(
                                          //                   context)
                                          //               .primary,
                                          //           size: 20.0,
                                          //         ),
                                          //       ),
                                          //       SizedBox(width: 10.0),
                                          //       Expanded(
                                          //         child: Text(
                                          //           widget!.enseigneDoc!
                                          //               .siteWebUrl,
                                          //           maxLines: 1,
                                          //           overflow:
                                          //               TextOverflow.ellipsis,
                                          //           style: GoogleFonts.inter(
                                          //             fontSize: 15.0,
                                          //             fontWeight:
                                          //                 FontWeight.w600,
                                          //             color: Color(0xFF3B3F74),
                                          //           ),
                                          //         ),
                                          //       ),
                                          //       Icon(
                                          //         Icons.open_in_new_rounded,
                                          //         color: FlutterFlowTheme.of(
                                          //                 context)
                                          //             .primary,
                                          //         size: 18.0,
                                          //       ),
                                          //     ],
                                          //   ),
                                          // ),
                                        ),
                                      if (!functions.checkValueIsEmpty(
                                          widget!.enseigneDoc!.facebookLink ))
                                     InkWell(
                                                          splashColor: Colors.transparent,
                                                          focusColor: Colors.transparent,
                                                          hoverColor: Colors.transparent,
                                                          highlightColor: Colors.transparent,
                                                          onTap: () async {
                                                                      await launchURL(widget!
                                                                          .enseigneDoc!
                                                                .facebookLink);
                                                          },
                                                          child: Container(
                                                            padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                                            decoration: BoxDecoration(
                                                              color: Color(0xFF1877F2).withOpacity(0.1),
                                                              borderRadius: BorderRadius.circular(12.0),
                                                            ),
                                                              child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                  Icon(
                                                                  Icons.facebook,
                                                                  color: Color(0xFF1877F2),
                                                                  size: 18.0,
                                                                ),
                                                                SizedBox(width: 6.0),
                                                                Text(
                                                                  'Facebook',
                                                                  style: GoogleFonts.inter(
                                                                    fontSize: 13.0,
                                                                    fontWeight: FontWeight.w600,
                                                                    color: Color(0xFF1877F2),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                              ),
                                                            ),
                                      if (!functions.checkValueIsEmpty(
                                          widget!.enseigneDoc!.instagramLink))
                                       InkWell(
                                                          splashColor: Colors.transparent,
                                                          focusColor: Colors.transparent,
                                                          hoverColor: Colors.transparent,
                                                          highlightColor: Colors.transparent,
                                                          onTap: () async {
                                                                      await launchURL(widget!
                                                                          .enseigneDoc!
                                                                          .instagramLink);
                                                                    },
                                                          child: Container(
                                                            padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                                            decoration: BoxDecoration(
                                                              color: Color(0xFFE4405F).withOpacity(0.1),
                                                              borderRadius: BorderRadius.circular(12.0),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                FaIcon(
                                                                  FontAwesomeIcons.instagram,
                                                                  color: Color(0xFFE4405F),
                                                                  size: 18.0,
                                                                ),
                                                                SizedBox(width: 6.0),
                                                                Text(
                                                                  'Instagram',
                                                                  style: GoogleFonts.inter(
                                                                    fontSize: 13.0,
                                                                    fontWeight: FontWeight.w600,
                                                                    color: Color(0xFFE4405F),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                              ),
                                                            ),
                                  


                                        
                                    ]
                                        .divide(SizedBox(height: 12.0))
                                        .around(SizedBox(height: 12.0)),
                                  ),

SizedBox(height: 1.0),

                                  // Social Media Links
                                  Row(
                                    mainAxisSize: MainAxisSize.max,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [

   if (!functions.checkValueIsEmpty(
                                          widget!.enseigneDoc!.instagramLink))
                                       InkWell(
                                                          splashColor: Colors.transparent,
                                                          focusColor: Colors.transparent,
                                                          hoverColor: Colors.transparent,
                                                          highlightColor: Colors.transparent,
                                                          onTap: () async {
                                                                      await launchURL(widget!
                                                                          .enseigneDoc!
                                                                          .instagramLink);
                                                                    },
                                                          child: Container(
                                                            padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                                            decoration: BoxDecoration(
                                                              color: Color(0xFFE4405F).withOpacity(0.1),
                                                              borderRadius: BorderRadius.circular(12.0),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                FaIcon(
                                                                  FontAwesomeIcons.instagram,
                                                                  color: Color(0xFFE4405F),
                                                                  size: 18.0,
                                                                ),
                                                                SizedBox(width: 6.0),
                                                                Text(
                                                                  'Instagram',
                                                                  style: GoogleFonts.inter(
                                                                    fontSize: 13.0,
                                                                    fontWeight: FontWeight.w600,
                                                                    color: Color(0xFFE4405F),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                              ),
                                                            ),
                                  


                                      // Twitter
                                          if (!functions.checkValueIsEmpty(
                                          widget!.enseigneDoc!.twitterLink))
                                          InkWell(
                                                          splashColor: Colors.transparent,
                                                          focusColor: Colors.transparent,
                                                          hoverColor: Colors.transparent,
                                                          highlightColor: Colors.transparent,
                                                          onTap: () async {
                                                                      await launchURL(widget!
                                                                          .enseigneDoc!
                                                                          .twitterLink);
                                                                    },
                                                          child: Container(
                                                            padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                                            decoration: BoxDecoration(
                                                              color: Color(0xFF1DA1F2).withOpacity(0.1),
                                                              borderRadius: BorderRadius.circular(12.0),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                FaIcon(
                                                                  FontAwesomeIcons.twitter,
                                                                  color: Color(0xFF1DA1F2),
                                                                  size: 18.0,
                                                                ),
                                                                SizedBox(width: 6.0),
                                                                Text(
                                                                  'Twitter',
                                                                  style: GoogleFonts.inter(
                                                                    fontSize: 13.0,
                                                                    fontWeight: FontWeight.w600,
                                                                    color: Color(0xFF1DA1F2),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),



                                    ],
                                  ),
                                  ])
                                ),
                              ),
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20.0),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.06),
                                    blurRadius: 14.0,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: EdgeInsetsDirectional.fromSTEB(
                                    16.0, 16.0, 16.0, 16.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    Text(
                                      'Horaires d\'ouverture',
                                      style: FlutterFlowTheme.of(context)
                                          .headlineSmall
                                          .override(
                                            font: GoogleFonts.interTight(
                                              fontWeight:
                                                  FlutterFlowTheme.of(context)
                                                      .headlineSmall
                                                      .fontWeight,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .headlineSmall
                                                      .fontStyle,
                                            ),
                                            fontSize: 20.0,
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
                                    FutureBuilder<List<HorairesRecord>>(
                                      future: (_model
                                                  .firestoreRequestCompleter ??=
                                              Completer<List<HorairesRecord>>()
                                                ..complete(
                                                    queryHorairesRecordOnce(
                                                  parent: widget!
                                                      .enseigneDoc?.reference,
                                                  queryBuilder:
                                                      (horairesRecord) =>
                                                          horairesRecord.orderBy(
                                                              'created_time'),
                                                )))
                                          .future,
                                      builder: (context, snapshot) {
                                        // Customize what your widget looks like when it's loading.
                                        if (!snapshot.hasData) {
                                          return Center(
                                            child: SizedBox(
                                              width: 50.0,
                                              height: 50.0,
                                              child: CircularProgressIndicator(
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(
                                                  FlutterFlowTheme.of(context)
                                                      .primary,
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                        List<HorairesRecord>
                                            columnHorairesRecordList =
                                            snapshot.data!;

                                        return Column(
                                          mainAxisSize: MainAxisSize.max,
                                          children: List.generate(
                                              columnHorairesRecordList.length,
                                              (columnIndex) {
                                            final columnHorairesRecord =
                                                columnHorairesRecordList[
                                                    columnIndex];
                                            return Padding(
                                              padding: EdgeInsetsDirectional
                                                  .fromSTEB(8.0, 0.0, 8.0, 0.0),
                                              child: Container(
                                                width: double.infinity,
                                                decoration: BoxDecoration(
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .secondaryBackground,
                                                ),
                                                child: Padding(
                                                  padding: EdgeInsetsDirectional
                                                      .fromSTEB(
                                                          8.0, 6.0, 8.0, 0.0),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(
                                                        columnHorairesRecord
                                                            .day!.name,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodyLarge
                                                                .override(
                                                                  font:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodyLarge
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodyLarge
                                                                        .fontStyle,
                                                                  ),
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyLarge
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyLarge
                                                                      .fontStyle,
                                                                ),
                                                      ),
                                                      Builder(
                                                        builder: (context) {
                                                          if (columnHorairesRecord
                                                              .isOpen) {
                                                            return Builder(
                                                              builder:
                                                                  (context) {
                                                                if (!columnHorairesRecord
                                                                    .isFullDay) {
                                                                  return Text(
                                                                    '${dateTimeFormat(
                                                                      "Hm",
                                                                      columnHorairesRecord
                                                                          .openingDay,
                                                                      locale: FFLocalizations.of(
                                                                              context)
                                                                          .languageCode,
                                                                    )} - ${dateTimeFormat(
                                                                      "Hm",
                                                                      columnHorairesRecord
                                                                          .closingDay,
                                                                      locale: FFLocalizations.of(
                                                                              context)
                                                                          .languageCode,
                                                                    )}',
                                                                    style: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodyMedium
                                                                        .override(
                                                                          font:
                                                                              GoogleFonts.inter(
                                                                            fontWeight:
                                                                                FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                            fontStyle:
                                                                                FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                          ),
                                                                          letterSpacing:
                                                                              0.0,
                                                                          fontWeight: FlutterFlowTheme.of(context)
                                                                              .bodyMedium
                                                                              .fontWeight,
                                                                          fontStyle: FlutterFlowTheme.of(context)
                                                                              .bodyMedium
                                                                              .fontStyle,
                                                                        ),
                                                                  );
                                                                } else {
                                                                  return Column(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .max,
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .end,
                                                                    children: [
                                                                      Text(
                                                                        '${dateTimeFormat(
                                                                          "Hm",
                                                                          columnHorairesRecord
                                                                              .openingMorning,
                                                                          locale:
                                                                              FFLocalizations.of(context).languageCode,
                                                                        )} - ${dateTimeFormat(
                                                                          "Hm",
                                                                          columnHorairesRecord
                                                                              .closingMorning,
                                                                          locale:
                                                                              FFLocalizations.of(context).languageCode,
                                                                        )}',
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
                                                                      ),
                                                                      Text(
                                                                        '${dateTimeFormat(
                                                                          "Hm",
                                                                          columnHorairesRecord
                                                                              .openingAfternoon,
                                                                          locale:
                                                                              FFLocalizations.of(context).languageCode,
                                                                        )} - ${dateTimeFormat(
                                                                          "Hm",
                                                                          columnHorairesRecord
                                                                              .closingAfternoon,
                                                                          locale:
                                                                              FFLocalizations.of(context).languageCode,
                                                                        )}',
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
                                                                      ),
                                                                    ],
                                                                  );
                                                                }
                                                              },
                                                            );
                                                          } else {
                                                            return Text(
                                                              'Fermé',
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
                                                            );
                                                          }
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                        );
                                      },
                                    ),
                                  ].divide(SizedBox(height: 16.0)),
                                ),
                              ),
                            ),
                            Align(
                              alignment: AlignmentDirectional(-1.0, 0.0),
                              child: Padding(
                                padding: EdgeInsetsDirectional.fromSTEB(
                                    0.0, 20.0, 0.0, 0.0),
                                child: Text(
                                  'JEUX EN COURS',
                                  textAlign: TextAlign.center,
                                  style: FlutterFlowTheme.of(context)
                                      .titleMedium
                                      .override(
                                        font: GoogleFonts.interTight(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .titleMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .titleMedium
                                                  .fontStyle,
                                        ),
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .titleMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .titleMedium
                                            .fontStyle,
                                      ),
                                ),
                              ),
                            ),
                            Container(
                              height: 500.0,
                              decoration: BoxDecoration(),
                              child: Builder(
                                builder: (context) {
                                  if (currentUserUid != null &&
                                      currentUserUid != '') {
                                    return Builder(
                                      builder: (context) {
                                        if (functions.isAdult(
                                            currentUserDocument!.birthday!)) {
                                          return FutureBuilder<
                                              List<GamesRecord>>(
                                            future: queryGamesRecordOnce(
                                              queryBuilder: (gamesRecord) =>
                                                  gamesRecord
                                                      .where(
                                                        'enseigne_id',
                                                        isEqualTo: widget!
                                                            .enseigneDoc
                                                            ?.reference,
                                                      )
                                                      .where(
                                                        'end_date',
                                                        isGreaterThan:
                                                            getCurrentTimestamp,
                                                      ),
                                              limit: 15,
                                            ),
                                            builder: (context, snapshot) {
                                              // Customize what your widget looks like when it's loading.
                                              if (!snapshot.hasData) {
                                                return Center(
                                                  child: SizedBox(
                                                    width: 50.0,
                                                    height: 50.0,
                                                    child:
                                                        CircularProgressIndicator(
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                              Color>(
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .primary,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }
                                              List<GamesRecord>
                                                  listViewGamesRecordList =
                                                  snapshot.data!;
                                              if (listViewGamesRecordList
                                                  .isEmpty) {
                                                return ListEmptyComponentWidget(
                                                  title: 'Liste vide',
                                                  description:
                                                      'Aucun jeux en cours',
                                                );
                                              }

                                              return ListView.separated(
                                                padding: EdgeInsets.zero,
                                                primary: false,
                                                scrollDirection: Axis.vertical,
                                                itemCount:
                                                    listViewGamesRecordList
                                                        .length,
                                                separatorBuilder: (_, __) =>
                                                    SizedBox(height: 10.0),
                                                itemBuilder:
                                                    (context, listViewIndex) {
                                                  final listViewGamesRecord =
                                                      listViewGamesRecordList[
                                                          listViewIndex];
                                                  return Material(
                                                    color: Colors.transparent,
                                                    elevation: 1.0,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20.0),
                                                    ),
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: FlutterFlowTheme
                                                                .of(context)
                                                            .secondaryBackground,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20.0),
                                                      ),
                                                      child: StreamBuilder<
                                                          EnseignesRecord>(
                                                        stream: EnseignesRecord
                                                            .getDocument(
                                                                listViewGamesRecord
                                                                    .enseigneId!),
                                                        builder: (context,
                                                            snapshot) {
                                                          // Customize what your widget looks like when it's loading.
                                                          if (!snapshot
                                                              .hasData) {
                                                            return Center(
                                                              child: SizedBox(
                                                                width: 50.0,
                                                                height: 50.0,
                                                                child:
                                                                    CircularProgressIndicator(
                                                                  valueColor:
                                                                      AlwaysStoppedAnimation<
                                                                          Color>(
                                                                    FlutterFlowTheme.of(
                                                                            context)
                                                                        .primary,
                                                                  ),
                                                                ),
                                                              ),
                                                            );
                                                          }

                                                          final rowEnseignesRecord =
                                                              snapshot.data!;

                                                          return InkWell(
                                                            splashColor: Colors
                                                                .transparent,
                                                            focusColor: Colors
                                                                .transparent,
                                                            hoverColor: Colors
                                                                .transparent,
                                                            highlightColor:
                                                                Colors
                                                                    .transparent,
                                                            onTap: () async {
                                                              await listViewGamesRecord
                                                                  .reference
                                                                  .update({
                                                                ...mapToFirestore(
                                                                  {
                                                                    'views': FieldValue
                                                                        .increment(
                                                                            1),
                                                                  },
                                                                ),
                                                              });

                                                              context.pushNamed(
                                                                JeuDetailJoueurPageWidget
                                                                    .routeName,
                                                                queryParameters:
                                                                    {
                                                                  'gameDoc':
                                                                      serializeParam(
                                                                    listViewGamesRecord,
                                                                    ParamType
                                                                        .Document,
                                                                  ),
                                                                  'enseigneDoc':
                                                                      serializeParam(
                                                                    widget!
                                                                        .enseigneDoc,
                                                                    ParamType
                                                                        .Document,
                                                                  ),
                                                                }.withoutNulls,
                                                                extra: <String,
                                                                    dynamic>{
                                                                  'gameDoc':
                                                                      listViewGamesRecord,
                                                                  'enseigneDoc':
                                                                      widget!
                                                                          .enseigneDoc,
                                                                  kTransitionInfoKey:
                                                                      TransitionInfo(
                                                                    hasTransition:
                                                                        true,
                                                                    transitionType:
                                                                        PageTransitionType
                                                                            .fade,
                                                                  ),
                                                                },
                                                              );
                                                            },
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .max,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .center,
                                                              children: [
                                                                Expanded(
                                                                  flex: 1,
                                                                  child:
                                                                      Container(
                                                                    height:
                                                                        150.0,
                                                                    decoration:
                                                                        BoxDecoration(),
                                                                    child:
                                                                        ClipRRect(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              8.0),
                                                                      child: Image
                                                                          .network(
                                                                        listViewGamesRecord
                                                                            .photo,
                                                                        fit: BoxFit
                                                                            .fill,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                                Expanded(
                                                                  flex: 2,
                                                                  child:
                                                                      Padding(
                                                                    padding: EdgeInsetsDirectional
                                                                        .fromSTEB(
                                                                            10.0,
                                                                            0.0,
                                                                            0.0,
                                                                            0.0),
                                                                    child:
                                                                        Column(
                                                                      mainAxisSize:
                                                                          MainAxisSize
                                                                              .max,
                                                                      mainAxisAlignment:
                                                                          MainAxisAlignment
                                                                              .start,
                                                                      crossAxisAlignment:
                                                                          CrossAxisAlignment
                                                                              .start,
                                                                      children:
                                                                          [
                                                                        SingleChildScrollView(
                                                                          scrollDirection:
                                                                              Axis.horizontal,
                                                                          child:
                                                                              Row(
                                                                            mainAxisSize:
                                                                                MainAxisSize.max,
                                                                            children: [
                                                                              Text(
                                                                                listViewGamesRecord.name,
                                                                                style: FlutterFlowTheme.of(context).bodyMedium.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FontWeight.w600,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                                      ),
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FontWeight.w600,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                                    ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                        Column(
                                                                          mainAxisSize:
                                                                              MainAxisSize.max,
                                                                          mainAxisAlignment:
                                                                              MainAxisAlignment.spaceEvenly,
                                                                          children:
                                                                              [
                                                                            Row(
                                                                              mainAxisSize: MainAxisSize.max,
                                                                              children: [
                                                                                Icon(
                                                                                  Icons.store_sharp,
                                                                                  color: FlutterFlowTheme.of(context).primaryText,
                                                                                  size: 18.0,
                                                                                ),
                                                                                Text(
                                                                                  rowEnseignesRecord.name,
                                                                                  style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                        font: GoogleFonts.inter(
                                                                                          fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                          fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                        ),
                                                                                        letterSpacing: 0.0,
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                            Row(
                                                                              mainAxisSize: MainAxisSize.max,
                                                                              children: [
                                                                                Icon(
                                                                                  Icons.location_on_sharp,
                                                                                  color: FlutterFlowTheme.of(context).primaryText,
                                                                                  size: 18.0,
                                                                                ),
                                                                                Text(
                                                                                  rowEnseignesRecord.city,
                                                                                  style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                        font: GoogleFonts.inter(
                                                                                          fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                          fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                        ),
                                                                                        letterSpacing: 0.0,
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                            Row(
                                                                              mainAxisSize: MainAxisSize.max,
                                                                              children: [
                                                                                FaIcon(
                                                                                  FontAwesomeIcons.piggyBank,
                                                                                  color: FlutterFlowTheme.of(context).primaryText,
                                                                                  size: 18.0,
                                                                                ),
                                                                                Text(
                                                                                  ' Valeur : ',
                                                                                  style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                        font: GoogleFonts.inter(
                                                                                          fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                          fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                        ),
                                                                                        letterSpacing: 0.0,
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                ),
                                                                                Text(
                                                                                  listViewGamesRecord.prizeValue.toString(),
                                                                                  style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                        font: GoogleFonts.inter(
                                                                                          fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                          fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                        ),
                                                                                        letterSpacing: 0.0,
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                            Row(
                                                                              mainAxisSize: MainAxisSize.max,
                                                                              children: [
                                                                                Icon(
                                                                                  Icons.calendar_month,
                                                                                  color: FlutterFlowTheme.of(context).primaryText,
                                                                                  size: 18.0,
                                                                                ),
                                                                                Text(
                                                                                  ' Valable jusqu\'au : ',
                                                                                  style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                        font: GoogleFonts.inter(
                                                                                          fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                          fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                        ),
                                                                                        letterSpacing: 0.0,
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                ),
                                                                                Text(
                                                                                  dateTimeFormat(
                                                                                    "d/M/y",
                                                                                    listViewGamesRecord.endDate!,
                                                                                    locale: FFLocalizations.of(context).languageCode,
                                                                                  ),
                                                                                  style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                        font: GoogleFonts.inter(
                                                                                          fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                          fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                        ),
                                                                                        letterSpacing: 0.0,
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                          ].divide(SizedBox(height: 5.0)),
                                                                        ),
                                                                      ].divide(SizedBox(
                                                                              height: 5.0)),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                          );
                                        } else {
                                          return FutureBuilder<
                                              List<GamesRecord>>(
                                            future: queryGamesRecordOnce(
                                              queryBuilder: (gamesRecord) =>
                                                  gamesRecord
                                                      .where(
                                                        'enseigne_id',
                                                        isEqualTo: widget!
                                                            .enseigneDoc
                                                            ?.reference,
                                                      )
                                                      .where(
                                                        'end_date',
                                                        isGreaterThan:
                                                            getCurrentTimestamp,
                                                      )
                                                      .where(
                                                        'prohibited_for_minors',
                                                        isEqualTo: false,
                                                      ),
                                              limit: 15,
                                            ),
                                            builder: (context, snapshot) {
                                              // Customize what your widget looks like when it's loading.
                                              if (!snapshot.hasData) {
                                                return Center(
                                                  child: SizedBox(
                                                    width: 50.0,
                                                    height: 50.0,
                                                    child:
                                                        CircularProgressIndicator(
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                              Color>(
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .primary,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }
                                              List<GamesRecord>
                                                  listViewGamesRecordList =
                                                  snapshot.data!;
                                              if (listViewGamesRecordList
                                                  .isEmpty) {
                                                return ListEmptyComponentWidget(
                                                  title: 'Liste vide',
                                                  description:
                                                      'Pas de jeu en cours',
                                                );
                                              }

                                              return ListView.separated(
                                                padding: EdgeInsets.zero,
                                                primary: false,
                                                scrollDirection: Axis.vertical,
                                                itemCount:
                                                    listViewGamesRecordList
                                                        .length,
                                                separatorBuilder: (_, __) =>
                                                    SizedBox(height: 10.0),
                                                itemBuilder:
                                                    (context, listViewIndex) {
                                                  final listViewGamesRecord =
                                                      listViewGamesRecordList[
                                                          listViewIndex];
                                                  return Container(
                                                    decoration: BoxDecoration(
                                                      color: FlutterFlowTheme
                                                              .of(context)
                                                          .secondaryBackground,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20.0),
                                                    ),
                                                    child: StreamBuilder<
                                                        EnseignesRecord>(
                                                      stream: EnseignesRecord
                                                          .getDocument(
                                                              listViewGamesRecord
                                                                  .enseigneId!),
                                                      builder:
                                                          (context, snapshot) {
                                                        // Customize what your widget looks like when it's loading.
                                                        if (!snapshot.hasData) {
                                                          return Center(
                                                            child: SizedBox(
                                                              width: 50.0,
                                                              height: 50.0,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                valueColor:
                                                                    AlwaysStoppedAnimation<
                                                                        Color>(
                                                                  FlutterFlowTheme.of(
                                                                          context)
                                                                      .primary,
                                                                ),
                                                              ),
                                                            ),
                                                          );
                                                        }

                                                        final rowEnseignesRecord =
                                                            snapshot.data!;

                                                        return InkWell(
                                                          splashColor: Colors
                                                              .transparent,
                                                          focusColor: Colors
                                                              .transparent,
                                                          hoverColor: Colors
                                                              .transparent,
                                                          highlightColor: Colors
                                                              .transparent,
                                                          onTap: () async {
                                                            await listViewGamesRecord
                                                                .reference
                                                                .update({
                                                              ...mapToFirestore(
                                                                {
                                                                  'views': FieldValue
                                                                      .increment(
                                                                          1),
                                                                },
                                                              ),
                                                            });

                                                            context.pushNamed(
                                                              JeuDetailJoueurPageWidget
                                                                  .routeName,
                                                              queryParameters: {
                                                                'gameDoc':
                                                                    serializeParam(
                                                                  listViewGamesRecord,
                                                                  ParamType
                                                                      .Document,
                                                                ),
                                                                'enseigneDoc':
                                                                    serializeParam(
                                                                  widget!
                                                                      .enseigneDoc,
                                                                  ParamType
                                                                      .Document,
                                                                ),
                                                              }.withoutNulls,
                                                              extra: <String,
                                                                  dynamic>{
                                                                'gameDoc':
                                                                    listViewGamesRecord,
                                                                'enseigneDoc':
                                                                    widget!
                                                                        .enseigneDoc,
                                                                kTransitionInfoKey:
                                                                    TransitionInfo(
                                                                  hasTransition:
                                                                      true,
                                                                  transitionType:
                                                                      PageTransitionType
                                                                          .fade,
                                                                ),
                                                              },
                                                            );
                                                          },
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .max,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .center,
                                                            children: [
                                                              Expanded(
                                                                flex: 1,
                                                                child:
                                                                    Container(
                                                                  height: 130.0,
                                                                  decoration:
                                                                      BoxDecoration(),
                                                                  child:
                                                                      ClipRRect(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                            8.0),
                                                                    child: Image
                                                                        .network(
                                                                      listViewGamesRecord
                                                                          .photo,
                                                                      fit: BoxFit
                                                                          .fill,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              Expanded(
                                                                flex: 2,
                                                                child: Padding(
                                                                  padding: EdgeInsetsDirectional
                                                                      .fromSTEB(
                                                                          10.0,
                                                                          0.0,
                                                                          0.0,
                                                                          0.0),
                                                                  child: Column(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .max,
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .start,
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    children: [
                                                                      Text(
                                                                        listViewGamesRecord
                                                                            .name,
                                                                        style: FlutterFlowTheme.of(context)
                                                                            .bodyMedium
                                                                            .override(
                                                                              font: GoogleFonts.inter(
                                                                                fontWeight: FontWeight.w600,
                                                                                fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                              ),
                                                                              letterSpacing: 0.0,
                                                                              fontWeight: FontWeight.w600,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                            ),
                                                                      ),
                                                                      Column(
                                                                        mainAxisSize:
                                                                            MainAxisSize.max,
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.spaceEvenly,
                                                                        children:
                                                                            [
                                                                          Row(
                                                                            mainAxisSize:
                                                                                MainAxisSize.max,
                                                                            children: [
                                                                              Icon(
                                                                                Icons.store_sharp,
                                                                                color: FlutterFlowTheme.of(context).primaryText,
                                                                                size: 18.0,
                                                                              ),
                                                                              Text(
                                                                                rowEnseignesRecord.name,
                                                                                style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                    ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          Row(
                                                                            mainAxisSize:
                                                                                MainAxisSize.max,
                                                                            children: [
                                                                              Icon(
                                                                                Icons.location_on_sharp,
                                                                                color: FlutterFlowTheme.of(context).primaryText,
                                                                                size: 18.0,
                                                                              ),
                                                                              Text(
                                                                                rowEnseignesRecord.city,
                                                                                style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                    ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          Row(
                                                                            mainAxisSize:
                                                                                MainAxisSize.max,
                                                                            children: [
                                                                              FaIcon(
                                                                                FontAwesomeIcons.piggyBank,
                                                                                color: FlutterFlowTheme.of(context).primaryText,
                                                                                size: 18.0,
                                                                              ),
                                                                              Text(
                                                                                ' Valeur : ',
                                                                                style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                    ),
                                                                              ),
                                                                              Text(
                                                                                listViewGamesRecord.prizeValue.toString(),
                                                                                style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                    ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          Row(
                                                                            mainAxisSize:
                                                                                MainAxisSize.max,
                                                                            children: [
                                                                              Icon(
                                                                                Icons.calendar_month,
                                                                                color: FlutterFlowTheme.of(context).primaryText,
                                                                                size: 18.0,
                                                                              ),
                                                                              Text(
                                                                                ' Valable jusqu\'au : ',
                                                                                style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                    ),
                                                                              ),
                                                                              Text(
                                                                                dateTimeFormat(
                                                                                  "d/M/y",
                                                                                  listViewGamesRecord.endDate!,
                                                                                  locale: FFLocalizations.of(context).languageCode,
                                                                                ),
                                                                                style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                    ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ].divide(SizedBox(height: 5.0)),
                                                                      ),
                                                                    ].divide(SizedBox(
                                                                        height:
                                                                            5.0)),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                          );
                                        }
                                      },
                                    );
                                  } else {
                                    return FutureBuilder<List<GamesRecord>>(
                                      future: queryGamesRecordOnce(
                                        queryBuilder: (gamesRecord) =>
                                            gamesRecord
                                                .where(
                                                  'enseigne_id',
                                                  isEqualTo: widget!
                                                      .enseigneDoc?.reference,
                                                )
                                                .where(
                                                  'end_date',
                                                  isGreaterThan:
                                                      getCurrentTimestamp,
                                                ),
                                        limit: 15,
                                      ),
                                      builder: (context, snapshot) {
                                        // Customize what your widget looks like when it's loading.
                                        if (!snapshot.hasData) {
                                          return Center(
                                            child: SizedBox(
                                              width: 50.0,
                                              height: 50.0,
                                              child: CircularProgressIndicator(
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(
                                                  FlutterFlowTheme.of(context)
                                                      .primary,
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                        List<GamesRecord>
                                            listViewGamesRecordList =
                                            snapshot.data!;
                                        if (listViewGamesRecordList.isEmpty) {
                                          return ListEmptyComponentWidget(
                                            title: 'Liste vide',
                                            description: 'Aucun jeux en cours',
                                          );
                                        }

                                        return ListView.separated(
                                          padding: EdgeInsets.zero,
                                          primary: false,
                                          scrollDirection: Axis.vertical,
                                          itemCount:
                                              listViewGamesRecordList.length,
                                          separatorBuilder: (_, __) =>
                                              SizedBox(height: 10.0),
                                          itemBuilder:
                                              (context, listViewIndex) {
                                            final listViewGamesRecord =
                                                listViewGamesRecordList[
                                                    listViewIndex];
                                            return Material(
                                              color: Colors.transparent,
                                              elevation: 1.0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20.0),
                                              ),
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .secondaryBackground,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          20.0),
                                                ),
                                                child: StreamBuilder<
                                                    EnseignesRecord>(
                                                  stream: EnseignesRecord
                                                      .getDocument(
                                                          listViewGamesRecord
                                                              .enseigneId!),
                                                  builder: (context, snapshot) {
                                                    // Customize what your widget looks like when it's loading.
                                                    if (!snapshot.hasData) {
                                                      return Center(
                                                        child: SizedBox(
                                                          width: 50.0,
                                                          height: 50.0,
                                                          child:
                                                              CircularProgressIndicator(
                                                            valueColor:
                                                                AlwaysStoppedAnimation<
                                                                    Color>(
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .primary,
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    }

                                                    final rowEnseignesRecord =
                                                        snapshot.data!;

                                                    return InkWell(
                                                      splashColor:
                                                          Colors.transparent,
                                                      focusColor:
                                                          Colors.transparent,
                                                      hoverColor:
                                                          Colors.transparent,
                                                      highlightColor:
                                                          Colors.transparent,
                                                      onTap: () async {
                                                        await listViewGamesRecord
                                                            .reference
                                                            .update({
                                                          ...mapToFirestore(
                                                            {
                                                              'views': FieldValue
                                                                  .increment(1),
                                                            },
                                                          ),
                                                        });

                                                        context.pushNamed(
                                                          JeuDetailJoueurPageWidget
                                                              .routeName,
                                                          queryParameters: {
                                                            'gameDoc':
                                                                serializeParam(
                                                              listViewGamesRecord,
                                                              ParamType
                                                                  .Document,
                                                            ),
                                                            'enseigneDoc':
                                                                serializeParam(
                                                              widget!
                                                                  .enseigneDoc,
                                                              ParamType
                                                                  .Document,
                                                            ),
                                                          }.withoutNulls,
                                                          extra: <String,
                                                              dynamic>{
                                                            'gameDoc':
                                                                listViewGamesRecord,
                                                            'enseigneDoc':
                                                                widget!
                                                                    .enseigneDoc,
                                                            kTransitionInfoKey:
                                                                TransitionInfo(
                                                              hasTransition:
                                                                  true,
                                                              transitionType:
                                                                  PageTransitionType
                                                                      .fade,
                                                            ),
                                                          },
                                                        );
                                                      },
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.max,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .center,
                                                        children: [
                                                          Expanded(
                                                            flex: 1,
                                                            child: Container(
                                                              height: 130.0,
                                                              decoration:
                                                                  BoxDecoration(),
                                                              child: ClipRRect(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            8.0),
                                                                child: Image
                                                                    .network(
                                                                  listViewGamesRecord
                                                                      .photo,
                                                                  fit: BoxFit
                                                                      .fill,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          Expanded(
                                                            flex: 2,
                                                            child: Padding(
                                                              padding:
                                                                  EdgeInsetsDirectional
                                                                      .fromSTEB(
                                                                          10.0,
                                                                          0.0,
                                                                          0.0,
                                                                          0.0),
                                                              child: Column(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .max,
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .start,
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  SingleChildScrollView(
                                                                    scrollDirection:
                                                                        Axis.horizontal,
                                                                    child: Row(
                                                                      mainAxisSize:
                                                                          MainAxisSize
                                                                              .max,
                                                                      children: [
                                                                        Text(
                                                                          listViewGamesRecord
                                                                              .name,
                                                                          style: FlutterFlowTheme.of(context)
                                                                              .bodyMedium
                                                                              .override(
                                                                                font: GoogleFonts.inter(
                                                                                  fontWeight: FontWeight.w600,
                                                                                  fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                                ),
                                                                                letterSpacing: 0.0,
                                                                                fontWeight: FontWeight.w600,
                                                                                fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                              ),
                                                                        ),
                                                                      ],
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
                                                                            MainAxisSize.max,
                                                                        children: [
                                                                          Icon(
                                                                            Icons.store_sharp,
                                                                            color:
                                                                                FlutterFlowTheme.of(context).primaryText,
                                                                            size:
                                                                                18.0,
                                                                          ),
                                                                          Text(
                                                                            rowEnseignesRecord.name,
                                                                            style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                  font: GoogleFonts.inter(
                                                                                    fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                  ),
                                                                                  letterSpacing: 0.0,
                                                                                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      Row(
                                                                        mainAxisSize:
                                                                            MainAxisSize.max,
                                                                        children: [
                                                                          Icon(
                                                                            Icons.location_on_sharp,
                                                                            color:
                                                                                FlutterFlowTheme.of(context).primaryText,
                                                                            size:
                                                                                18.0,
                                                                          ),
                                                                          Text(
                                                                            rowEnseignesRecord.city,
                                                                            style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                  font: GoogleFonts.inter(
                                                                                    fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                  ),
                                                                                  letterSpacing: 0.0,
                                                                                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      Row(
                                                                        mainAxisSize:
                                                                            MainAxisSize.max,
                                                                        children: [
                                                                          FaIcon(
                                                                            FontAwesomeIcons.piggyBank,
                                                                            color:
                                                                                FlutterFlowTheme.of(context).primaryText,
                                                                            size:
                                                                                18.0,
                                                                          ),
                                                                          Text(
                                                                            ' Valeur : ',
                                                                            style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                  font: GoogleFonts.inter(
                                                                                    fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                  ),
                                                                                  letterSpacing: 0.0,
                                                                                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                ),
                                                                          ),
                                                                          Text(
                                                                            listViewGamesRecord.prizeValue.toString(),
                                                                            style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                  font: GoogleFonts.inter(
                                                                                    fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                  ),
                                                                                  letterSpacing: 0.0,
                                                                                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      Row(
                                                                        mainAxisSize:
                                                                            MainAxisSize.max,
                                                                        children: [
                                                                          Icon(
                                                                            Icons.calendar_month,
                                                                            color:
                                                                                FlutterFlowTheme.of(context).primaryText,
                                                                            size:
                                                                                18.0,
                                                                          ),
                                                                          Text(
                                                                            ' Valable jusqu\'au : ',
                                                                            style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                  font: GoogleFonts.inter(
                                                                                    fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                  ),
                                                                                  letterSpacing: 0.0,
                                                                                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                ),
                                                                          ),
                                                                          Text(
                                                                            dateTimeFormat(
                                                                              "d/M/y",
                                                                              listViewGamesRecord.endDate!,
                                                                              locale: FFLocalizations.of(context).languageCode,
                                                                            ),
                                                                            style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                  font: GoogleFonts.inter(
                                                                                    fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                  ),
                                                                                  letterSpacing: 0.0,
                                                                                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ].divide(SizedBox(
                                                                        height:
                                                                            5.0)),
                                                                  ),
                                                                ].divide(SizedBox(
                                                                    height:
                                                                        5.0)),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    );
                                  }
                                },
                              ),
                            ),
                          ].divide(SizedBox(height: 10.0)),
                        ),
                      ),
                    ),
                  ),
                  wrapWithModel(
                    model: _model.customNavBarJoueurModel,
                    updateCallback: () => safeSetState(() {}),
                    child: CustomNavBarJoueurWidget(),
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
