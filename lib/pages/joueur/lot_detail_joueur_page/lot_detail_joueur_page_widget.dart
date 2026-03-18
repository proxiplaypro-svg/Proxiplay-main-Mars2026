import '/backend/backend.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/components/update_horaire_card_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
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
  static const Color _premiumAccent = Color(0xFFA0134D);
  static const Color _premiumTint = Color(0xFFFFF1F6);

  late LotDetailJoueurPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  Future<void> _openAddressInGoogleMaps(EnseignesRecord enseigne) async {
    final address =
        '${enseigne.address}, ${enseigne.areaCode} ${enseigne.city}'.trim();
    final mapsUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
    );
    await launchUrl(
      mapsUri,
      mode: LaunchMode.externalApplication,
    );
  }

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
            backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(100.0),
              child: AppBar(
                automaticallyImplyLeading: false,
                actions: const [],
                flexibleSpace: FlexibleSpaceBar(
                  title: Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 14.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 8.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    12.0, 0.0, 0.0, 0.0),
                                child: FlutterFlowIconButton(
                                  borderColor: Colors.transparent,
                                  borderRadius: 30.0,
                                  borderWidth: 1.0,
                                  buttonSize: 50.0,
                                  icon: Icon(
                                    Icons.chevron_left_rounded,
                                    color: FlutterFlowTheme.of(context)
                                        .primaryText,
                                    size: 30.0,
                                  ),
                                  onPressed: () async {
                                    context.pop();
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    4.0, 0.0, 0.0, 0.0),
                                child: Text(
                                  'Mes lots',
                                  style: FlutterFlowTheme.of(context)
                                      .headlineMedium
                                      .override(
                                        font: GoogleFonts.interTight(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .headlineMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .headlineMedium
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        fontSize: 22.0,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .headlineMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .headlineMedium
                                            .fontStyle,
                                      ),
                                ),
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
                      alignment: const Alignment(1.0, -1.0),
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
	                                        Container(
	                                          width:
	                                              MediaQuery.sizeOf(context).width *
	                                                  1.0,
	                                          decoration: BoxDecoration(
	                                            color: FlutterFlowTheme.of(context)
	                                                .secondaryBackground,
	                                            borderRadius:
	                                                BorderRadius.circular(20.0),
	                                            border: Border.all(
	                                              color: _premiumAccent.withValues(
	                                                  alpha: 0.10),
	                                              width: 1.0,
	                                            ),
	                                            boxShadow: [
	                                              BoxShadow(
	                                                color: _premiumAccent.withValues(
	                                                    alpha: 0.06),
	                                                blurRadius: 18.0,
	                                                offset:
	                                                    const Offset(0.0, 8.0),
	                                              ),
	                                            ],
	                                          ),
	                                          child: Padding(
	                                            padding:
	                                                const EdgeInsetsDirectional.fromSTEB(
	                                                    20.0, 20.0, 20.0, 20.0),
	                                            child: Column(
	                                              mainAxisSize: MainAxisSize.max,
	                                              children: [
	                                                Text(
	                                                  'Code de récupération',
	                                                  textAlign: TextAlign.center,
	                                                  style: FlutterFlowTheme.of(
	                                                          context)
	                                                      .headlineMedium
	                                                      .override(
	                                                        font: GoogleFonts
	                                                            .interTight(
	                                                          fontWeight:
	                                                              FontWeight.w700,
	                                                          fontStyle:
	                                                              FlutterFlowTheme.of(
	                                                                      context)
	                                                                  .headlineMedium
	                                                                  .fontStyle,
	                                                        ),
	                                                        color: FlutterFlowTheme.of(
	                                                                context)
	                                                            .primaryText,
	                                                        letterSpacing: 0.0,
	                                                        fontWeight:
	                                                            FontWeight.w700,
	                                                      ),
	                                                ),
	                                                if (!widget.lot!.claimed) ...[
	                                                  const SizedBox(height: 16.0),
	                                                  Container(
	                                                    width: double.infinity,
	                                                    decoration: BoxDecoration(
	                                                      color: _premiumTint,
	                                                      borderRadius:
	                                                          BorderRadius.circular(
	                                                              16.0),
	                                                      border: Border.all(
	                                                        color: _premiumAccent,
	                                                        width: 1.5,
	                                                      ),
	                                                    ),
	                                                    child: Padding(
	                                                      padding:
	                                                          const EdgeInsets.all(
	                                                              12.0),
	                                                      child: Text(
	                                                        widget.lot!.claimCode,
	                                                        textAlign:
	                                                            TextAlign.center,
	                                                        style: FlutterFlowTheme
	                                                                .of(context)
	                                                            .displaySmall
	                                                            .override(
	                                                              font: GoogleFonts
	                                                                  .interTight(
	                                                                fontWeight:
	                                                                    FontWeight
	                                                                        .w800,
	                                                                fontStyle: FlutterFlowTheme.of(
	                                                                        context)
	                                                                    .displaySmall
	                                                                    .fontStyle,
	                                                              ),
	                                                              color:
	                                                                  _premiumAccent,
	                                                              letterSpacing:
	                                                                  1.0,
	                                                              fontWeight:
	                                                                  FontWeight
	                                                                      .w800,
	                                                            ),
	                                                      ),
	                                                    ),
	                                                  ),
	                                                  const SizedBox(height: 10.0),
	                                                  Text(
	                                                    'Présentez ce code au commerçant',
	                                                    textAlign: TextAlign.center,
	                                                    style: FlutterFlowTheme.of(
	                                                            context)
	                                                        .bodyMedium
	                                                        .override(
	                                                          font: GoogleFonts
	                                                              .inter(
	                                                            fontWeight:
	                                                                FontWeight.w500,
	                                                            fontStyle: FlutterFlowTheme.of(
	                                                                    context)
	                                                                .bodyMedium
	                                                                .fontStyle,
	                                                          ),
	                                                          color: FlutterFlowTheme
	                                                                  .of(context)
	                                                              .secondaryText,
	                                                          letterSpacing: 0.0,
	                                                        ),
	                                                  ),
	                                                ] else ...[
	                                                  const SizedBox(height: 16.0),
	                                                  Container(
	                                                    width: double.infinity,
	                                                    decoration: BoxDecoration(
	                                                      color: _premiumTint,
	                                                      borderRadius:
	                                                          BorderRadius.circular(
	                                                              14.0),
	                                                    ),
	                                                    child: Padding(
	                                                      padding:
	                                                          const EdgeInsetsDirectional
	                                                              .fromSTEB(12.0,
	                                                                  16.0, 12.0,
	                                                                  16.0),
	                                                      child: Text(
	                                                        'Lot récupéré',
	                                                        textAlign:
	                                                            TextAlign.center,
	                                                        style: FlutterFlowTheme
	                                                                .of(context)
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
	                                                              color:
	                                                                  _premiumAccent,
	                                                              letterSpacing:
	                                                                  0.0,
	                                                              fontWeight:
	                                                                  FontWeight
	                                                                      .w600,
	                                                            ),
	                                                      ),
	                                                    ),
	                                                  ),
	                                                ],
	                                              ],
	                                            ),
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
	                                                    BorderRadius.circular(20.0),
	                                                border: Border.all(
	                                                  color: _premiumAccent
	                                                      .withValues(alpha: 0.08),
	                                                  width: 1.0,
	                                                ),
	                                                boxShadow: [
	                                                  BoxShadow(
	                                                    color: _premiumAccent
	                                                        .withValues(
	                                                            alpha: 0.05),
	                                                    blurRadius: 18.0,
	                                                    offset:
	                                                        const Offset(0.0, 8.0),
	                                                  ),
	                                                ],
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
                                                        height: 40.0,
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
	                                                        color: _premiumTint,
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
	                                                                  color:
	                                                                      _premiumAccent,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleSmall
                                                                      .fontWeight,
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
	                                                          color:
	                                                              _premiumAccent,
                                                          width: 1.0,
                                                        ),
                                                      ),
                                                    ),
	                                                    InkWell(
	                                                      splashColor:
	                                                          Colors.transparent,
	                                                      focusColor:
	                                                          Colors.transparent,
	                                                      hoverColor:
	                                                          Colors.transparent,
	                                                      highlightColor:
	                                                          Colors.transparent,
	                                                      onTap: () async {
	                                                        await _openAddressInGoogleMaps(
	                                                          containerEnseignesRecord,
	                                                        );
	                                                      },
	                                                      child: Container(
	                                                        width: double.infinity,
	                                                        decoration:
	                                                            const BoxDecoration(),
	                                                        child: Row(
	                                                          crossAxisAlignment:
	                                                              CrossAxisAlignment
	                                                                  .start,
	                                                          children: [
	                                                            const Icon(
	                                                              Icons.location_on,
	                                                              color: _premiumAccent,
	                                                              size: 22.0,
	                                                            ),
	                                                            Expanded(
	                                                              child: Text(
	                                                                '${containerEnseignesRecord.address}, ${containerEnseignesRecord.areaCode} ${containerEnseignesRecord.city}',
	                                                                softWrap: true,
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
	                                                                      color:
	                                                                          _premiumAccent,
	                                                                      decoration:
	                                                                          TextDecoration
	                                                                              .underline,
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
	                                                                    ),
	                                                              ),
	                                                            ),
	                                                          ].divide(const SizedBox(
	                                                              width: 10.0)),
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
                                                                            4.0),
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
                                                                              4.0,
                                                                              8.0,
                                                                              4.0),
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
                                        Container(
                                          width:
                                              MediaQuery.sizeOf(context).width *
                                                  1.0,
                                          decoration: BoxDecoration(
                                            color: FlutterFlowTheme.of(context)
                                                .secondaryBackground,
                                            borderRadius:
                                                BorderRadius.circular(16.0),
                                          ),
                                          child: Padding(
                                            padding:
                                                const EdgeInsetsDirectional.fromSTEB(
                                                    20.0, 20.0, 20.0, 20.0),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.max,
                                              children: [
                                                Text(
                                                  'Détails du lot',
                                                  style: FlutterFlowTheme.of(
                                                          context)
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
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Lot : ',
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
                                                    Expanded(
                                                      child: Text(
                                                        widget.lot!.name,
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
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .primary,
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
                                                    ),
                                                  ],
                                                ),
                                              ].divide(const SizedBox(height: 16.0)),
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
