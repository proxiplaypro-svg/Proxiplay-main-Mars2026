import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/custom_cloud_functions/custom_cloud_function_response_manager.dart';
import '/backend/schema/structs/index.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/components/update_horaire_card_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/flutter_flow/custom_functions.dart' as functions;
import '/index.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
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
      future: queryParticipantsDetailsRecordOnce(
        parent: widget!.gameDoc?.reference,
        queryBuilder: (participantsDetailsRecord) =>
            participantsDetailsRecord.where(
          'user_id',
          isEqualTo: currentUserReference,
        ),
        singleRecord: true,
      ),
      builder: (context, snapshot) {
        // Customize what your widget looks like when it's loading.
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
            body: Center(
              child: SizedBox(
                width: 50.0,
                height: 50.0,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    FlutterFlowTheme.of(context).primary,
                  ),
                ),
              ),
            ),
          );
        }
        List<ParticipantsDetailsRecord>
            jeuDetailJoueurPageParticipantsDetailsRecordList = snapshot.data!;
        final jeuDetailJoueurPageParticipantsDetailsRecord =
            jeuDetailJoueurPageParticipantsDetailsRecordList.isNotEmpty
                ? jeuDetailJoueurPageParticipantsDetailsRecordList.first
                : null;
        final endDate = widget!.gameDoc?.endDate;
        final endWindowEnd = endDate?.add(const Duration(hours: 48));
        final isWithinEndWindow = endDate != null &&
            getCurrentTimestamp.isAfter(endDate) &&
            (endWindowEnd != null &&
                getCurrentTimestamp.isBefore(endWindowEnd));
        final hasWinnerAnnouncement = isWithinEndWindow &&
            (widget!.gameDoc?.hasWinner ?? false) &&
            (widget!.gameDoc?.mainPrizeWinner != null);
        final hasMainPrize = (widget.gameDoc?.prizeValue ?? 0) > 0;
        final secondaryPrizes = widget.gameDoc?.secondaryPrizes ?? const [];
        final hasSecondaryPrizeEntries = secondaryPrizes.any((item) {
          final countValue = item['count'];
          final parsedCount = countValue is num
              ? countValue.toInt()
              : int.tryParse((countValue ?? '').toString()) ?? 0;
          return parsedCount > 0;
        });
        final secondaryPrizeDescription =
            (widget.gameDoc?.secondaryPrizeDescription ?? '').trim();
        final hasSecondaryPrizeDescriptionText =
            secondaryPrizeDescription.isNotEmpty &&
                secondaryPrizeDescription != '0';
        final hasSecondaryPrizeContent =
            hasSecondaryPrizeEntries || hasSecondaryPrizeDescriptionText;
        final leftActionVisible = (() {
          final isGuest = currentUserUid == null || currentUserUid == '';
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
                padding: EdgeInsets.only(left: 16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10.0,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
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
              title: Container(
                height: 40.0,
                child: Image.asset(
                  'assets/images/logo_D_secondaire.png',
                  height: 40.0,
                  fit: BoxFit.contain,
                ),
              ),
              actions: [
                                  Builder(
                                    builder: (context) {
                    if (currentUserUid != null && currentUserUid != '') {
                      return StreamBuilder<List<FavoriteGamesRecord>>(
                                          stream: queryFavoriteGamesRecord(
                                            parent: currentUserReference,
                          queryBuilder: (favoriteGamesRecord) =>
                                                    favoriteGamesRecord.where(
                                              'game_id',
                            isEqualTo: widget!.gameDoc?.reference,
                                            ),
                                            singleRecord: true,
                                          ),
                                          builder: (context, snapshot) {
                                            if (!snapshot.hasData) {
                            return Padding(
                              padding: EdgeInsets.only(right: 8.0),
                              child: Container(
                                width: 40.0,
                                height: 40.0,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 10.0,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                                child: SizedBox(
                                    width: 18.0,
                                    height: 18.0,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.0,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        FlutterFlowTheme.of(context).primary,
                                      ),
                                    ),
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
                            padding: EdgeInsets.only(right: 8.0),
                            child: Container(
                              width: 40.0,
                              height: 40.0,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.9),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10.0,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                                    icon: Icon(
                                  favoriteGame != null
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: favoriteGame != null
                                      ? Colors.red
                                      : FlutterFlowTheme.of(context).primaryText,
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
                                        gameId: widget!.gameDoc?.reference,
                                      ),
                                      ...mapToFirestore({
                                        'added_at': FieldValue.serverTimestamp(),
                                      }),
                                    });

                                    await widget!.gameDoc!.reference.update({
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
                      return SizedBox.shrink();
                                      }
                                    },
                                  ),
                Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: Container(
                    width: 40.0,
                    height: 40.0,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10.0,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                                      icon: Icon(
                        Icons.share_rounded,
                        color: FlutterFlowTheme.of(context).primaryText,
                        size: 20.0,
                                      ),
                                      onPressed: () async {
                                        await Share.share(
                                          'proxiplay://proxiplay.com/shareJeuPage?gameDoc=${widget!.gameDoc?.reference.id}&enseigneDoc=${widget!.enseigneDoc?.reference.id}',
                          sharePositionOrigin: getWidgetBoundingBox(context),
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
                            Image.network(
                              widget!.gameDoc!.photo,
                              width: double.infinity,
                              height: 320.0,
                              fit: BoxFit.cover,
                            ),
                            // Main Content Card (White) - Overlapping using Transform
                            Transform.translate(
                              offset: Offset(0, -30.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(30.0),
                                    topRight: Radius.circular(30.0),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 30.0,
                                      offset: Offset(0, -5),
                                      spreadRadius: 0,
                                    ),
                                  ],
                                ),
                                child: Padding(
                                padding: EdgeInsetsDirectional.fromSTEB(
                                    24.0, 
                                    (widget!.gameDoc?.description ?? '').trim().isEmpty ? 0.0 : 32.0, 
                                    24.0, 
                                    24.0
                                  ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.max,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Game Title
                                    Text(
                                      widget!.gameDoc!.name ?? 'Jeu', 
                                      style: GoogleFonts.inter(
                                        fontSize:  widget!.gameDoc!.name.isEmpty ? 0.0 : 28.0,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1A1A1A),
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    SizedBox(height: (widget!.gameDoc?.description ?? '').trim().isEmpty ? 12.0 : 16.0),
                                    // Modern Badges Row
                                    Wrap(
                                      spacing: 8.0,
                                      runSpacing: 8.0,
                                      children: [
                                        if (widget!.gameDoc!.prizeValue != null && widget!.gameDoc!.prizeValue! > 0)
                                    Container(
                                            padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                      decoration: BoxDecoration(
                                              color: Color(0xFFFFF4E6),
                                              borderRadius: BorderRadius.circular(12.0),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.emoji_events_rounded, size: 16.0, color: Color(0xFFFF9500)),
                                                SizedBox(width: 6.0),
                                                Text(
                                                  '${widget!.gameDoc!.prizeValue}€',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13.0,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFFFF9500),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if ((widget.enseigneDoc?.city ?? '')
                                            .trim()
                                            .isNotEmpty)
                                      Container(
                                            padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                        decoration: BoxDecoration(
                                              color: Color(0xFFF0F9FF),
                                              borderRadius: BorderRadius.circular(12.0),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                                children: [
                                                Icon(Icons.location_on_outlined, size: 16.0, color: Color(0xFF3B82F6)),
                                                SizedBox(width: 6.0),
                                                  Text(
                                                  widget.enseigneDoc?.city ?? '',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13.0,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF3B82F6),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (widget!.enseigneDoc != null)
                                          Container(
                                            padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                            decoration: BoxDecoration(
                                              color: Color(0xFFF0FDF4),
                                              borderRadius: BorderRadius.circular(12.0),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.store_rounded, size: 16.0, color: Color(0xFF10B981)),
                                                SizedBox(width: 6.0),
                                                  Text(
                                                  widget!.enseigneDoc!.name ?? '',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13.0,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF10B981),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    SizedBox(height: (widget!.gameDoc?.description ?? '').trim().isEmpty ? 16.0 : 24.0),
                                    // Action Buttons Column
                                    Column(
                                      children: [
                                        if (leftActionVisible)
                                      //     Expanded(
                                      // child:
                                         Builder(
                                        builder: (context) {
                                          if (currentUserUid != null &&
                                              currentUserUid != '') {
                                            return Builder(
                                              builder: (context) {
                                                if (widget!.gameDoc
                                                        ?.prohibitedForMinors ??
                                                    false) {
                                                  return Builder(
                                                    builder: (context) {
                                                      if (functions.isAdult(
                                                          currentUserDocument!
                                                              .birthday!)) {
                                                        return Visibility(
                                                          visible: widget!
                                                                  .gameDoc!
                                                                  .endDate! >
                                                              getCurrentTimestamp,
                                                          child: FFButtonWidget(
                                                            onPressed: ((widget!
                                                                            .gameDoc!
                                                                            .endDate! <
                                                                        getCurrentTimestamp) ||
                                                                    ((jeuDetailJoueurPageParticipantsDetailsRecord !=
                                                                            null) &&
                                                                        (jeuDetailJoueurPageParticipantsDetailsRecord!.lastPlay! >=
                                                                            getCurrentTimestamp)) ||
                                                                    (valueOrDefault(
                                                                            currentUserDocument?.remainingPart,
                                                                            0) <=
                                                                        0))
                                                                ? null
                                                                : () async {
                                                                    try {
                                                                      final result = await FirebaseFunctions
                                                                          .instance
                                                                          .httpsCallable(
                                                                              'participateInGameTransaction')
                                                                          .call({
                                                                        "gameRef": widget!
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
                                                                        errorCode:
                                                                            error.code,
                                                                        succeeded:
                                                                            false,
                                                                      );
                                                                    }

                                                                    if (_model
                                                                        .cloudFunction3sn!
                                                                        .succeeded!) {
                                                                      context
                                                                          .pushNamed(
                                                                        PlayJoueurPageWidget
                                                                            .routeName,
                                                                        queryParameters:
                                                                            {
                                                                          'game':
                                                                              serializeParam(
                                                                            widget!.gameDoc,
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
                                                                              widget!.gameDoc,
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
                                                                              title: Text(_model.cloudFunction3sn!.data!.message),
                                                                              actions: [
                                                                                TextButton(
                                                                                  onPressed: () => Navigator.pop(alertDialogContext),
                                                                                  child: Text('Ok'),
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
                                                              if (valueOrDefault(
                                                                      currentUserDocument
                                                                          ?.remainingPart,
                                                                      0) <=
                                                                  0) {
                                                                return 'Vous n\'avez plus de parties';
                                                              } else if (widget!
                                                                      .gameDoc!
                                                                      .endDate! <
                                                                  getCurrentTimestamp) {
                                                                return 'Le jeu est terminé';
                                                              } else if ((jeuDetailJoueurPageParticipantsDetailsRecord !=
                                                                      null) &&
                                                                  (jeuDetailJoueurPageParticipantsDetailsRecord!
                                                                          .lastPlay! >=
                                                                      getCurrentTimestamp)) {
                                                                return 'Vous avez déjà joué';
                                                              } else if ((jeuDetailJoueurPageParticipantsDetailsRecord !=
                                                                      null) &&
                                                                  (jeuDetailJoueurPageParticipantsDetailsRecord!
                                                                          .lastPlay! <
                                                                      getCurrentTimestamp)) {
                                                                return 'Rejouer';
                                                              } else {
                                                                return 'Participer';
                                                              }
                                                            }(),
                                                            options:
                                                                FFButtonOptions(
                                                              width: double
                                                                  .infinity,
                                                                  height: 56.0,
                                                              padding:
                                                                  EdgeInsets
                                                                      .all(0.0),
                                                              iconPadding:
                                                                  EdgeInsetsDirectional
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
                                                    visible: widget!
                                                            .gameDoc!.endDate! >
                                                        getCurrentTimestamp,
                                                    child: AuthUserStreamWidget(
                                                      builder: (context) =>
                                                          FFButtonWidget(
                                                        onPressed: ((widget!
                                                                        .gameDoc!
                                                                        .endDate! <
                                                                    getCurrentTimestamp) ||
                                                                ((jeuDetailJoueurPageParticipantsDetailsRecord !=
                                                                        null) &&
                                                                    (jeuDetailJoueurPageParticipantsDetailsRecord!
                                                                            .lastPlay! >=
                                                                        getCurrentTimestamp)) ||
                                                                (valueOrDefault(
                                                                        currentUserDocument
                                                                            ?.remainingPart,
                                                                        0) <=
                                                                    0))
                                                            ? null
                                                            : () async {
                                                                try {
                                                                  final result = await FirebaseFunctions
                                                                      .instance
                                                                      .httpsCallable(
                                                                          'participateInGameTransaction')
                                                                      .call({
                                                                    "gameRef": widget!
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
                                                                    errorCode:
                                                                        error
                                                                            .code,
                                                                    succeeded:
                                                                        false,
                                                                  );
                                                                }

                                                                if (_model
                                                                    .cloudFunction3sn2!
                                                                    .succeeded!) {
                                                                  context
                                                                      .pushNamed(
                                                                    PlayJoueurPageWidget
                                                                        .routeName,
                                                                    queryParameters:
                                                                        {
                                                                      'game':
                                                                          serializeParam(
                                                                        widget!
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
                                                                      'game': widget!
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
                                                                          title: Text(_model
                                                                              .cloudFunction3sn2!
                                                                              .data!
                                                                              .message),
                                                                          actions: [
                                                                            TextButton(
                                                                              onPressed: () => Navigator.pop(alertDialogContext),
                                                                              child: Text('Ok'),
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
                                                          if (valueOrDefault(
                                                                  currentUserDocument
                                                                      ?.remainingPart,
                                                                  0) <=
                                                              0) {
                                                            return 'Vous n\'avez plus de parties';
                                                          } else if (widget!
                                                                  .gameDoc!
                                                                  .endDate! <
                                                              getCurrentTimestamp) {
                                                            return 'Le jeu est terminé';
                                                          } else if ((jeuDetailJoueurPageParticipantsDetailsRecord !=
                                                                  null) &&
                                                              (jeuDetailJoueurPageParticipantsDetailsRecord!
                                                                      .lastPlay! >=
                                                                  getCurrentTimestamp)) {
                                                            return 'Vous avez déjà joué';
                                                          } else if ((jeuDetailJoueurPageParticipantsDetailsRecord !=
                                                                  null) &&
                                                              (jeuDetailJoueurPageParticipantsDetailsRecord!
                                                                      .lastPlay! <
                                                                  getCurrentTimestamp)) {
                                                                return '🎫 Rejouer';
                                                          } else {
                                                            return 'Participer';
                                                          }
                                                        }(),
                                                        options:
                                                            FFButtonOptions(
                                                          width:
                                                              double.infinity,
                                                              height: 56.0,
                                                          padding:
                                                              EdgeInsets.all(
                                                                      0.0),
                                                          iconPadding:
                                                              EdgeInsetsDirectional
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
                                                    ),
                                                  );
                                                }
                                              },
                                            );
                                          } else {
                                            return FFButtonWidget(
                                              onPressed: () async {
                                                if (Navigator.of(context)
                                                    .canPop()) {
                                                  context.pop();
                                                }
                                                context.pushNamed(
                                                    InscriptionPageWidget
                                                        .routeName);
                                              },
                                              text: 'Créer un compte',
                                              options: FFButtonOptions(
                                                width: double.infinity,
                                                    height: 56.0,
                                                padding: EdgeInsets.all(0.0),
                                                iconPadding:
                                                    EdgeInsetsDirectional
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

                                          SizedBox(height: 12.0),
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
                                              widget!.enseigneDoc,
                                              ParamType.Document,
                                            ),
                                          }.withoutNulls,
                                          extra: <String, dynamic>{
                                            'enseigneDoc': widget!.enseigneDoc,
                                          },
                                        );
                                      },
                                      child: Container(
                                                constraints: BoxConstraints(minHeight: 56.0),
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 12.0,
                                                  vertical: 8.0,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(16.0),
                                                  border: Border.all(
                                                    color: FlutterFlowTheme.of(context).primary,
                                                    width: 2.0,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.05),
                                                      blurRadius: 10.0,
                                                      offset: Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.store_rounded,
                                                      color: FlutterFlowTheme.of(context).primary,
                                                      size: 20.0,
                                                    ),
                                                    SizedBox(width: 8.0),
                                                    Flexible(
                                                      child: Text(
                                                        //  here name of the store
                                                        widget!.enseigneDoc!.name ?? '',
                                                        maxLines: 2,
                                                        softWrap: true,
                                                        overflow: TextOverflow.ellipsis,
                                                        textAlign: TextAlign.center,
                                                        style: GoogleFonts.inter(
                                                          fontSize: 16.0,
                                                          fontWeight: FontWeight.w600,
                                                          color: FlutterFlowTheme.of(context).primary,
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
                                    SizedBox(height: 24.0),
                                    // Winner Announcement Section
                                    if (hasWinnerAnnouncement)
                                      Container(
                                        width: double.infinity,
                                        margin: EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 24.0),
                                        padding: EdgeInsets.all(20.0),
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
                                              EdgeInsetsDirectional.fromSTEB(
                                                  16.0, 16.0, 16.0, 16.0),
                                          child: FutureBuilder<UsersRecord>(
                                            future: UsersRecord.getDocumentOnce(
                                                widget!
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
                                                    //   'Félicitations à $winnerName de ${snapshot.data!.city} !',
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
                                                    'Félicitations à $winnerName de ${snapshot.data!.city} !',
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
                                                    'Le jeu est terminé. Revenez bientôt pour découvrir les prochains jeux !',
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
                                            ].divide(SizedBox(height: 8.0)),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    if ((widget!.gameDoc?.description ?? '')
                                        .trim()
                                        .isNotEmpty)
                                    Container(
                                      width: double.infinity,
                                        margin: EdgeInsets.only(bottom: 16.0),
                                        padding: EdgeInsets.all(20.0),
                                      decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(24.0),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.05),
                                              blurRadius: 20.0,
                                              offset: Offset(0, 4),
                                              spreadRadius: 0,
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.max,
                                                      crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                              widget!.gameDoc!.description
                                                  .trim(),
                                              style: GoogleFonts.inter(
                                                fontSize: 15.0,
                                                fontWeight: FontWeight.w400,
                                                color: Color(0xFF4B5563),
                                                height: 1.6,
                                                letterSpacing: 0.0,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    // Store Information Section
                                    // if (widget!.enseigneDoc != null)
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
                                          //     widget!.enseigneDoc!.name ?? '',
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
                                          //                 parent: widget!
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
                                          //                 CircularProgressIndicator(
                                          //               valueColor:
                                          //                   AlwaysStoppedAnimation<
                                          //                       Color>(
                                          //                 FlutterFlowTheme.of(
                                          //                         context)
                                          //                     .primary,
                                          //               ),
                                          //               ),
                                          //             ),
                                          //           ),
                                          //         );
                                          //       }
                                          //       List<ImagesRecord>
                                          //           rowImagesRecordList =
                                          //           snapshot.data!;

                                          //     if (rowImagesRecordList.isEmpty) {
                                          //       return SizedBox.shrink();
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
                                        if (widget!.enseigneDoc != null) {
                                          return Column(
                                            mainAxisSize: MainAxisSize.max,
                                            children: [
                                              // Website Link Card
                                              if (!functions
                                                  .checkValueIsEmpty(
                                                      widget!
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
                                                //       await launchURL(widget!
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
                                                //                   widget!
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
                                              //         widget!.enseigneDoc!
                                              //             .facebookLink) ||
                                              //     !functions.checkValueIsEmpty(
                                              //         widget!.enseigneDoc!
                                              //             .twitterLink) ||
                                              //     !functions.checkValueIsEmpty(
                                              //         widget!.enseigneDoc!
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
                                              //             .checkValueIsEmpty(widget!
                                              //                         .enseigneDoc!
                                              //                 .facebookLink))
                                              //                     InkWell(
                                              //             splashColor: Colors.transparent,
                                              //             focusColor: Colors.transparent,
                                              //             hoverColor: Colors.transparent,
                                              //             highlightColor: Colors.transparent,
                                              //             onTap: () async {
                                              //                         await launchURL(widget!
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
                                              //                 .checkValueIsEmpty(widget!
                                              //                     .enseigneDoc!
                                              //                     .instagramLink))
                                              //                     InkWell(
                                              //             splashColor: Colors.transparent,
                                              //             focusColor: Colors.transparent,
                                              //             hoverColor: Colors.transparent,
                                              //             highlightColor: Colors.transparent,
                                              //             onTap: () async {
                                              //                         await launchURL(widget!
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
                                              //                 .checkValueIsEmpty(widget!
                                              //                     .enseigneDoc!
                                              //                     .twitterLink))
                                              //                     InkWell(
                                              //             splashColor: Colors.transparent,
                                              //             focusColor: Colors.transparent,
                                              //             hoverColor: Colors.transparent,
                                              //             highlightColor: Colors.transparent,
                                              //             onTap: () async {
                                              //                         await launchURL(widget!
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
                                                  parent: widget!
                                                      .enseigneDoc?.reference,
                                                  queryBuilder:
                                                      (horairesRecord) =>
                                                          horairesRecord.orderBy(
                                                              'created_time'),
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
                                                  List<HorairesRecord>
                                                      containerHorairesRecordList =
                                                      snapshot.data!;

                                                  return Container(
                                                    decoration: BoxDecoration(),
                                                  );
                                                },
                                              ),
                                              FutureBuilder<
                                                  List<HorairesRecord>>(
                                                future: queryHorairesRecordOnce(
                                                  parent: widget!
                                                      .enseigneDoc?.reference,
                                                  queryBuilder:
                                                      (horairesRecord) =>
                                                          horairesRecord.orderBy(
                                                              'created_time'),
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
  if (hasMainPrize || hasSecondaryPrizeContent)
                                      Container(
                                        width: double.infinity,
                                        margin:
                                            EdgeInsets.only(bottom: 16.0),
                                        padding: EdgeInsets.all(16.0),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                                            borderRadius:
                                              BorderRadius.circular(20.0),
                                          border: Border.all(
                                            color: Color(0xFFE5E7EB),
                                            width: 1.0,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.04),
                                              blurRadius: 12.0,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                                            child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                                              children: [
                                            // Text(
                                            //   'Lots à gagner',
                                            //   style: GoogleFonts.inter(
                                            //     fontSize: 22.0,
                                            //     fontWeight: FontWeight.w700,
                                            //     color: Color(0xFF1A1A1A),
                                            //     letterSpacing: -0.3,
                                            //   ),
                                            // ),
                                            // SizedBox(height: 12.0),
                                                                Text(
                                      widget!.gameDoc!.name ?? 'Jeu', 
                                      style: GoogleFonts.inter(
                                        fontSize:  widget!.gameDoc!.name.isEmpty ? 0.0 : 23.0,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF111827),
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    SizedBox(height: 12.0),
                                            if (hasMainPrize)
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Lot principal',
                                                          style: GoogleFonts
                                                              .inter(
                                                            fontSize: 14.0,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: Color(
                                                                0xFF111827),
                                                          ),
                                                        ),
                                                        SizedBox(height: 2.0),
                                                        Text(
                                                          '${widget.gameDoc?.prizeValue ?? 0} €',
                                                          style: GoogleFonts
                                                              .inter(
                                                            fontSize: 13.0,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color: Color(
                                                                0xFF374151),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                                                Container(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 10.0,
                                                            vertical: 4.0),
                                                                              decoration: BoxDecoration(
                                                      color: Color(0xFFFFF4E6),
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(20.0),
                                                    ),
                                                    child: Text(
                                                      'Tirage au sort',
                                                      style:
                                                          GoogleFonts.inter(
                                                        fontSize: 11.0,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            Color(0xFFFF9500),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            if (hasSecondaryPrizeContent)
                                              SizedBox(height: 10.0),
                                            if (hasSecondaryPrizeContent)
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                                                      children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Gains immédiats',
                                                          style: GoogleFonts
                                                              .inter(
                                                            fontSize: 14.0,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: Color(
                                                                0xFF111827),
                                                          ),
                                                        ),
                                                        if (hasSecondaryPrizeDescriptionText)
                                                          Padding(
                                                            padding:
                                                                EdgeInsets.only(
                                                                    top: 2.0),
                                                            child: Text(
                                                              secondaryPrizeDescription,
                                                              style: GoogleFonts
                                                                  .inter(
                                                                fontSize: 13.0,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                color: Color(
                                                                    0xFF374151),
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  Container(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 10.0,
                                                            vertical: 4.0),
                                                    decoration: BoxDecoration(
                                                      color: Color(0xFFEAFBF2),
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(20.0),
                                                    ),
                                                    child: Text(
                                                      'Gains immédiats',
                                                      style:
                                                          GoogleFonts.inter(
                                                        fontSize: 11.0,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            Color(0xFF10B981),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
                                              
                                              Container(
                                                width: double.infinity,
                                                margin:
                                                    EdgeInsets.only(bottom: 16.0),
                                                padding: EdgeInsets.all(16.0),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(20.0),
                                                  border: Border.all(
                                                    color: Color(0xFFE5E7EB),
                                                    width: 1.0,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withOpacity(0.04),
                                                      blurRadius: 12.0,
                                                      offset: Offset(0, 2),
                                                    ),
                                                  ],
                                                ),

                                                
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                                                                      children: [
                                                    
                                                                                                        Text(
                                                      'Règles du jeu',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 20.0,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color:
                                                            Color(0xFF1F2937),
                                                      ),
                                                    ),
                                                    SizedBox(height: 12.0),
                                                    Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .access_time_rounded,
                                                          size: 16.0,
                                                          color: Color(0xFF6B7280),
                                                        ),
                                                        SizedBox(width: 8.0),
                                                        Expanded(
                                                          child: Text(
                                                            'Début du jeu le ${widget!.gameDoc?.startDate != null ? dateTimeFormat("d/M/y", widget!.gameDoc!.startDate, locale: FFLocalizations.of(context).languageCode) : '-'}',
                                                            style: GoogleFonts
                                                                .inter(
                                                              fontSize: 13.0,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              color: Color(
                                                                  0xFF374151),
                                                              height: 1.35,
                                                            ),
                                                                                                              ),
                                                                                                        ),
                                                                                                      ],
                                                    ),
                                                    SizedBox(height: 8.0),
                                                    Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .pan_tool_alt_rounded,
                                                          size: 16.0,
                                                          color: Color(0xFF6B7280),
                                                        ),
                                                        SizedBox(width: 8.0),
                                                        Expanded(
                                                          child: Text(
                                                            'Grattez la zone ci-dessus pour découvrir si vous avez gagné',
                                                            style: GoogleFonts
                                                                .inter(
                                                              fontSize: 13.0,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              color: Color(
                                                                  0xFF374151),
                                                              height: 1.35,
                                                            ),
                                                          ),
                                                                                    ),
                                                                                  ],
                                                                                ),
                                                    SizedBox(height: 8.0),
                                               if (hasMainPrize)       Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                       Icon(
                                                          Icons
                                                              .card_giftcard_rounded,
                                                          size: 16.0,
                                                          color: Color(0xFF6B7280),
                                                        ),
                                                        SizedBox(width: 8.0),
                                                      
                                                        Expanded(
                                                          child: Text(
                                                            'Le lot principal sera attribué par tirage au sort le ${widget!.gameDoc?.endDate != null ? dateTimeFormat("d/M/y", widget!.gameDoc!.endDate, locale: FFLocalizations.of(context).languageCode) : '-'}',
                                                            style: GoogleFonts
                                                                .inter(
                                                              fontSize: 13.0,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              color: Color(
                                                                  0xFF374151),
                                                              height: 1.35,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    SizedBox(height: 8.0),
                                                 
                                                 if (hasSecondaryPrizeContent)
                                                    Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .emoji_events_outlined,
                                                          size: 16.0,
                                                          color: Color(0xFF6B7280),
                                                        ),
                                                        SizedBox(width: 8.0),
                                                        Expanded(
                                                          child: Text(
                                                            'De nombreux lots secondaires sont à gagner instantanément',
                                                            style: GoogleFonts
                                                                .inter(
                                                              fontSize: 13.0,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              color: Color(
                                                                  0xFF374151),
                                                              height: 1.35,
                                                        ),
                                                      ),
                                                    ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ].divide(SizedBox(height: 10.0)),
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
                                              padding: EdgeInsets.all(10.0),
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
                                                    SizedBox(height: 10.0)),
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
                      child: CustomNavBarJoueurWidget(),
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
