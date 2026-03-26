import '/backend/backend.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/components/update_horaire_card_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webviewx_plus/webviewx_plus.dart';
import 'lot_detail_joueur_page_model.dart';
export 'lot_detail_joueur_page_model.dart';

/// page avec detail du lot gagnÃ© avec code a montrer au commercant pour
/// rÃ©cupÃ©rer le lot
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

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => LotDetailJoueurPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'lotDetailJoueurPage'});
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  Future<void> _copyClaimCode() async {
    final claimCode = widget.lot?.claimCode;
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

  String _scheduleLabel(HorairesRecord record) {
    if (!record.isOpen) {
      return 'Fermé';
    }

    if (!record.isFullDay) {
      return '${dateTimeFormat(
        "Hm",
        record.openingDay,
        locale: FFLocalizations.of(context).languageCode,
      )} - ${dateTimeFormat(
        "Hm",
        record.closingDay,
        locale: FFLocalizations.of(context).languageCode,
      )}';
    }

    return '${dateTimeFormat(
      "Hm",
      record.openingMorning,
      locale: FFLocalizations.of(context).languageCode,
    )} - ${dateTimeFormat(
      "Hm",
      record.closingMorning,
      locale: FFLocalizations.of(context).languageCode,
    )}\n${dateTimeFormat(
      "Hm",
      record.openingAfternoon,
      locale: FFLocalizations.of(context).languageCode,
    )} - ${dateTimeFormat(
      "Hm",
      record.closingAfternoon,
      locale: FFLocalizations.of(context).languageCode,
    )}';
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HorairesRecord>>(
      stream: queryHorairesRecord(
        parent: widget.lot?.enseigneId,
        queryBuilder: (horairesRecord) =>
            horairesRecord.orderBy('created_time'),
      ),
      builder: (context, snapshot) {
        // Customize what your widget looks like when it's loading.
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
            body: const Center(
              child: SizedBox(
                width: 50.0,
                height: 50.0,
                child: SizedBox.shrink(),
              ),
            ),
          );
        }
        List<HorairesRecord> lotDetailJoueurPageHorairesRecordList =
            snapshot.data!;

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
                      child: StreamBuilder<GamesRecord>(
                        stream: GamesRecord.getDocument(widget.lot!.gameId!),
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

                          return SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                Container(
                                  width: MediaQuery.sizeOf(context).width * 1.0,
                                  decoration: const BoxDecoration(
                                    borderRadius: BorderRadius.only(
                                      bottomLeft: Radius.circular(0.0),
                                      bottomRight: Radius.circular(0.0),
                                      topLeft: Radius.circular(0.0),
                                      topRight: Radius.circular(0.0),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(
                                        20.0, 24.0, 20.0, 24.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.max,
                                      children: [
                                        _buildSectionCard(
                                          context: context,
                                          title: 'Code de récupération',
                                          child: Builder(
                                            builder: (context) {
                                              if (!widget.lot!.claimed) {
                                                return Column(
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
                                                          widget.lot!.claimCode,
                                                          textAlign: TextAlign.center,
                                                          style: FlutterFlowTheme.of(context)
                                                              .displayMedium
                                                              .override(
                                                                font: GoogleFonts.interTight(
                                                                  fontWeight: FontWeight.w800,
                                                                  fontStyle: FlutterFlowTheme.of(context).displayMedium.fontStyle,
                                                                ),
                                                                color: const Color(0xFFA0134D),
                                                                fontSize: 34.0,
                                                                letterSpacing: 1.5,
                                                                fontWeight: FontWeight.w800,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                    Text(
                                                      'Présentez ce code au commerçant',
                                                      textAlign: TextAlign.center,
                                                      style: FlutterFlowTheme.of(context)
                                                          .bodyLarge
                                                          .override(
                                                            font: GoogleFonts.inter(
                                                              fontWeight: FontWeight.w500,
                                                              fontStyle: FlutterFlowTheme.of(context).bodyLarge.fontStyle,
                                                            ),
                                                            color: FlutterFlowTheme.of(context).secondaryText,
                                                            letterSpacing: 0.0,
                                                            fontWeight: FontWeight.w500,
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
                                                      options: FFButtonOptions(
                                                        width: 190.0,
                                                        height: 44.0,
                                                        padding: const EdgeInsetsDirectional.fromSTEB(
                                                            18.0, 0.0, 18.0, 0.0),
                                                        iconPadding: const EdgeInsetsDirectional.fromSTEB(
                                                            0.0, 0.0, 0.0, 0.0),
                                                        color: const Color(0xFFFFF1F6),
                                                        textStyle: FlutterFlowTheme.of(context)
                                                            .bodyMedium
                                                            .override(
                                                              font: GoogleFonts.inter(
                                                                fontWeight: FontWeight.w600,
                                                                fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
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
                                                  ].divide(const SizedBox(height: 16.0)),
                                                );
                                              }

                                              return Container(
                                                width: double.infinity,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFEAF5FF),
                                                  borderRadius: BorderRadius.circular(18.0),
                                                ),
                                                child: Padding(
                                                  padding: const EdgeInsetsDirectional.fromSTEB(
                                                      16.0, 18.0, 16.0, 18.0),
                                                  child: Text(
                                                    'Lot récupéré',
                                                    textAlign: TextAlign.center,
                                                    style: FlutterFlowTheme.of(context)
                                                        .titleMedium
                                                        .override(
                                                          font: GoogleFonts.interTight(
                                                            fontWeight: FontWeight.w700,
                                                            fontStyle: FlutterFlowTheme.of(context).titleMedium.fontStyle,
                                                          ),
                                                          color: const Color(0xFF2068B9),
                                                          letterSpacing: 0.0,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        FutureBuilder<EnseignesRecord>(
                                          future:
                                              EnseignesRecord.getDocumentOnce(
                                                  columnGamesRecord
                                                      .enseigneId!),
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

                                            final containerEnseignesRecord =
                                                snapshot.data!;

                                            return Container(
                                              decoration: BoxDecoration(
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .secondaryBackground,
                                                borderRadius:
                                                    BorderRadius.circular(16.0),
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsetsDirectional
                                                    .fromSTEB(
                                                        20.0, 20.0, 20.0, 20.0),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
                                                  children: [
                                                    Text(
                                                      'Point de Retrait',
                                                      style:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .headlineSmall
                                                              .override(
                                                                font: GoogleFonts
                                                                    .interTight(
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .headlineSmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .headlineSmall
                                                                      .fontStyle,
                                                                ),
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight: FlutterFlowTheme.of(
                                                                        context)
                                                                    .headlineSmall
                                                                    .fontWeight,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .headlineSmall
                                                                    .fontStyle,
                                                              ),
                                                    ),
                                                    const SizedBox.shrink(),
                                                    FFButtonWidget(
                                                      onPressed: () async {
                                                        context.pushNamed(
                                                          EnseigneDetailJoueurPageWidget
                                                              .routeName,
                                                          queryParameters: {
                                                            'enseigneDoc':
                                                                serializeParam(
                                                              containerEnseignesRecord,
                                                              ParamType
                                                                  .Document,
                                                            ),
                                                          }.withoutNulls,
                                                          extra: <String,
                                                              dynamic>{
                                                            'enseigneDoc':
                                                                containerEnseignesRecord,
                                                          },
                                                        );
                                                      },
                                                      text:
                                                          containerEnseignesRecord
                                                              .name,
                                                      options: FFButtonOptions(
                                                        width: double.infinity,
                                                        height: 48.0,
                                                        padding:
                                                            const EdgeInsetsDirectional
                                                                .fromSTEB(
                                                                    16.0,
                                                                    0.0,
                                                                    16.0,
                                                                    0.0),
                                                        iconPadding:
                                                            const EdgeInsetsDirectional
                                                                .fromSTEB(
                                                                    0.0,
                                                                    0.0,
                                                                    0.0,
                                                                    0.0),
                                                        color: const Color(0xFFFFF1F6),
                                                        textStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .titleSmall
                                                                .override(
                                                                  font: GoogleFonts
                                                                      .interTight(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleSmall
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleSmall
                                                                        .fontStyle,
                                                                  ),
                                                                  color: const Color(
                                                                      0xFFA0134D),
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
                                                        elevation: 0.0,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(30.0),
                                                        borderSide: const BorderSide(
                                                          color: Color(0xFFA0134D),
                                                          width: 1.4,
                                                        ),
                                                      ),
                                                    ),
                                                    Container(
                                                      width: double.infinity,
                                                      decoration:
                                                          const BoxDecoration(),
                                                      child: InkWell(
                                                        splashColor: Colors.transparent,
                                                        focusColor: Colors.transparent,
                                                        hoverColor: Colors.transparent,
                                                        highlightColor: Colors.transparent,
                                                        onTap: () async {
                                                          final fullAddress =
                                                              '${containerEnseignesRecord.address}, ${containerEnseignesRecord.areaCode} ${containerEnseignesRecord.city}';
                                                          final encodedAddress =
                                                              Uri.encodeComponent(
                                                                  fullAddress);
                                                          final mapUrl =
                                                              'https://www.google.com/maps/search/?api=1&query=$encodedAddress';
                                                          await launchURL(mapUrl);
                                                        },
                                                        child: Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment.start,
                                                          children: [
                                                            Icon(
                                                              Icons.location_on,
                                                              color: FlutterFlowTheme
                                                                      .of(context)
                                                                  .primary,
                                                              size: 24.0,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                '${containerEnseignesRecord.address}, ${containerEnseignesRecord.areaCode} ${containerEnseignesRecord.city}',
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow.ellipsis,
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
                                                                      letterSpacing:
                                                                          0.0,
                                                                      fontWeight:
                                                                          FlutterFlowTheme.of(context)
                                                                              .bodyMedium
                                                                              .fontWeight,
                                                                      fontStyle:
                                                                          FlutterFlowTheme.of(context)
                                                                              .bodyMedium
                                                                              .fontStyle,
                                                                      color: const Color(
                                                                          0xFFA0134D),
                                                                      decoration:
                                                                          TextDecoration
                                                                              .underline,
                                                                    ),
                                                              ),
                                                            ),
                                                          ].divide(const SizedBox(
                                                              width: 12.0)),
                                                        ),
                                                      ),
                                                    ),
                                                    Row(
                                                      mainAxisSize:
                                                          MainAxisSize.max,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Icon(
                                                          Icons.access_time,
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .primary,
                                                          size: 24.0,
                                                        ),
                                                        Expanded(
                                                          child: Builder(
                                                            builder: (context) {
                                                              final addHoraireCommercantPageVar =
                                                                  lotDetailJoueurPageHorairesRecordList
                                                                      .toList();

                                                              return ListView
                                                                  .separated(
                                                                padding:
                                                                    EdgeInsets
                                                                        .zero,
                                                                primary: false,
                                                                shrinkWrap:
                                                                    true,
                                                                scrollDirection:
                                                                    Axis.vertical,
                                                                itemCount:
                                                                    addHoraireCommercantPageVar
                                                                        .length,
                                                                separatorBuilder: (_,
                                                                        __) =>
                                                                    const SizedBox(
                                                                        height:
                                                                            10.0),
                                                                itemBuilder:
                                                                    (context,
                                                                        addHoraireCommercantPageVarIndex) {
                                                                  final addHoraireCommercantPageVarItem =
                                                                      addHoraireCommercantPageVar[
                                                                          addHoraireCommercantPageVarIndex];
                                                                  return Padding(
                                                                    padding: const EdgeInsetsDirectional
                                                                        .fromSTEB(
                                                                            8.0,
                                                                            0.0,
                                                                            8.0,
                                                                            0.0),
                                                                    child:
                                                                        InkWell(
                                                                      splashColor:
                                                                          Colors
                                                                              .transparent,
                                                                      focusColor:
                                                                          Colors
                                                                              .transparent,
                                                                      hoverColor:
                                                                          Colors
                                                                              .transparent,
                                                                      highlightColor:
                                                                          Colors
                                                                              .transparent,
                                                                      onTap:
                                                                          () async {
                                                                        await showModalBottomSheet(
                                                                          isScrollControlled:
                                                                              true,
                                                                          backgroundColor:
                                                                              Colors.transparent,
                                                                          enableDrag:
                                                                              false,
                                                                          context:
                                                                              context,
                                                                          builder:
                                                                              (context) {
                                                                            return WebViewAware(
                                                                              child: GestureDetector(
                                                                                onTap: () {
                                                                                  FocusScope.of(context).unfocus();
                                                                                  FocusManager.instance.primaryFocus?.unfocus();
                                                                                },
                                                                                child: Padding(
                                                                                  padding: MediaQuery.viewInsetsOf(context),
                                                                                  child: SizedBox(
                                                                                    height: MediaQuery.sizeOf(context).height * 0.7,
                                                                                    child: UpdateHoraireCardWidget(
                                                                                      day: addHoraireCommercantPageVarItem,
                                                                                    ),
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            );
                                                                          },
                                                                        ).then((value) =>
                                                                            safeSetState(() {}));
                                                                      },
                                                                      child:
                                                                          Container(
                                                                        width: double
                                                                            .infinity,
                                                                        decoration:
                                                                            BoxDecoration(
                                                                          borderRadius:
                                                                              BorderRadius.circular(0.0),
                                                                        ),
                                                                        child:
                                                                            Padding(
                                                                          padding: const EdgeInsetsDirectional.fromSTEB(
                                                                              8.0,
                                                                              8.0,
                                                                              8.0,
                                                                              8.0),
                                                                          child:
                                                                              Row(
                                                                            mainAxisSize:
                                                                                MainAxisSize.max,
                                                                            mainAxisAlignment:
                                                                                MainAxisAlignment.spaceBetween,
                                                                            children: [
                                                                              Text(
                                                                                addHoraireCommercantPageVarItem.day!.name,
                                                                                style: FlutterFlowTheme.of(context).bodyLarge.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodyLarge.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodyLarge.fontStyle,
                                                                                      ),
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FlutterFlowTheme.of(context).bodyLarge.fontWeight,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodyLarge.fontStyle,
                                                                                    ),
                                                                              ),
                                                                              Row(
                                                                                mainAxisSize: MainAxisSize.max,
                                                                                children: [
                                                                                  Builder(
                                                                                    builder: (context) {
                                                                                      if (addHoraireCommercantPageVarItem.isOpen) {
                                                                                        return Builder(
                                                                                          builder: (context) {
                                                                                            if (!addHoraireCommercantPageVarItem.isFullDay) {
                                                                                              return Text(
                                                                                                '${dateTimeFormat(
                                                                                                  "Hm",
                                                                                                  addHoraireCommercantPageVarItem.openingDay,
                                                                                                  locale: FFLocalizations.of(context).languageCode,
                                                                                                )} - ${dateTimeFormat(
                                                                                                  "Hm",
                                                                                                  addHoraireCommercantPageVarItem.closingDay,
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
                                                                                                      addHoraireCommercantPageVarItem.openingMorning,
                                                                                                      locale: FFLocalizations.of(context).languageCode,
                                                                                                    )} - ${dateTimeFormat(
                                                                                                      "Hm",
                                                                                                      addHoraireCommercantPageVarItem.closingMorning,
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
                                                                                                      addHoraireCommercantPageVarItem.openingAfternoon,
                                                                                                      locale: FFLocalizations.of(context).languageCode,
                                                                                                    )} - ${dateTimeFormat(
                                                                                                      "Hm",
                                                                                                      addHoraireCommercantPageVarItem.closingAfternoon,
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
                                                                                          'Fermé',
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
                                                                                      }
                                                                                    },
                                                                                  ),
                                                                                ].divide(const SizedBox(width: 10.0)),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  );
                                                                },
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                      ].divide(const SizedBox(
                                                          width: 12.0)),
                                                    ),
                                                  ].divide(
                                                      const SizedBox(height: 16.0)),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        _buildSectionCard(
                                          context: context,
                                          title: 'Détails du lot',
                                          child: Center(
                                            child: Text(
                                              widget.lot!.name,
                                              textAlign: TextAlign.center,
                                              style: FlutterFlowTheme.of(context)
                                                  .titleLarge
                                                  .override(
                                                    font: GoogleFonts.interTight(
                                                      fontWeight: FontWeight.w500,
                                                      fontStyle: FlutterFlowTheme.of(context).titleLarge.fontStyle,
                                                    ),
                                                    color: const Color(0xFF2D2A72),
                                                    letterSpacing: 0.0,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                            ),
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
      },
    );
  }
}

