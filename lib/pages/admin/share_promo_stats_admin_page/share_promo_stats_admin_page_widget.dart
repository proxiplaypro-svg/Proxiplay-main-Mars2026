import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/models/share_promo_models.dart';
import '/services/share_promo_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SharePromoStatsAdminPageWidget extends StatefulWidget {
  const SharePromoStatsAdminPageWidget({super.key});

  static String routeName = 'SharePromoStatsAdminPage';
  static String routePath = 'sharePromoStatsAdminPage';

  @override
  State<SharePromoStatsAdminPageWidget> createState() =>
      _SharePromoStatsAdminPageWidgetState();
}

class _SharePromoStatsAdminPageWidgetState
    extends State<SharePromoStatsAdminPageWidget> {
  final _service = SharePromoService();

  late Future<SharePromoAdminStatsModel> _statsFuture;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
  }

  Future<SharePromoAdminStatsModel> _loadStats() async {
    try {
      final stats = await _service.adminGetSharePromoStats();
      _loadError = null;
      return stats;
    } catch (error) {
      _loadError = 'Impossible de charger les statistiques: $error';
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

  String _formatDate(dynamic value) {
    if (value is Timestamp) {
      return dateTimeFormat('d/M/y H:mm', value.toDate());
    }
    if (value is DateTime) {
      return dateTimeFormat('d/M/y H:mm', value);
    }
    if (value is String && value.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(value.trim());
      if (parsed != null) {
        return dateTimeFormat('d/M/y H:mm', parsed);
      }
      return value;
    }
    return '-';
  }

  String _readValue(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) {
        continue;
      }
      if (key.toLowerCase().contains('createdat')) {
        return _formatDate(value);
      }
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '-';
  }

  String _formatRewardType(String value) {
    switch (value.trim()) {
      case 'all_games_until_midnight':
        return 'Tous les jeux jusqu à minuit';
      case 'play_credit':
      case 'plays':
      case 'remaining_part':
      case 'extra_play':
        return 'Parties supplémentaires';
      case 'game_bonus':
        return 'Bonus de jeu';
      default:
        return value.trim().isEmpty ? '-' : value;
    }
  }

  Widget _buildSection({
    required BuildContext context,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18.0,
            offset: const Offset(0.0, 8.0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
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
          const SizedBox(height: 4.0),
          Text(
            subtitle,
            style: theme.bodySmall.override(
              font: GoogleFonts.inter(
                fontWeight: theme.bodySmall.fontWeight,
                fontStyle: theme.bodySmall.fontStyle,
              ),
              color: theme.secondaryText,
              letterSpacing: 0.0,
              fontWeight: theme.bodySmall.fontWeight,
              fontStyle: theme.bodySmall.fontStyle,
            ),
          ),
          const SizedBox(height: 16.0),
          child,
        ],
      ),
    );
  }

  Widget _buildKpiCard(
    BuildContext context, {
    required String label,
    required int value,
    required Color accentColor,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 18.0),
      constraints: const BoxConstraints(minHeight: 142.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(18.0),
        border: Border.all(color: const Color(0xFFD9E2EC)),
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
          const SizedBox(height: 14.0),
          Text(
            '$value',
            style: theme.headlineMedium.override(
              font: GoogleFonts.interTight(
                fontWeight: FontWeight.w700,
                fontStyle: theme.headlineMedium.fontStyle,
              ),
              letterSpacing: 0.0,
              fontWeight: FontWeight.w700,
              fontStyle: theme.headlineMedium.fontStyle,
            ),
          ),
          const SizedBox(height: 6.0),
          Text(
            label,
            style: theme.bodyMedium.override(
              font: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontStyle: theme.bodyMedium.fontStyle,
              ),
              fontSize: 13.0,
              letterSpacing: 0.0,
              fontWeight: FontWeight.w600,
              fontStyle: theme.bodyMedium.fontStyle,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0xFFD9E2EC)),
      ),
      child: Text(message),
    );
  }

  Widget _buildListSection({
    required BuildContext context,
    required List<Map<String, dynamic>> rows,
    required String emptyMessage,
    required Widget Function(Map<String, dynamic> row) itemBuilder,
  }) {
    if (rows.isEmpty) {
      return _buildEmptyState(emptyMessage);
    }
    return Column(
      children: List.generate(rows.length, (index) {
        final row = rows[index];
        return Padding(
          padding: EdgeInsets.only(bottom: index == rows.length - 1 ? 0.0 : 12.0),
          child: itemBuilder(row),
        );
      }),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116.0,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF52606D),
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralCard(Map<String, dynamic> row) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0xFFD9E2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('inviteCode', _readValue(row, const ['inviteCode'])),
          _buildInfoRow('inviterUid', _readValue(row, const ['inviterUid'])),
          _buildInfoRow('status', _readValue(row, const ['status'])),
          _buildInfoRow('createdAt', _readValue(row, const ['createdAt'])),
        ],
      ),
    );
  }

  Widget _buildRewardCard(Map<String, dynamic> row) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0xFFD9E2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(
            'Utilisateur',
            _readValue(row, const ['uid', 'userId', 'user_id']),
          ),
          _buildInfoRow(
            'Récompense',
            _formatRewardType(
              _readValue(row, const ['type', 'rewardType', 'reward_type']),
            ),
          ),
          _buildInfoRow(
            'Valeur',
            _readValue(row, const ['value', 'rewardValue']),
          ),
          _buildInfoRow('Créé le', _readValue(row, const ['createdAt'])),
        ],
      ),
    );
  }

  Widget _buildTopInviterCard(Map<String, dynamic> row) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0xFFD9E2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('inviterUid', _readValue(row, const ['uid', 'inviterUid'])),
          _buildInfoRow(
            'acceptedCount',
            _readValue(row, const ['acceptedCount']),
          ),
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
              child: const Text('Réessayer'),
            ),
          ],
        ),
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
          'Statistiques parrainage',
          style: theme.titleLarge.override(
            font: GoogleFonts.interTight(
              fontWeight: FontWeight.w700,
              fontStyle: theme.titleLarge.fontStyle,
            ),
            letterSpacing: 0.0,
            fontWeight: FontWeight.w700,
            fontStyle: theme.titleLarge.fontStyle,
          ),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<SharePromoAdminStatsModel>(
          future: _statsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _buildErrorState();
            }
            if (!snapshot.hasData) {
              return _buildErrorState();
            }

            final stats = snapshot.data!;
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(20.0),
                children: [
                  _buildSection(
                    context: context,
                    title: 'SECTION 1 - KPI',
                    subtitle: 'Vue rapide de l’activité de parrainage.',
                    child: GridView.count(
                      crossAxisCount: MediaQuery.sizeOf(context).width > 900 ? 4 : 2,
                      crossAxisSpacing: 12.0,
                      mainAxisSpacing: 12.0,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: MediaQuery.sizeOf(context).width > 900 ? 1.35 : 1.1,
                      children: [
                        _buildKpiCard(
                          context,
                          label: 'Invitations en attente',
                          value: stats.pendingReferrals,
                          accentColor: const Color(0xFFF79009),
                        ),
                        _buildKpiCard(
                          context,
                          label: 'Inscriptions validées',
                          value: stats.acceptedReferrals,
                          accentColor: const Color(0xFF2E90FA),
                        ),
                        _buildKpiCard(
                          context,
                          label: 'Récompenses accordées',
                          value: stats.grantedRewards,
                          accentColor: const Color(0xFF12B76A),
                        ),
                        _buildKpiCard(
                          context,
                          label: 'Campagnes actives',
                          value: stats.activeCampaigns,
                          accentColor: const Color(0xFF7A5AF8),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  _buildSection(
                    context: context,
                    title: 'SECTION 2 - Referrals récentes',
                    subtitle: 'inviteCode, inviterUid, status, createdAt',
                    child: _buildListSection(
                      context: context,
                      rows: stats.recentReferrals,
                      emptyMessage: 'Aucune referral récente.',
                      itemBuilder: _buildReferralCard,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  _buildSection(
                    context: context,
                    title: 'SECTION 3 - Rewards récentes',
                    subtitle: 'userId, rewardType, value, createdAt',
                    child: _buildListSection(
                      context: context,
                      rows: stats.recentRewards,
                      emptyMessage: 'Aucune reward récente.',
                      itemBuilder: _buildRewardCard,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  _buildSection(
                    context: context,
                    title: 'SECTION 4 - Top parrains',
                    subtitle: 'inviterUid et acceptedCount, triés par performance.',
                    child: _buildListSection(
                      context: context,
                      rows: stats.topInviters,
                      emptyMessage: 'Aucun parrain en tête pour le moment.',
                      itemBuilder: _buildTopInviterCard,
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
