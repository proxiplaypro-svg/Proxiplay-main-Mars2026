import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/models/monthly_challenge_models.dart';
import '/services/monthly_challenge_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MonthlyChallengeStatsAdminPageWidget extends StatefulWidget {
  const MonthlyChallengeStatsAdminPageWidget({super.key});

  @override
  State<MonthlyChallengeStatsAdminPageWidget> createState() =>
      _MonthlyChallengeStatsAdminPageWidgetState();
}

class _MonthlyChallengeStatsAdminPageWidgetState
    extends State<MonthlyChallengeStatsAdminPageWidget> {
  final _service = MonthlyChallengeService();
  late Future<MonthlyChallengeAdminStatsModel> _statsFuture;
  bool _drawing = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
  }

  Future<MonthlyChallengeAdminStatsModel> _loadStats() async {
    try {
      final stats = await _service.adminGetMonthlyChallengeStats();
      _loadError = null;
      return stats;
    } catch (error) {
      _loadError = 'Impossible de charger le defi mensuel: $error';
      rethrow;
    }
  }

  Future<void> _refresh() async {
    final future = _loadStats();
    setState(() {
      _statsFuture = future;
    });
    await future;
  }

  String _formatDate(Timestamp? value) {
    if (value == null) {
      return '-';
    }
    return dateTimeFormat('d/M/y H:mm', value.toDate());
  }

  String _drawStatusLabel(String value) {
    switch (value.trim()) {
      case 'completed':
        return 'Termine';
      case 'no_eligible_users':
        return 'Aucun qualifie';
      case 'already_completed':
        return 'Deja tire';
      default:
        return value.trim().isEmpty ? 'En attente' : value;
    }
  }

  String _formatPercent(double value) {
    return '${value.toStringAsFixed(1).replaceAll('.', ',')} %';
  }

  String _formatAverage(double value, int targetDays) {
    return '${value.toStringAsFixed(1).replaceAll('.', ',')} / $targetDays jours';
  }

  Future<void> _runDraw() async {
    setState(() => _drawing = true);
    try {
      final result = await _service.adminRunMonthlyChallengeDraw();
      if (!mounted) {
        return;
      }
      logFirebaseEvent(
        'monthly_challenge_draw_completed',
        parameters: {
          'month': result['month'],
          'status': result['status'],
          'eligible_count': result['eligibleCount'],
          'winner_uid': result['winnerUid'],
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tirage execute: ${result['status'] ?? 'ok'}',
          ),
        ),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _drawing = false);
      }
    }
  }

  Widget _buildKpiCard(
    BuildContext context, {
    required String label,
    required String value,
    required Color accentColor,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.0),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12.0,
            height: 12.0,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(999.0),
            ),
          ),
          const SizedBox(height: 12.0),
          Text(
            value,
            style: theme.headlineMedium.override(
              font: GoogleFonts.interTight(
                fontWeight: FontWeight.w800,
                fontStyle: theme.headlineMedium.fontStyle,
              ),
              letterSpacing: 0.0,
              fontWeight: FontWeight.w800,
              fontStyle: theme.headlineMedium.fontStyle,
            ),
          ),
          const SizedBox(height: 6.0),
          Text(label, style: theme.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130.0,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42.0, color: Color(0xFFB42318)),
            const SizedBox(height: 12.0),
            Text(
              _loadError ?? 'Une erreur est survenue.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _statsFuture = _loadStats();
                });
              },
              child: const Text('Reessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistributionSection(
    BuildContext context,
    MonthlyChallengeAdminStatsModel stats,
  ) {
    final theme = FlutterFlowTheme.of(context);
    final maxCount = stats.distribution.fold<int>(
      0,
      (current, bucket) => bucket.count > current ? bucket.count : current,
    );

    return Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Progression des joueurs',
            style: theme.titleMedium.override(
              font: GoogleFonts.interTight(
                fontWeight: FontWeight.w700,
                fontStyle: theme.titleMedium.fontStyle,
              ),
              letterSpacing: 0.0,
              fontWeight: FontWeight.w700,
              fontStyle: theme.titleMedium.fontStyle,
            ),
          ),
          const SizedBox(height: 8.0),
          Text(
            'Moyenne: ${_formatAverage(stats.averageActiveDays, stats.config.targetDays)}'
            '${stats.medianActiveDays > 0 ? '  •  Mediane: ${stats.medianActiveDays.toStringAsFixed(1).replaceAll('.', ',')} jours' : ''}',
            style: theme.bodyMedium,
          ),
          const SizedBox(height: 16.0),
          if (stats.distribution.every((bucket) => bucket.count == 0))
            Text(
              'Aucun participant pour ce mois.',
              style: theme.bodyMedium,
            )
          else
            ...stats.distribution.map((bucket) {
              final ratio = maxCount > 0 ? bucket.count / maxCount : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 84.0,
                      child: Text(
                        '${bucket.label} jours',
                        style: theme.bodyMedium.override(
                          font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                          letterSpacing: 0.0,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999.0),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 12.0,
                          backgroundColor: const Color(0xFFF2F4F7),
                          color: const Color(0xFF2E90FA),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    SizedBox(
                      width: 88.0,
                      child: Text(
                        '${bucket.count} joueur${bucket.count > 1 ? 's' : ''}',
                        textAlign: TextAlign.right,
                        style: theme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTimelineSection(
    BuildContext context,
    MonthlyChallengeAdminStatsModel stats,
  ) {
    final theme = FlutterFlowTheme.of(context);
    final highlightedPoints = stats.timeline.isEmpty
        ? const <MonthlyChallengeTimelinePoint>[]
        : stats.timeline.length <= 7
            ? stats.timeline
            : <MonthlyChallengeTimelinePoint>[
                stats.timeline.first,
                stats.timeline[(stats.timeline.length * 0.2).floor()],
                stats.timeline[(stats.timeline.length * 0.4).floor()],
                stats.timeline[(stats.timeline.length * 0.6).floor()],
                stats.timeline[(stats.timeline.length * 0.8).floor()],
                stats.timeline.last,
              ];

    return Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Evolution pendant le mois',
            style: theme.titleMedium.override(
              font: GoogleFonts.interTight(
                fontWeight: FontWeight.w700,
                fontStyle: theme.titleMedium.fontStyle,
              ),
              letterSpacing: 0.0,
              fontWeight: FontWeight.w700,
              fontStyle: theme.titleMedium.fontStyle,
            ),
          ),
          const SizedBox(height: 8.0),
          if (stats.timeline.isEmpty)
            Text(
              'Historique indisponible pour ce mois.',
              style: theme.bodyMedium,
            )
          else
            ...highlightedPoints.map(
              (point) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  '${point.day} ${stats.config.month.isNotEmpty ? stats.config.month.substring(5) : ''}  •  ${point.participants} participants / ${point.qualified} qualifies',
                  style: theme.bodyMedium,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.secondaryBackground,
      appBar: AppBar(
        title: Text(
          'Stats defi mensuel',
          style: theme.titleLarge.override(
            font: GoogleFonts.interTight(),
            letterSpacing: 0.0,
          ),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<MonthlyChallengeAdminStatsModel>(
          future: _statsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _buildErrorState();
            }
            final stats = snapshot.data!;
            final title = stats.config.month.isEmpty
                ? 'Aucun defi configure'
                : (stats.config.title.isNotEmpty
                    ? stats.config.title
                    : 'Defi ${stats.config.month}');
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(20.0),
                children: [
                  Text(
                    title,
                    style: theme.headlineSmall.override(
                      font: GoogleFonts.interTight(
                        fontWeight: FontWeight.w800,
                        fontStyle: theme.headlineSmall.fontStyle,
                      ),
                      letterSpacing: 0.0,
                      fontWeight: FontWeight.w800,
                      fontStyle: theme.headlineSmall.fontStyle,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  GridView.count(
                    crossAxisCount: MediaQuery.sizeOf(context).width > 900 ? 4 : 2,
                    crossAxisSpacing: 12.0,
                    mainAxisSpacing: 12.0,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio:
                        MediaQuery.sizeOf(context).width > 900 ? 1.4 : 1.15,
                    children: [
                      _buildKpiCard(
                        context,
                        label: 'Participants',
                        value: '${stats.startedCount}',
                        accentColor: const Color(0xFFF79009),
                      ),
                      _buildKpiCard(
                        context,
                        label: 'Qualifies',
                        value: '${stats.qualifiedCount}',
                        accentColor: const Color(0xFF12B76A),
                      ),
                      _buildKpiCard(
                        context,
                        label: 'Qualification',
                        value: _formatPercent(stats.qualificationRate),
                        accentColor: const Color(0xFF2E90FA),
                      ),
                      _buildKpiCard(
                        context,
                        label: 'Moyenne',
                        value: _formatAverage(
                          stats.averageActiveDays,
                          stats.config.targetDays,
                        ),
                        accentColor: const Color(0xFF7A5AF8),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16.0),
                  _buildDistributionSection(context, stats),
                  const SizedBox(height: 16.0),
                  _buildTimelineSection(context, stats),
                  const SizedBox(height: 16.0),
                  Container(
                    padding: const EdgeInsets.all(18.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tirage',
                          style: theme.titleMedium.override(
                            font: GoogleFonts.interTight(
                              fontWeight: FontWeight.w700,
                              fontStyle: theme.titleMedium.fontStyle,
                            ),
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.w700,
                            fontStyle: theme.titleMedium.fontStyle,
                          ),
                        ),
                        const SizedBox(height: 14.0),
                        _buildInfoRow('Mois', stats.config.month.isEmpty ? '-' : stats.config.month),
                        _buildInfoRow('Objectif', '${stats.config.targetDays} jours'),
                        _buildInfoRow('Lot', stats.config.prizeTitle.isEmpty ? '-' : stats.config.prizeTitle),
                        _buildInfoRow('Date', _formatDate(stats.config.drawDate)),
                        _buildInfoRow('Statut', _drawStatusLabel(stats.drawStatus)),
                        _buildInfoRow('Eligibles', '${stats.eligibleCount}'),
                        _buildInfoRow('Gagnant', stats.winnerUid.isEmpty ? '-' : stats.winnerUid),
                        _buildInfoRow('Tire le', _formatDate(stats.drawnAt)),
                        const SizedBox(height: 8.0),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _drawing ? null : _runDraw,
                            icon: const Icon(Icons.casino_rounded),
                            label: Text(
                              _drawing ? 'Tirage en cours...' : 'Lancer le tirage',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
