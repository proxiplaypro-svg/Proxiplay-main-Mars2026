import '/components/merchant_pickup_point.dart';
import 'dart:async';
import '/backend/backend.dart';
import '/components/custom_nav_bar_joueur_widget.dart';

import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'lot_detail_joueur_page_model.dart';
export 'lot_detail_joueur_page_model.dart';

/// page avec detail du lot gagné avec code a montrer au commercant pour
/// récupérer le lot
class LotDetailJoueurPageWidget extends StatefulWidget {
  const LotDetailJoueurPageWidget({
    super.key,
    required this.lot,
  });

  final PrizesRecord? lot;

  static String routeName = 'lotDetailJoueurPage';
  static String routePath = 'lotDetailJoueurPage';

  @override
  State<LotDetailJoueurPageWidget> createState() =>
      _LotDetailJoueurPageWidgetState();
}

class _LotDetailJoueurPageWidgetState extends State<LotDetailJoueurPageWidget> {
  late LotDetailJoueurPageModel _model;

  PrizesRecord? _lot;
  StreamSubscription? _lotSubscription;
  Timer? _expirationTimer;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _lot = widget.lot;
    _lotSubscription = widget.lot?.reference.snapshots().listen((snapshot) {
      if (mounted) {
        setState(() {
          _lot = snapshot.exists ? PrizesRecord.fromSnapshot(snapshot) : null;
        });
      }
    }, onError: (Object error) {
      if (mounted) {
        setState(() {
          _lot = null;
        });
      }
    });
    _expirationTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _model = createModel(context, () => LotDetailJoueurPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'lotDetailJoueurPage'});
  }

  @override
  void dispose() {
    _lotSubscription?.cancel();
    _expirationTimer?.cancel();
    _model.dispose();

    super.dispose();
  }

  Future<void> _copyClaimCode() async {
    final claimCode = _lot?.claimCode;
    if (claimCode == null || claimCode.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: claimCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Code copié'),
        backgroundColor: FlutterFlowTheme.of(context).primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: MediaQuery.sizeOf(context).width * 1.0,
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(24.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18.0,
            offset: const Offset(0.0, 8.0),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(24.0, 24.0, 24.0, 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: FlutterFlowTheme.of(context).headlineSmall.override(
                    font: GoogleFonts.interTight(
                      fontWeight: FontWeight.w700,
                      fontStyle:
                          FlutterFlowTheme.of(context).headlineSmall.fontStyle,
                    ),
                    color: const Color(0xFF2D2A72),
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 22.0),
            child,
          ],
        ),
      ),
    );
  }

  // Utilise pour les lots sans jeu classique lie (animations, jeu de
  // parrainage, defi mensuel) : ces moteurs de tirage n'ecrivent jamais
  // game_id sur le prize (voir draw_animation_winner.js /
  // referral_game_engine.js / monthly_challenge.js), donc
  // GamesRecord.getDocument(_lot!.gameId!) plantait ici avant meme
  // de commencer (null check operator sur un champ absent). Ce lot a
  // toujours son propre nom/description/claim_code denormalises, donc pas
  // besoin du jeu pour afficher l'essentiel.
  Widget _buildGamelessLotContent(BuildContext context) {
    final prize = _lot;
    final name = prize?.name.trim() ?? '';
    final conditions = _lotConditions();
    final winDate = prize?.winDate;

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(20.0, 20.0, 20.0, 32.0),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionCard(
            context: context,
            title: name.isNotEmpty ? name : 'Votre lot',
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (prize?.fulfillmentType == 'platform')
                  const Text('Remise du lot organisée par Proxiplay.'),
                if (prize?.fulfillmentType == 'review' ||
                    prize?.fulfillmentType == 'partner')
                  const Text(
                      'Contactez Proxiplay pour les modalités de remise.'),
                if (winDate != null)
                  Text(
                    'Gagné le ${dateTimeFormat('d/M/y', winDate, locale: FFLocalizations.of(context).languageCode)}',
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                          font: GoogleFonts.inter(
                            fontStyle: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .fontStyle,
                          ),
                          color: FlutterFlowTheme.of(context).secondaryText,
                          letterSpacing: 0.0,
                        ),
                  ),
                if (conditions != null) ...[
                  const SizedBox(height: 12.0),
                  Text(
                    conditions,
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                          font: GoogleFonts.inter(
                            fontStyle: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .fontStyle,
                          ),
                          color: FlutterFlowTheme.of(context).primaryText,
                          letterSpacing: 0.0,
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16.0),
          if (prize != null && prize.isAvailable)
            _buildSectionCard(
              context: context,
              title: 'Code de récupération',
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F6),
                      borderRadius: BorderRadius.circular(22.0),
                      border: Border.all(
                        color: const Color(0xFFA0134D),
                        width: 2.0,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          16.0, 24.0, 16.0, 24.0),
                      child: Text(
                        prize.claimCode,
                        textAlign: TextAlign.center,
                        style:
                            FlutterFlowTheme.of(context).displayMedium.override(
                                  font: GoogleFonts.interTight(
                                    fontWeight: FontWeight.w800,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .displayMedium
                                        .fontStyle,
                                  ),
                                  color: const Color(0xFFA0134D),
                                  fontSize: 34.0,
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  Text(
                    'Présentez ce code au commerçant',
                    textAlign: TextAlign.center,
                    style: FlutterFlowTheme.of(context).bodyLarge.override(
                          font: GoogleFonts.inter(
                            fontWeight: FontWeight.w500,
                            fontStyle: FlutterFlowTheme.of(context)
                                .bodyLarge
                                .fontStyle,
                          ),
                          color: FlutterFlowTheme.of(context).secondaryText,
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 16.0),
                  FFButtonWidget(
                    onPressed: () async {
                      await _copyClaimCode();
                    },
                    text: 'Copier le code',
                    icon: const Icon(Icons.copy_rounded, size: 18.0),
                    options: FFButtonOptions(
                      width: 190.0,
                      height: 44.0,
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          18.0, 0.0, 18.0, 0.0),
                      iconPadding: const EdgeInsetsDirectional.fromSTEB(
                          0.0, 0.0, 0.0, 0.0),
                      color: const Color(0xFFFFF1F6),
                      textStyle:
                          FlutterFlowTheme.of(context).bodyMedium.override(
                                font: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .fontStyle,
                                ),
                                color: const Color(0xFFA0134D),
                                letterSpacing: 0.0,
                                fontWeight: FontWeight.w600,
                              ),
                      elevation: 0.0,
                      borderSide: const BorderSide(
                        color: Color(0xFFF0C1D1),
                        width: 1.0,
                      ),
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                ],
              ),
            )
          else if (prize != null)
            _buildSectionCard(
              context: context,
              title: 'Code de récupération',
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF5FF),
                  borderRadius: BorderRadius.circular(18.0),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      16.0, 18.0, 16.0, 18.0),
                  child: Text(
                    prize.claimed == true ? 'Lot récupéré' : 'Lot expiré',
                    textAlign: TextAlign.center,
                    style: FlutterFlowTheme.of(context).titleMedium.override(
                          font: GoogleFonts.interTight(
                            fontWeight: FontWeight.w700,
                            fontStyle: FlutterFlowTheme.of(context)
                                .titleMedium
                                .fontStyle,
                          ),
                          color: const Color(0xFF2068B9),
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            ),
          if (prize != null && prize.fulfillmentType == 'merchant') ...[
            const SizedBox(height: 16),
            MerchantPickupPoint(enseigneRef: prize.enseigneId),
          ],
        ],
      ),
    );
  }

  String? _lotConditions() {
    final conditions = _lot?.description.trim() ?? '';
    return conditions.isEmpty ? null : conditions;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: const Color(0xFFF8F8FC),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0.0,
          automaticallyImplyLeading: false,
          titleSpacing: 0.0,
          title: Row(
            children: [
              Padding(
                padding:
                    const EdgeInsetsDirectional.fromSTEB(12.0, 0.0, 0.0, 0.0),
                child: FlutterFlowIconButton(
                  borderColor: Colors.transparent,
                  borderRadius: 18.0,
                  borderWidth: 1.0,
                  buttonSize: 48.0,
                  fillColor: Colors.white.withValues(alpha: 0.9),
                  icon: Icon(
                    Icons.chevron_left_rounded,
                    color: FlutterFlowTheme.of(context).primaryText,
                    size: 30.0,
                  ),
                  onPressed: () async {
                    context.pop();
                  },
                ),
              ),
              Padding(
                padding:
                    const EdgeInsetsDirectional.fromSTEB(12.0, 0.0, 0.0, 0.0),
                child: Text(
                  'Mes lots',
                  style: FlutterFlowTheme.of(context).headlineMedium.override(
                        font: GoogleFonts.interTight(
                          fontWeight: FontWeight.w700,
                          fontStyle: FlutterFlowTheme.of(context)
                              .headlineMedium
                              .fontStyle,
                        ),
                        color: const Color(0xFF2D2A72),
                        fontSize: 22.0,
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          top: true,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFCFBFF),
                  Color(0xFFF0F2FF),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _lot?.gameId == null
                      ? _buildGamelessLotContent(context)
                      : StreamBuilder<GamesRecord>(
                          stream: GamesRecord.getDocument(_lot!.gameId!),
                          builder: (context, snapshot) {
                            // Customize what your widget looks like when it's loading.
                            if (!snapshot.hasData) {
                              return const Center(
                                child: SizedBox(
                                  width: 50.0,
                                  height: 50.0,
                                  child: SizedBox.shrink(),
                                ),
                              );
                            }

                            final columnGamesRecord = snapshot.data!;
                            final lotConditions = _lotConditions();

                            return SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  Container(
                                    width:
                                        MediaQuery.sizeOf(context).width * 1.0,
                                    decoration: const BoxDecoration(
                                      borderRadius: BorderRadius.only(
                                        bottomLeft: Radius.circular(0.0),
                                        bottomRight: Radius.circular(0.0),
                                        topLeft: Radius.circular(0.0),
                                        topRight: Radius.circular(0.0),
                                      ),
                                    ),
                                    child: Padding(
                                      padding:
                                          const EdgeInsetsDirectional.fromSTEB(
                                              20.0, 24.0, 20.0, 24.0),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.max,
                                        children: [
                                          _buildSectionCard(
                                            context: context,
                                            title: 'Code de récupération',
                                            child: Builder(
                                              builder: (context) {
                                                if (_lot!.isAvailable) {
                                                  return Column(
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    children: [
                                                      Container(
                                                        width: double.infinity,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: const Color(
                                                              0xFFFFF1F6),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      22.0),
                                                          border: Border.all(
                                                            color: const Color(
                                                                0xFFA0134D),
                                                            width: 2.0,
                                                          ),
                                                        ),
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsetsDirectional
                                                                  .fromSTEB(
                                                                  16.0,
                                                                  24.0,
                                                                  16.0,
                                                                  24.0),
                                                          child: Text(
                                                            _lot!.claimCode,
                                                            textAlign: TextAlign
                                                                .center,
                                                            style: FlutterFlowTheme
                                                                    .of(context)
                                                                .displayMedium
                                                                .override(
                                                                  font: GoogleFonts
                                                                      .interTight(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .displayMedium
                                                                        .fontStyle,
                                                                  ),
                                                                  color: const Color(
                                                                      0xFFA0134D),
                                                                  fontSize:
                                                                      34.0,
                                                                  letterSpacing:
                                                                      1.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                      Text(
                                                        'Présentez ce code au commerçant',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodyLarge
                                                                .override(
                                                                  font:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodyLarge
                                                                        .fontStyle,
                                                                  ),
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .secondaryText,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                ),
                                                      ),
                                                      FFButtonWidget(
                                                        onPressed: () async {
                                                          await _copyClaimCode();
                                                        },
                                                        text: 'Copier le code',
                                                        icon: const Icon(
                                                          Icons.copy_rounded,
                                                          size: 18.0,
                                                        ),
                                                        options:
                                                            FFButtonOptions(
                                                          width: 190.0,
                                                          height: 44.0,
                                                          padding:
                                                              const EdgeInsetsDirectional
                                                                  .fromSTEB(
                                                                  18.0,
                                                                  0.0,
                                                                  18.0,
                                                                  0.0),
                                                          iconPadding:
                                                              const EdgeInsetsDirectional
                                                                  .fromSTEB(
                                                                  0.0,
                                                                  0.0,
                                                                  0.0,
                                                                  0.0),
                                                          color: const Color(
                                                              0xFFFFF1F6),
                                                          textStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodyMedium
                                                                  .override(
                                                                    font: GoogleFonts
                                                                        .inter(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodyMedium
                                                                          .fontStyle,
                                                                    ),
                                                                    color: const Color(
                                                                        0xFFA0134D),
                                                                    letterSpacing:
                                                                        0.0,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                  ),
                                                          elevation: 0.0,
                                                          borderSide:
                                                              const BorderSide(
                                                            color: Color(
                                                                0xFFF0C1D1),
                                                            width: 1.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      16.0),
                                                        ),
                                                      ),
                                                    ].divide(const SizedBox(
                                                        height: 16.0)),
                                                  );
                                                }

                                                return Container(
                                                  width: double.infinity,
                                                  decoration: BoxDecoration(
                                                    color:
                                                        const Color(0xFFEAF5FF),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            18.0),
                                                  ),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsetsDirectional
                                                            .fromSTEB(16.0,
                                                            18.0, 16.0, 18.0),
                                                    child: Text(
                                                      _lot!.claimed
                                                          ? 'Lot récupéré'
                                                          : 'Lot expiré',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: FlutterFlowTheme
                                                              .of(context)
                                                          .titleMedium
                                                          .override(
                                                            font: GoogleFonts
                                                                .interTight(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              fontStyle:
                                                                  FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleMedium
                                                                      .fontStyle,
                                                            ),
                                                            color: const Color(
                                                                0xFF2068B9),
                                                            letterSpacing: 0.0,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          MerchantPickupPoint(
                                              enseigneRef: _lot?.enseigneId),
                                          _buildSectionCard(
                                            context: context,
                                            title: 'Détails du lot',
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Text(
                                                  _lot!.name,
                                                  textAlign: TextAlign.center,
                                                  style: FlutterFlowTheme.of(
                                                          context)
                                                      .titleLarge
                                                      .override(
                                                        font: GoogleFonts
                                                            .interTight(
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .titleLarge
                                                                  .fontStyle,
                                                        ),
                                                        color: const Color(
                                                            0xFF2D2A72),
                                                        letterSpacing: 0.0,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                ),
                                                if (lotConditions != null) ...[
                                                  const SizedBox(height: 18.0),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: Text(
                                                      'Conditions',
                                                      style: FlutterFlowTheme
                                                              .of(context)
                                                          .titleMedium
                                                          .override(
                                                            font: GoogleFonts
                                                                .inter(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              fontStyle:
                                                                  FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleMedium
                                                                      .fontStyle,
                                                            ),
                                                            color: const Color(
                                                                0xFF2D2A72),
                                                            letterSpacing: 0.0,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8.0),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: Text(
                                                      lotConditions,
                                                      style: FlutterFlowTheme
                                                              .of(context)
                                                          .bodyLarge
                                                          .override(
                                                            font: GoogleFonts
                                                                .inter(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                              fontStyle:
                                                                  FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyLarge
                                                                      .fontStyle,
                                                            ),
                                                            color: const Color(
                                                                0xFF5E667E),
                                                            letterSpacing: 0.0,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          const SizedBox.shrink(),
                                        ].divide(const SizedBox(height: 24.0)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                wrapWithModel(
                  model: _model.customNavBarJoueurModel,
                  updateCallback: () => safeSetState(() {}),
                  child: const CustomNavBarJoueurWidget(
                    indexActive: 4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
