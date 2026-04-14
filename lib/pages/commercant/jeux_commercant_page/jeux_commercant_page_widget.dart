import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/components/custom_nav_bar_commercant2_widget.dart';
import '/components/list_empty_component_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/utils/game_metrics.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'jeux_commercant_page_model.dart';
export 'jeux_commercant_page_model.dart';

/// je veux un formulaire pour ajouter un jeu
class JeuxCommercantPageWidget extends StatefulWidget {
  const JeuxCommercantPageWidget({super.key});

  static String routeName = 'JeuxCommercantPage';
  static String routePath = 'jeuxCommercantPage';

  @override
  State<JeuxCommercantPageWidget> createState() =>
      _JeuxCommercantPageWidgetState();
}

class _JeuxCommercantPageWidgetState extends State<JeuxCommercantPageWidget> {
  late JeuxCommercantPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => JeuxCommercantPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'JeuxCommercantPage'});
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  Future<void> _restartGame(GamesRecord game) async {
    if (game.enseigneId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enseigne introuvable pour ce jeu.')),
      );
      return;
    }

    context.pushNamed(
      AddGameCommercantPageWidget.routeName,
      queryParameters: {
        'enseigneRef': serializeParam(
          game.enseigneId,
          ParamType.DocumentReference,
        ),
        'enseigne': serializeParam(
          game.enseigneName,
          ParamType.String,
        ),
      }.withoutNulls,
      extra: <String, dynamic>{
        'templateGame': game,
      },
    );
  }

  Future<void> _deleteGame(GamesRecord game) async {
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Supprimer le jeu'),
              content: const Text(
                'Retirer ce jeu de la liste uniquement ? Les statistiques sont conserv\u00E9es.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Annuler'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Supprimer'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldDelete) return;

    try {
      await game.reference.update({
        'hidden_from_merchant_stats': true,
        'updated_time': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jeu retir\u00E9 de la liste.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suppression impossible.')),
      );
    }
  }

  bool _isGameActive(GamesRecord game) {
    final now = getCurrentTimestamp;
    final start = game.startDate;
    final end = game.endDate;
    if (end == null) return false;
    if (game.snapshotData['hidden_from_merchant_stats'] == true) return false;
    final afterStart = start == null || !now.isBefore(start);
    return afterStart && now.isBefore(end);
  }

  GamesRecord? _pickCurrentGame(List<GamesRecord> games) {
    final activeGames = games.where(_isGameActive).toList()
      ..sort((a, b) {
        final aDate = a.endDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.endDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aDate.compareTo(bDate);
      });
    return activeGames.isEmpty ? null : activeGames.first;
  }

  List<GamesRecord> _finishedGames(List<GamesRecord> games) {
    final now = getCurrentTimestamp;
    return games
      .where((g) => g.endDate != null && !g.endDate!.isAfter(now))
      .toList()
      ..sort((a, b) {
        final aDate = a.endDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.endDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
  }

  Widget _statusBadge(bool isActive) {
    final bg = isActive ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0);
    final fg = isActive ? const Color(0xFF2E7D32) : const Color(0xFFE65100);
    final label = isActive ? 'Actif' : 'Termin\u00E9';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14.0),
      ),
      child: Text(
        label,
        style: FlutterFlowTheme.of(context).bodySmall.override(
              font: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
              ),
              color: fg,
              letterSpacing: 0.0,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16.0, color: FlutterFlowTheme.of(context).primary),
        const SizedBox(width: 4.0),
        Text(
          text,
          style: FlutterFlowTheme.of(context).bodySmall.override(
                font: GoogleFonts.inter(
                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                ),
                letterSpacing: 0.0,
              ),
        ),
      ],
    );
  }

  Future<void> _openDetails(GamesRecord game) async {
    if (game.enseigneId == null) return;
    final enseigne = await EnseignesRecord.getDocumentOnce(game.enseigneId!);
    if (!mounted) return;
    context.pushNamed(
      JeuDetailCommercantPageWidget.routeName,
      queryParameters: {
        'gameDoc': serializeParam(game, ParamType.Document),
        'enseigneDoc': serializeParam(enseigne, ParamType.Document),
      }.withoutNulls,
      extra: <String, dynamic>{'gameDoc': game, 'enseigneDoc': enseigne},
    );
  }

  Widget _statStyleCard(
    GamesRecord game, {
    required bool isActive,
    required bool showActions,
  }) {
    final startText = game.startDate != null
        ? dateTimeFormat('d/M/y', game.startDate,
            locale: FFLocalizations.of(context).languageCode)
        : '-';
    final endText = game.endDate != null
        ? dateTimeFormat('d/M/y', game.endDate,
            locale: FFLocalizations.of(context).languageCode)
        : '-';
    return InkWell(
      onTap: () async => _openDetails(game),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10.0),
                child: Image.network(game.photo, width: 88.0, height: 88.0, fit: BoxFit.cover),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            game.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FlutterFlowTheme.of(context).titleSmall,
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        _statusBadge(isActive),
                      ],
                    ),
                    const SizedBox(height: 6.0),
                    Text(
                      'Du $startText au $endText',
                      style: FlutterFlowTheme.of(context).bodySmall.override(
                            font: GoogleFonts.inter(
                              fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                              fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                            ),
                            color: FlutterFlowTheme.of(context).secondaryText,
                            letterSpacing: 0.0,
                          ),
                    ),
                    const SizedBox(height: 8.0),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _chip(Icons.remove_red_eye,
                              'Ouvertures fiche ${gameViewsDisplayValue(game)}'),
                          const SizedBox(width: 12.0),
                          _chip(Icons.sports_esports_rounded, 'Participations ${game.participations}'),
                          const SizedBox(width: 12.0),
                          _chip(Icons.star_rounded, 'Favoris ${game.favorites}'),
                        ],
                      ),
                    ),
                    if (showActions) ...[
                      const SizedBox(height: 8.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FFButtonWidget(
                            onPressed: () async => _restartGame(game),
                            text: 'Relancer',
                            options: FFButtonOptions(
                              height: 30.0,
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              color: FlutterFlowTheme.of(context).primary,
                              textStyle: FlutterFlowTheme.of(context).bodySmall.override(
                                    font: GoogleFonts.inter(fontWeight: FontWeight.w700),
                                    color: FlutterFlowTheme.of(context).info,
                                    letterSpacing: 0.0,
                                  ),
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          FFButtonWidget(
                            onPressed: () async => _deleteGame(game),
                            text: 'Supprimer',
                            options: FFButtonOptions(
                              height: 30.0,
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              color: const Color(0xFFFFF3E0),
                              textStyle: FlutterFlowTheme.of(context).bodySmall.override(
                                    font: GoogleFonts.inter(fontWeight: FontWeight.w700),
                                    color: const Color(0xFFE65100),
                                    letterSpacing: 0.0,
                                  ),
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: const BorderSide(color: Color(0xFFE65100), width: 1.0),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
            preferredSize: const Size.fromHeight(60.0),
            child: AppBar(
              backgroundColor: Colors.transparent,
              automaticallyImplyLeading: false,
              actions: const [],
              flexibleSpace: FlexibleSpaceBar(
                title: Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    InkWell(
                      splashColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onTap: () async {
                        if (Navigator.of(context).canPop()) {
                          context.pop();
                        }
                        context.pushNamed(HomeCommercantPageWidget.routeName);
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: SvgPicture.asset(
                          'assets/images/logo_D_secondaire_sans_html_avec_couleurs.svg',
                          width: 200.0,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
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
                titlePadding:
                    const EdgeInsetsDirectional.fromSTEB(0.0, 10.0, 0.0, 0.0),
              ),
              toolbarHeight: 60.0,
            ),
          ),
          body: SafeArea(
            top: true,
            child: Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  fit: BoxFit.cover,
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
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(20.0, 20.0, 20.0, 0.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Container(
                            decoration: const BoxDecoration(),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.max,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const SizedBox.shrink(),
                              FutureBuilder<List<EnseignesRecord>>(
                                future: queryEnseignesRecordOnce(
                                  queryBuilder: (enseignesRecord) =>
                                      enseignesRecord.where(
                                    'owner',
                                    isEqualTo: currentUserReference,
                                  ),
                                  singleRecord: true,
                                ),
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
                                  List<EnseignesRecord>
                                      conditionalBuilderEnseignesRecordList =
                                      snapshot.data!;
                                  final conditionalBuilderEnseignesRecord =
                                      conditionalBuilderEnseignesRecordList
                                              .isNotEmpty
                                          ? conditionalBuilderEnseignesRecordList
                                              .first
                                          : null;

                                  return Builder(
                                    builder: (context) {
                                      if (conditionalBuilderEnseignesRecord !=
                                          null) {
                                        return FFButtonWidget(
                                          onPressed: () async {
                                            context.pushNamed(
                                              AddGameCommercantPageWidget
                                                  .routeName,
                                              queryParameters: {
                                                'enseigneRef': serializeParam(
                                                  conditionalBuilderEnseignesRecord
                                                      .reference,
                                                  ParamType.DocumentReference,
                                                ),
                                                'enseigne': serializeParam(
                                                  conditionalBuilderEnseignesRecord
                                                      .name,
                                                  ParamType.String,
                                                ),
                                              }.withoutNulls,
                                            );
                                          },
                                          text: 'Ajouter un jeu',
                                          options: FFButtonOptions(
                                            height: 40.0,
                                            padding:
                                                const EdgeInsetsDirectional.fromSTEB(
                                                    16.0, 0.0, 16.0, 0.0),
                                            iconPadding:
                                                const EdgeInsetsDirectional.fromSTEB(
                                                    0.0, 0.0, 0.0, 0.0),
                                            color: FlutterFlowTheme.of(context)
                                                .primary,
                                            textStyle: FlutterFlowTheme.of(
                                                    context)
                                                .titleSmall
                                                .override(
                                                  font: GoogleFonts.interTight(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .titleSmall
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .titleSmall
                                                            .fontStyle,
                                                  ),
                                                  color: Colors.white,
                                                  letterSpacing: 0.0,
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .titleSmall
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .titleSmall
                                                          .fontStyle,
                                                ),
                                            elevation: 0.0,
                                            borderRadius:
                                                BorderRadius.circular(8.0),
                                          ),
                                        );
                                      } else {
                                        return FFButtonWidget(
                                          onPressed: () async {
                                            context.pushNamed(
                                                AddEnseigneCommercantPageWidget
                                                    .routeName);
                                          },
                                          text: 'Ajouter une enseigne',
                                          options: FFButtonOptions(
                                            height: 40.0,
                                            padding:
                                                const EdgeInsetsDirectional.fromSTEB(
                                                    16.0, 0.0, 16.0, 0.0),
                                            iconPadding:
                                                const EdgeInsetsDirectional.fromSTEB(
                                                    0.0, 0.0, 0.0, 0.0),
                                            color: FlutterFlowTheme.of(context)
                                                .primary,
                                            textStyle: FlutterFlowTheme.of(
                                                    context)
                                                .titleSmall
                                                .override(
                                                  font: GoogleFonts.interTight(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .titleSmall
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .titleSmall
                                                            .fontStyle,
                                                  ),
                                                  color: Colors.white,
                                                  letterSpacing: 0.0,
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .titleSmall
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .titleSmall
                                                          .fontStyle,
                                                ),
                                            elevation: 0.0,
                                            borderRadius:
                                                BorderRadius.circular(8.0),
                                          ),
                                        );
                                      }
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                          Expanded(
                            flex: 1,
                            child: Container(
                              width: double.infinity,
                              decoration: const BoxDecoration(),
                              child: StreamBuilder<List<GamesRecord>>(
                                stream: queryGamesRecord(
                                  queryBuilder: (gamesRecord) =>
                                      gamesRecord.where(
                                    'create_by',
                                    isEqualTo: currentUserReference,
                                  ),
                                  limit: 15,
                                ),
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
                                  List<GamesRecord> listViewGamesRecordList =
                                      snapshot.data!
                                          .where((g) =>
                                              g.snapshotData[
                                                  'hidden_from_merchant_stats'] !=
                                              true)
                                          .toList();
                                  if (listViewGamesRecordList.isEmpty) {
                                    return const Center(
                                      child: ListEmptyComponentWidget(
                                        title: 'Aucun Jeu',
                                        description:
                                            'Votre liste est actuellement vide',
                                      ),
                                    );
                                  }

                                  final currentGame = _pickCurrentGame(
                                      listViewGamesRecordList);
                                  final finishedGames = _finishedGames(
                                      listViewGamesRecordList);

                                  final useStatLikeLayout =
                                      _model.hashCode != -1;
                                  if (useStatLikeLayout) {
                                    return ListView(
                                      padding: EdgeInsets.zero,
                                      children: [
                                      if (currentGame != null) ...[
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'Jeu en cours',
                                            style: FlutterFlowTheme.of(context)
                                                .titleMedium
                                                .override(
                                                  font: GoogleFonts.interTight(
                                                    fontWeight: FontWeight.w700,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .titleMedium
                                                            .fontStyle,
                                                  ),
                                                  letterSpacing: 0.0,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(height: 10.0),
                                        _statStyleCard(
                                          currentGame,
                                          isActive: true,
                                          showActions: false,
                                        ),
                                        const SizedBox(height: 14.0),
                                      ],
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'Jeux termin\u00E9s',
                                          style: FlutterFlowTheme.of(context)
                                              .titleMedium
                                              .override(
                                                font: GoogleFonts.interTight(
                                                  fontWeight: FontWeight.w700,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .titleMedium
                                                          .fontStyle,
                                                ),
                                                letterSpacing: 0.0,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(height: 10.0),
                                      if (finishedGames.isEmpty)
                                        const ListEmptyComponentWidget(
                                          title: 'Aucun jeu termin\u00E9',
                                          description:
                                              'Vos jeux termin\u00E9s appara\u00EEtront ici',
                                        )
                                      else
                                        ...finishedGames.map(
                                          (game) => Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 10.0),
                                            child: _statStyleCard(
                                              game,
                                              isActive: false,
                                              showActions: true,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }

                                  return ListView.separated(
                                    padding: EdgeInsets.zero,
                                    scrollDirection: Axis.vertical,
                                    itemCount: listViewGamesRecordList.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 10.0),
                                    itemBuilder: (context, listViewIndex) {
                                      final listViewGamesRecord =
                                          listViewGamesRecordList[
                                              listViewIndex];
                                      return StreamBuilder<EnseignesRecord>(
                                        stream: EnseignesRecord.getDocument(
                                            listViewGamesRecord.enseigneId!),
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

                                          return InkWell(
                                            splashColor: Colors.transparent,
                                            focusColor: Colors.transparent,
                                            hoverColor: Colors.transparent,
                                            highlightColor: Colors.transparent,
                                            onTap: () async {
                                              _model.enseigneRef =
                                                  await EnseignesRecord
                                                      .getDocumentOnce(
                                                          listViewGamesRecord
                                                              .enseigneId!);
                                              if (!context.mounted) {
                                                return;
                                              }

                                              context.pushNamed(
                                                JeuDetailCommercantPageWidget
                                                    .routeName,
                                                queryParameters: {
                                                  'gameDoc': serializeParam(
                                                    listViewGamesRecord,
                                                    ParamType.Document,
                                                  ),
                                                  'enseigneDoc': serializeParam(
                                                    containerEnseignesRecord,
                                                    ParamType.Document,
                                                  ),
                                                }.withoutNulls,
                                                extra: <String, dynamic>{
                                                  'gameDoc': listViewGamesRecord,
                                                  'enseigneDoc':
                                                      containerEnseignesRecord,
                                                  kTransitionInfoKey:
                                                      const TransitionInfo(
                                                    hasTransition: true,
                                                    transitionType:
                                                        PageTransitionType.fade,
                                                    duration: Duration(
                                                        milliseconds: 0),
                                                  ),
                                                },
                                              );

                                              safeSetState(() {});
                                            },
                                            child: Material(
                                              color: Colors.transparent,
                                              elevation: 1.0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20.0),
                                              ),
                                              child: Container(
                                                width: 100.0,
                                                height: 130.0,
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
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    Expanded(
                                                      flex: 1,
                                                      child: Container(
                                                        height:
                                                            double.infinity,
                                                        decoration:
                                                            const BoxDecoration(),
                                                        child: ClipRRect(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      8.0),
                                                          child: Image.network(
                                                            listViewGamesRecord
                                                                .photo,
                                                            width: 100.0,
                                                            height: 130.0,
                                                            fit: BoxFit.cover,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 2,
                                                      child: Container(
                                                        decoration:
                                                            const BoxDecoration(),
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets.all(
                                                                  10.0),
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
                                                                style: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .override(
                                                                      font: GoogleFonts
                                                                          .inter(
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .bodyMedium
                                                                            .fontStyle,
                                                                      ),
                                                                      letterSpacing:
                                                                          0.0,
                                                                      fontWeight:
                                                                          FontWeight.w600,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodyMedium
                                                                          .fontStyle,
                                                                    ),
                                                              ),
                                                              Expanded(
                                                                child: Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .max,
                                                                  children: [
                                                                    Expanded(
                                                                      child:
                                                                          Column(
                                                                        mainAxisSize:
                                                                            MainAxisSize.max,
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.start,
                                                                        crossAxisAlignment:
                                                                            CrossAxisAlignment.start,
                                                                        children:
                                                                            [
                                                                          Row(
                                                                            mainAxisSize:
                                                                                MainAxisSize.max,
                                                                            children: [
                                                                              Icon(
                                                                                Icons.remove_red_eye,
                                                                                color: FlutterFlowTheme.of(context).primaryText,
                                                                                size: 18.0,
                                                                              ),
                                                                              Text(
                                                                                'Ouvertures fiche : ',
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
                                                                                gameViewsDisplayValue(
                                                                                  listViewGamesRecord,
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
                                                                          Row(
                                                                            mainAxisSize:
                                                                                MainAxisSize.max,
                                                                            children: [
                                                                              Icon(
                                                                                Icons.person_rounded,
                                                                                color: FlutterFlowTheme.of(context).primaryText,
                                                                                size: 18.0,
                                                                              ),
                                                                              Text(
                                                                                'Joueurs : ',
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
                                                                                listViewGamesRecord.participations.toString(),
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
                                                                        ].divide(
                                                                                const SizedBox(height: 10.0)),
                                                                      ),
                                                                    ),
                                                                    Expanded(
                                                                      child:
                                                                          Column(
                                                                        mainAxisSize:
                                                                            MainAxisSize.max,
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.start,
                                                                        children: [
                                                                          Row(
                                                                            mainAxisSize:
                                                                                MainAxisSize.max,
                                                                            children: [
                                                                              Icon(
                                                                                Icons.star_rounded,
                                                                                color: FlutterFlowTheme.of(context).primaryText,
                                                                                size: 18.0,
                                                                              ),
                                                                              Text(
                                                                                'Favoris : ',
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
                                                                                listViewGamesRecord.favorites.toString(),
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
                                                                        ],
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                              Row(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .end,
                                                                children: [
                                                                  FFButtonWidget(
                                                                    onPressed:
                                                                        () async {
                                                                      await _restartGame(
                                                                          listViewGamesRecord);
                                                                    },
                                                                    text:
                                                                        'Relancer',
                                                                    options:
                                                                        FFButtonOptions(
                                                                      height:
                                                                          28.0,
                                                                      padding: const EdgeInsetsDirectional.fromSTEB(
                                                                          10.0,
                                                                          0.0,
                                                                          10.0,
                                                                          0.0),
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primary,
                                                                      textStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodySmall
                                                                          .override(
                                                                            font:
                                                                                GoogleFonts.inter(
                                                                              fontWeight: FontWeight.w700,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                            ),
                                                                            color:
                                                                                FlutterFlowTheme.of(context).info,
                                                                            letterSpacing:
                                                                                0.0,
                                                                            fontWeight:
                                                                                FontWeight.w700,
                                                                          ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              14.0),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                      width:
                                                                          8.0),
                                                                  FFButtonWidget(
                                                                    onPressed:
                                                                        () async {
                                                                      await _deleteGame(
                                                                          listViewGamesRecord);
                                                                    },
                                                                    text:
                                                                        'Supprimer',
                                                                    options:
                                                                        FFButtonOptions(
                                                                      height:
                                                                          28.0,
                                                                      padding: const EdgeInsetsDirectional.fromSTEB(
                                                                          10.0,
                                                                          0.0,
                                                                          10.0,
                                                                          0.0),
                                                                      color: const Color(
                                                                          0xFFFFF3E0),
                                                                      textStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodySmall
                                                                          .override(
                                                                            font:
                                                                                GoogleFonts.inter(
                                                                              fontWeight: FontWeight.w700,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                            ),
                                                                            color:
                                                                                const Color(0xFFE65100),
                                                                            letterSpacing:
                                                                                0.0,
                                                                            fontWeight:
                                                                                FontWeight.w700,
                                                                          ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              14.0),
                                                                      borderSide:
                                                                          const BorderSide(
                                                                        color: Color(
                                                                            0xFFE65100),
                                                                        width:
                                                                            1.0,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ].divide(const SizedBox(
                                                                height: 5.0)),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        ].divide(const SizedBox(height: 20.0)),
                      ),
                    ),
                  ),
                  wrapWithModel(
                    model: _model.customNavBarCommercant2Model,
                    updateCallback: () => safeSetState(() {}),
                    child: const CustomNavBarCommercant2Widget(
                      indexActive: 2,
                    ),
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


