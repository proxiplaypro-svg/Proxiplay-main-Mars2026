import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/components/custom_nav_bar_commercant2_widget.dart';
import '/components/list_empty_component_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/utils/game_metrics.dart';
import '/utils/merchant_game_visibility.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'stat_commercant_page_model.dart';
export 'stat_commercant_page_model.dart';

const bool kShowUniquePlayersStat = false;

class StatCommercantPageWidget extends StatefulWidget {
  const StatCommercantPageWidget({super.key});

  static String routeName = 'StatCommercantPage';
  static String routePath = 'statCommercantPage';

  @override
  State<StatCommercantPageWidget> createState() =>
      _StatCommercantPageWidgetState();
}

class _StatCommercantPageWidgetState extends State<StatCommercantPageWidget>
    with TickerProviderStateMixin {
  late StatCommercantPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => StatCommercantPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'StatCommercantPage'});
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Stream<List<GamesRecord>> _merchantGamesStream() {
    return queryGamesRecord(
      queryBuilder: (gamesRecord) => gamesRecord
          .where(
            'create_by',
            isEqualTo: currentUserReference,
          ),
      limit: 500,
    );
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  int _readUniquePlayers(GamesRecord game) {
    final data = game.snapshotData;
    return _readInt(
      data['unique_players_count'] ??
          data['stats_uniquePlayers'] ??
          data['uniquePlayersCount'] ??
          data['statsUniquePlayers'] ??
          data['unique_players'],
    );
  }

  bool _isUniquePlayersAvailable(GamesRecord game) {
    final data = game.snapshotData;
    return data['uniquePlayersEnabled'] == true ||
        data['uniquePlayersEnabledAt'] != null ||
        data['enabledAtUniquePlayers'] != null ||
        data['enabled_at_unique_players'] != null ||
        data['unique_players_count'] != null ||
        data['stats_uniquePlayers'] != null ||
        data['uniquePlayersCount'] != null ||
        data['statsUniquePlayers'] != null ||
        data['unique_players'] != null;
  }

  DateTime get _startOfToday {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isCreatedFromToday(GamesRecord game) {
    final createdAt = game.createdTime;
    if (createdAt == null) {
      return false;
    }
    return !createdAt.isBefore(_startOfToday);
  }

  bool _shouldShowUniquePlayers(GamesRecord game) {
    return _isCreatedFromToday(game) && _isUniquePlayersAvailable(game);
  }

  bool _isGameActive(GamesRecord game) {
    return isMerchantActiveGame(game);
  }

  List<GamesRecord> _activeGames(List<GamesRecord> games) {
    return games.where(_isGameActive).toList()
      ..sort((a, b) {
        final aDate = a.endDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.endDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aDate.compareTo(bDate);
      });
  }

  List<GamesRecord> _normalizeFinishedGames(List<GamesRecord> input) {
    final games = [...input];
    final now = getCurrentTimestamp;
    games.removeWhere((g) {
      final isHidden = g.snapshotData['hidden_from_merchant_stats'] == true;
      final isFinished = g.endDate != null && !g.endDate!.isAfter(now);
      return isHidden || !isFinished;
    });
    games.sort((a, b) {
      final aDate = a.endDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.endDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return games;
  }

  int _readFollowers(EnseignesRecord enseigne) {
    final data = enseigne.snapshotData;
    final dynamic rawValue = data['favoritesCount'] ??
        data['favorites'] ??
        data['favorisCount'] ??
        data['favoris'] ??
        data['stats_favorites'] ??
        data['stats_favoris'];

    if (rawValue is List) return rawValue.length;
    return _readInt(rawValue);
  }

  Stream<int> _followersStream() {
    if (currentUserReference == null) {
      return Stream<int>.value(0);
    }

    return queryEnseignesRecord(
      queryBuilder: (enseignesRecord) => enseignesRecord.where(
        'owner',
        isEqualTo: currentUserReference,
      ),
      limit: 100,
    ).map(
      (enseignes) => enseignes.fold<int>(0, (sum, e) => sum + _readFollowers(e)),
    );
  }

  Widget _buildGlobalLine({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.0),
      ),
      child: Row(
        children: [
          Container(
            width: 28.0,
            height: 28.0,
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9.0),
            ),
            child: Icon(
              icon,
              size: 16.0,
              color: FlutterFlowTheme.of(context).primary,
            ),
          ),
          const SizedBox(width: 8.0),
          Text(
            value,
            style: FlutterFlowTheme.of(context).titleMedium.override(
                  font: GoogleFonts.interTight(
                    fontWeight: FontWeight.w700,
                    fontStyle: FlutterFlowTheme.of(context).titleMedium.fontStyle,
                  ),
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FlutterFlowTheme.of(context).bodySmall.override(
                    font: GoogleFonts.inter(
                      fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                      fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                    ),
                    color: FlutterFlowTheme.of(context).secondaryText,
                    letterSpacing: 0.0,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameStatusBadge(bool isActive) {
    final background = isActive ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0);
    final textColor = isActive ? const Color(0xFF2E7D32) : const Color(0xFFE65100);
    final label = isActive ? 'Actif' : 'Termin\u00E9';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14.0),
      ),
      child: Text(
        label,
        style: FlutterFlowTheme.of(context).bodySmall.override(
              font: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
              ),
              color: textColor,
              letterSpacing: 0.0,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _statChip(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16.0, color: FlutterFlowTheme.of(context).primary),
        const SizedBox(width: 4.0),
        Text(
          value,
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

  Widget _buildGameCard(
    GamesRecord game, {
    bool isActiveCard = false,
    bool showActions = true,
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
      splashColor: Colors.transparent,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: () async {
        final enseigne = await EnseignesRecord.getDocumentOnce(game.enseigneId!);
        if (!mounted) return;
        context.pushNamed(
          JeuDetailCommercantPageWidget.routeName,
          queryParameters: {
            'gameDoc': serializeParam(game, ParamType.Document),
            'enseigneDoc': serializeParam(enseigne, ParamType.Document),
          }.withoutNulls,
          extra: <String, dynamic>{
            'gameDoc': game,
            'enseigneDoc': enseigne,
          },
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10.0,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10.0),
                child: Image.network(
                  game.photo,
                  width: 88.0,
                  height: 88.0,
                  fit: BoxFit.cover,
                ),
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
                            style: FlutterFlowTheme.of(context).titleSmall.override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontStyle,
                                  ),
                                  letterSpacing: 0.0,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        _buildGameStatusBadge(isActiveCard),
                      ],
                    ),
                    const SizedBox(height: 6.0),
                    Text(
                      'Du $startText au $endText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FlutterFlowTheme.of(context).bodySmall.override(
                            font: GoogleFonts.inter(
                              fontWeight:
                                  FlutterFlowTheme.of(context).bodySmall.fontWeight,
                              fontStyle:
                                  FlutterFlowTheme.of(context).bodySmall.fontStyle,
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
                          _statChip(Icons.remove_red_eye,
                              'Ouvertures fiche ${gameViewsDisplayValue(game)}'),
                          const SizedBox(width: 12.0),
                          _statChip(Icons.sports_esports_rounded,
                              'Participations ${game.participations}'),
                          const SizedBox(width: 12.0),
                          _statChip(Icons.star_rounded, 'Favoris ${game.favorites}'),
                          if (kShowUniquePlayersStat &&
                              _shouldShowUniquePlayers(game))
                            ...[
                              const SizedBox(width: 12.0),
                              _statChip(Icons.person_rounded,
                                  'Joueurs ${_readUniquePlayers(game)}'),
                            ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    if (showActions)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FFButtonWidget(
                            onPressed: () async {
                              await _restartGame(game);
                            },
                            text: 'Relancer',
                            options: FFButtonOptions(
                              height: 30.0,
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              color: FlutterFlowTheme.of(context).primary,
                              textStyle: FlutterFlowTheme.of(context).bodySmall.override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .fontStyle,
                                    ),
                                    color: FlutterFlowTheme.of(context).info,
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.w700,
                                  ),
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          FFButtonWidget(
                            onPressed: () async {
                              await _deleteGame(game);
                            },
                            text: 'Supprimer',
                            options: FFButtonOptions(
                              height: 30.0,
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              color: const Color(0xFFFFF3E0),
                              textStyle: FlutterFlowTheme.of(context).bodySmall.override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .fontStyle,
                                    ),
                                    color: const Color(0xFFE65100),
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.w700,
                                  ),
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: const BorderSide(
                                color: Color(0xFFE65100),
                                width: 1.0,
                              ),
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
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ListEmptyComponentWidget(
            title: 'Aucun jeu termin\u00E9',
            description: 'Vos jeux termin\u00E9s appara\u00EEtront ici',
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentGameEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Text(
        'Aucun jeu en cours',
        style: FlutterFlowTheme.of(context).bodyMedium.override(
              font: GoogleFonts.inter(
                fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
              ),
              letterSpacing: 0.0,
            ),
      ),
    );
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
                'Retirer ce jeu de la liste des jeux termin\u00E9s uniquement ? Les statistiques sont conserv\u00E9es.',
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
            preferredSize: const Size.fromHeight(76.0),
            child: AppBar(
              backgroundColor: Colors.transparent,
              automaticallyImplyLeading: false,
              elevation: 0.0,
              centerTitle: true,
              title: InkWell(
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
                child: SvgPicture.asset(
                  'assets/images/logo_D_secondaire_sans_html_avec_couleurs.svg',
                  width: 190.0,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          body: SafeArea(
            top: true,
            child: Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  fit: BoxFit.cover,
                  alignment: const AlignmentDirectional(-1.0, 1.0),
                  image: Image.asset('assets/images/Background.png').image,
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20.0, 6.0, 20.0, 12.0),
                    child: Column(
                      children: [
                        Text(
                          'Statistiques',
                          style:
                              FlutterFlowTheme.of(context).headlineSmall.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FontWeight.w700,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .headlineSmall
                                          .fontStyle,
                                    ),
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 4.0),
                        Text(
                          'Suivi de performance de vos jeux',
                          textAlign: TextAlign.center,
                          style: FlutterFlowTheme.of(context).bodySmall.override(
                                font: GoogleFonts.inter(
                                  fontWeight:
                                      FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                  fontStyle:
                                      FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                ),
                                color: FlutterFlowTheme.of(context).secondaryText,
                                letterSpacing: 0.0,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6.0),
                  Expanded(
                    child: StreamBuilder<List<GamesRecord>>(
                      stream: _merchantGamesStream(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: SizedBox(
                              width: 50.0,
                              height: 50.0,
                              child: SizedBox.shrink(),
                            ),
                          );
                        }

                        final allGames = snapshot.data!;
                        final finishedGames = _normalizeFinishedGames(allGames);
                        final activeGames = _activeGames(allGames);
                        final totalViews = totalViewsDisplayValue(allGames);
                        final totalParticipations = allGames.fold<int>(
                            0, (sum, game) => sum + game.participations);
                        final widgets = <Widget>[
                          StreamBuilder<int>(
                            stream: _followersStream(),
                            builder: (context, followersSnapshot) {
                              final followers = followersSnapshot.data ?? 0;
                              return Column(
                                children: [
                                  _buildGlobalLine(
                                    icon: Icons.remove_red_eye,
                                    label: 'Clics sur vos jeux',
                                    value: totalViews,
                                  ),
                                  const SizedBox(height: 8.0),
                                  _buildGlobalLine(
                                    icon: Icons.sports_esports_rounded,
                                    label: 'Participations',
                                    value: totalParticipations.toString(),
                                  ),
                                  const SizedBox(height: 8.0),
                                  _buildGlobalLine(
                                    icon: Icons.storefront_rounded,
                                    label: 'Followers',
                                    value: followers.toString(),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 8.0),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              activeGames.length > 1
                                  ? 'Jeux en cours'
                                  : 'Jeu en cours',
                              style: FlutterFlowTheme.of(context).titleMedium.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FontWeight.w700,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleMedium
                                          .fontStyle,
                                    ),
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 8.0),
                          if (activeGames.isNotEmpty)
                            ...activeGames.map(
                              (game) => _buildGameCard(
                                game,
                                isActiveCard: true,
                                showActions: false,
                              ),
                            )
                          else
                            _buildCurrentGameEmptyState(),
                          const SizedBox(height: 8.0),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Jeux termin\u00E9s',
                              style: FlutterFlowTheme.of(context).titleMedium.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FontWeight.w700,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleMedium
                                          .fontStyle,
                                    ),
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 8.0),
                          if (finishedGames.isEmpty)
                            SizedBox(
                              height: 240.0,
                              child: _buildEmptyState(),
                            )
                          else
                            ...finishedGames.map((game) => _buildGameCard(game)),
                        ];

                        return ListView(
                          padding:
                              const EdgeInsets.fromLTRB(20.0, 0.0, 20.0, 16.0),
                          children: widgets.expand((w) sync* {
                            yield w;
                            yield const SizedBox(height: 10.0);
                          }).toList()
                            ..removeLast(),
                        );
                      },
                    ),
                  ),
                  wrapWithModel(
                    model: _model.customNavBarCommercant2Model,
                    updateCallback: () => safeSetState(() {}),
                    child: const CustomNavBarCommercant2Widget(
                      indexActive: 3,
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

