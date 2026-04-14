import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/components/custom_nav_bar_commercant2_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/utils/game_metrics.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '/utils/share_links.dart';
import 'jeu_detail_commercant_page_model.dart';
export 'jeu_detail_commercant_page_model.dart';

const bool kShowUniquePlayersStat = false;

class JeuDetailCommercantPageWidget extends StatefulWidget {
  const JeuDetailCommercantPageWidget({
    super.key,
    required this.gameDoc,
    required this.enseigneDoc,
  });

  final GamesRecord? gameDoc;
  final EnseignesRecord? enseigneDoc;

  static String routeName = 'JeuDetailCommercantPage';
  static String routePath = 'jeuDetailCommercantPage';

  @override
  State<JeuDetailCommercantPageWidget> createState() =>
      _JeuDetailCommercantPageWidgetState();
}

class _JeuDetailCommercantPageWidgetState
    extends State<JeuDetailCommercantPageWidget> {
  late JeuDetailCommercantPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => JeuDetailCommercantPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'JeuDetailCommercantPage'});
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  int _readUniquePlayers(GamesRecord game) {
    final data = game.snapshotData;
    final dynamic raw = data['unique_players_count'] ??
        data['stats_uniquePlayers'] ??
        data['uniquePlayersCount'] ??
        data['statsUniquePlayers'] ??
        data['unique_players'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  bool _hasUniquePlayers(GamesRecord game) {
    final data = game.snapshotData;
    return data['unique_players_count'] != null ||
        data['stats_uniquePlayers'] != null ||
        data['uniquePlayersCount'] != null ||
        data['statsUniquePlayers'] != null ||
        data['unique_players'] != null;
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(16.0),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      child: Row(
        children: [
          Container(
            width: 30.0,
            height: 30.0,
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).alternate,
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: Icon(
              icon,
              size: 16.0,
              color: FlutterFlowTheme.of(context).primary,
            ),
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 2,
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
                Text(
                  value,
                  style: FlutterFlowTheme.of(context).titleMedium.override(
                        font: GoogleFonts.interTight(
                          fontWeight: FontWeight.w700,
                          fontStyle:
                              FlutterFlowTheme.of(context).titleMedium.fontStyle,
                        ),
                        fontSize: 17.0,
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _prizeLabel(PrizesRecord prize) {
    if (prize.name.trim().isNotEmpty) {
      return prize.name.trim();
    }
    return prize.prizeType == PrizeType.principal
        ? 'Lot principal'
        : 'Lot secondaire';
  }

  List<PrizesRecord> _sortPrizes(List<PrizesRecord> input) {
    final prizes = [...input];
    prizes.sort((a, b) {
      final aMain = a.prizeType == PrizeType.principal ? 0 : 1;
      final bMain = b.prizeType == PrizeType.principal ? 0 : 1;
      final byType = aMain.compareTo(bMain);
      if (byType != 0) return byType;

      final byClaim = (a.claimed ? 1 : 0).compareTo(b.claimed ? 1 : 0);
      if (byClaim != 0) return byClaim;

      final aDate = a.winDate?.millisecondsSinceEpoch ?? 0;
      final bDate = b.winDate?.millisecondsSinceEpoch ?? 0;
      return bDate.compareTo(aDate);
    });
    return prizes;
  }

  Widget _buildCodeRow(PrizesRecord prize) {
    final isClaimed = prize.claimed;
    final code = prize.claimCode.trim().isNotEmpty ? prize.claimCode : '---';

    return Container(
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(14.0),
      ),
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _prizeLabel(prize),
            style: FlutterFlowTheme.of(context).titleSmall.override(
                  font: GoogleFonts.interTight(
                    fontWeight: FontWeight.w700,
                    fontStyle: FlutterFlowTheme.of(context).titleSmall.fontStyle,
                  ),
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8.0),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  'Code: $code',
                  style: FlutterFlowTheme.of(context).bodyMedium.override(
                        font: GoogleFonts.inter(
                          fontWeight:
                              FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                          fontStyle:
                              FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                        ),
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10.0, vertical: 6.0),
                decoration: BoxDecoration(
                  color: isClaimed ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Text(
                  isClaimed ? 'Retire' : 'Non retire',
                  style: FlutterFlowTheme.of(context).bodySmall.override(
                        font: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontStyle:
                              FlutterFlowTheme.of(context).bodySmall.fontStyle,
                        ),
                        color: isClaimed
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFE65100),
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          if (prize.hasWinnerId()) ...[
            const SizedBox(height: 12.0),
            FutureBuilder<UsersRecord>(
              future: UsersRecord.getDocumentOnce(prize.winnerId!),
              builder: (context, snapshot) {
                final winner = snapshot.data;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: FlutterFlowTheme.of(context)
                        .primaryBackground
                        .withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Informations gagnant',
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                              font: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .fontStyle,
                              ),
                              letterSpacing: 0.0,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8.0),
                      _buildWinnerInfoRow('NOM', winner?.lastName),
                      _buildWinnerInfoRow('PRENOM', winner?.firstName),
                      _buildWinnerInfoRow('VILLE', winner?.city),
                      _buildWinnerInfoRow('MAIL', winner?.email),
                      _buildWinnerInfoRow('Telephone', winner?.phoneNumber),
                    ].divide(const SizedBox(height: 6.0)),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWinnerInfoRow(String label, String? value) {
    final displayValue =
        (value ?? '').trim().isNotEmpty ? value!.trim() : '—';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88.0,
          child: Text(
            '$label :',
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  font: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                  ),
                  color: FlutterFlowTheme.of(context).secondaryText,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w700,
                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                ),
          ),
        ),
        Expanded(
          child: SelectableText(
            displayValue,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  font: GoogleFonts.inter(
                    fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                    fontStyle:
                        FlutterFlowTheme.of(context).bodySmall.fontStyle,
                  ),
                  letterSpacing: 0.0,
                  fontWeight:
                      FlutterFlowTheme.of(context).bodySmall.fontWeight,
                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.gameDoc;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: 108.0,
          actions: const [],
          flexibleSpace: FlexibleSpaceBar(
            title: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(0.0, 18.0, 0.0, 10.0),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 2.0),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: FlutterFlowTheme.of(context).alternate,
                            width: 1.0,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          FlutterFlowIconButton(
                            borderColor: Colors.transparent,
                            borderRadius: 12.0,
                            borderWidth: 1.0,
                            buttonSize: 48.0,
                            fillColor: Colors.white.withOpacity(0.9),
                            icon: Icon(
                              Icons.chevron_left_rounded,
                              color: FlutterFlowTheme.of(context).primaryText,
                              size: 24.0,
                            ),
                            onPressed: () async {
                              context.safePop();
                            },
                          ),
                          Expanded(
                            child: Center(
                              child: Image.asset(
                                'assets/images/logo_D_secondaire.png',
                                height: 36.0,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          Builder(
                            builder: (context) => Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  0.0, 0.0, 12.0, 0.0),
                              child: InkWell(
                                splashColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                onTap: () async {
                                  if (game == null) return;
                                  await Share.share(
                                    buildAppShareText(
                                      title:
                                          '${game.name} sur ProxiPlay',
                                      description: widget.enseigneDoc?.name
                                                  .trim()
                                                  .isNotEmpty ==
                                              true
                                          ? 'Disponible chez ${widget.enseigneDoc!.name}.'
                                          : null,
                                    ),
                                    sharePositionOrigin: getWidgetBoundingBox(context),
                                  );
                                },
                                child: Container(
                                  width: 48.0,
                                  height: 48.0,
                                  decoration: BoxDecoration(
                                    color: FlutterFlowTheme.of(context).primary,
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  child: const Icon(
                                    Icons.share_sharp,
                                    color: Colors.white,
                                    size: 24.0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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
          shadowColor: Colors.transparent,
          scrolledUnderElevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.fromSTEB(20.0, 12.0, 20.0, 20.0),
                  child: game == null
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20.0),
                          decoration: BoxDecoration(
                            color: FlutterFlowTheme.of(context).secondaryBackground,
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                          child: Text(
                            'Jeu introuvable.',
                            style: FlutterFlowTheme.of(context).bodyMedium,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              game.name,
                              style: FlutterFlowTheme.of(context).headlineMedium.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FontWeight.w700,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .headlineMedium
                                          .fontStyle,
                                    ),
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 12.0),
                            Container(
                              width: double.infinity,
                              height: 220.0,
                              decoration: BoxDecoration(
                                color: FlutterFlowTheme.of(context).secondaryBackground,
                                borderRadius: BorderRadius.circular(16.0),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16.0),
                                child: Image.network(
                                  game.photo,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12.0),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: FlutterFlowTheme.of(context).secondaryBackground,
                                borderRadius: BorderRadius.circular(16.0),
                              ),
                              child: Text(
                                game.description,
                                style: FlutterFlowTheme.of(context).bodyMedium,
                              ),
                            ),
                            const SizedBox(height: 16.0),
                            Text(
                              'Statistiques',
                              style: FlutterFlowTheme.of(context).titleLarge.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FontWeight.w700,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleLarge
                                          .fontStyle,
                                    ),
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 10.0),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final cardWidth =
                                    (constraints.maxWidth - 10.0) / 2;
                                final aspectRatio = cardWidth / 82.0;
                                return GridView(
                                  padding: EdgeInsets.zero,
                                  physics: const NeverScrollableScrollPhysics(),
                                  shrinkWrap: true,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 10.0,
                                    mainAxisSpacing: 10.0,
                                    childAspectRatio: aspectRatio,
                                  ),
                                  children: [
                                    _buildStatCard(
                                      icon: Icons.remove_red_eye,
                                      label: 'Ouvertures fiche',
                                      value: gameViewsDisplayValue(game),
                                    ),
                                    _buildStatCard(
                                      icon: Icons.star,
                                      label: 'Favoris',
                                      value: game.favorites.toString(),
                                    ),
                                    _buildStatCard(
                                      icon: Icons.sports_esports,
                                      label: 'Participations',
                                      value: game.participations.toString(),
                                    ),
                                    if (kShowUniquePlayersStat)
                                      _buildStatCard(
                                        icon: Icons.people,
                                        label: 'Joueurs uniques',
                                        value: _hasUniquePlayers(game)
                                            ? _readUniquePlayers(game)
                                                .toString()
                                            : '—',
                                      ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 16.0),
                            Text(
                              'Codes gagnants',
                              style: FlutterFlowTheme.of(context).titleLarge.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FontWeight.w700,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleLarge
                                          .fontStyle,
                                    ),
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 10.0),
                            StreamBuilder<List<PrizesRecord>>(
                              stream: queryPrizesRecord(
                                queryBuilder: (prizesRecord) => prizesRecord.where(
                                  'game_id',
                                  isEqualTo: game.reference,
                                ),
                              ),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16.0),
                                    decoration: BoxDecoration(
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryBackground,
                                      borderRadius: BorderRadius.circular(16.0),
                                    ),
                                    child: const SizedBox.shrink(),
                                  );
                                }

                                final prizes = _sortPrizes(snapshot.data!);
                                if (prizes.isEmpty) {
                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16.0),
                                    decoration: BoxDecoration(
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryBackground,
                                      borderRadius: BorderRadius.circular(16.0),
                                    ),
                                    child: Text(
                                      'Aucun code gagnant pour l\'instant',
                                      style: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .override(
                                            font: GoogleFonts.inter(
                                              fontWeight: FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontWeight,
                                              fontStyle: FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontStyle,
                                            ),
                                            letterSpacing: 0.0,
                                          ),
                                    ),
                                  );
                                }

                                return Column(
                                  children: prizes
                                      .map(_buildCodeRow)
                                      .toList()
                                      .divide(const SizedBox(height: 10.0)),
                                );
                              },
                            ),
                          ],
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
    );
  }
}
