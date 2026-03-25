import '/auth/firebase_auth/auth_util.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
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
  late Future<_ReferralStatsViewData> _statsFuture;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
  }

  Future<_ReferralStatsViewData> _loadStats() async {
    try {
      final stats = await _loadReferralStats();
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

  Future<_ReferralStatsViewData> _loadReferralStats() async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty) {
      throw StateError('Utilisateur non authentifié.');
    }

    final referralsRef = FirebaseFirestore.instance.collection('referrals');
    final userReferralsQuery = referralsRef.where('inviterUid', isEqualTo: uid);

    int totalReferrals = 0;
    try {
      final totalSnapshot = await userReferralsQuery.count().get();
      totalReferrals = totalSnapshot.count ?? 0;
    } catch (_) {
      totalReferrals = -1;
    }

    final querySnapshot = await userReferralsQuery.get();
    final docs = querySnapshot.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList();

    final statusValues = docs
        .map((row) => (row['status'] ?? '').toString().trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final missingCreatedAt = docs
        .where((row) => _readTimestampValue(row['createdAt']) == null)
        .length;

    debugPrint(
      '[share_promo_stats] totalReferrals=$totalReferrals filteredByUser=${docs.length} userUid=$uid',
    );
    debugPrint(
      '[share_promo_stats] statuses=${statusValues.join(', ')}',
    );
    if (docs.isEmpty) {
      debugPrint(
        '[share_promo_stats][warning] no referrals found for inviterUid=$uid',
      );
    }
    if (missingCreatedAt > 0) {
      debugPrint(
        '[share_promo_stats][warning] missing createdAt count=$missingCreatedAt inviterUid=$uid',
      );
    }

    final inviteeUserIds = docs
        .map((row) => (row['inviteeUid'] ?? '').toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final usersById = await _loadUsersByIds(inviteeUserIds);

    docs.sort((a, b) {
      final bMillis =
          _readTimestampValue(b['createdAt'])?.millisecondsSinceEpoch ?? 0;
      final aMillis =
          _readTimestampValue(a['createdAt'])?.millisecondsSinceEpoch ?? 0;
      return bMillis.compareTo(aMillis);
    });

    final pendingCount =
        docs.where((row) => _normalizeStatus(row) == 'pending').length;
    final acceptedCount =
        docs.where((row) => _normalizeStatus(row) == 'accepted').length;
    final rewardedCount = docs.where(_isRewardGranted).length;
    final campaignIds = docs
        .map((row) => (row['campaignId'] ?? '').toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final activeCampaigns = campaignIds.isNotEmpty
        ? campaignIds.length
        : docs.where((row) => row['active'] == true).length;

    final rows = docs.take(20).map((row) {
      final inviteeUid = (row['inviteeUid'] ?? '').toString().trim();
      final inviteeData = usersById[inviteeUid] ?? const <String, dynamic>{};
      return _ReferralRowViewData(
        displayName: _buildInviteeDisplayName(inviteeData),
        inviteCode: (row['inviteCode'] ?? '').toString().trim(),
        statusKey: _effectiveStatus(row),
        statusLabel: _statusLabel(row),
        createdAt: _readTimestampValue(row['createdAt']),
        rewardGranted: _isRewardGranted(row),
      );
    }).toList();

    return _ReferralStatsViewData(
      pendingReferrals: pendingCount,
      acceptedReferrals: acceptedCount,
      grantedRewards: rewardedCount,
      activeCampaigns: activeCampaigns,
      recentReferrals: rows,
    );
  }

  Future<Map<String, Map<String, dynamic>>> _loadUsersByIds(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) {
      return const <String, Map<String, dynamic>>{};
    }

    final result = <String, Map<String, dynamic>>{};
    for (var index = 0; index < userIds.length; index += 10) {
      final chunk = userIds.sublist(
        index,
        index + 10 > userIds.length ? userIds.length : index + 10,
      );
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        result[doc.id] = doc.data();
      }
    }
    return result;
  }

  Timestamp? _readTimestampValue(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value;
    }
    if (value is DateTime) {
      return Timestamp.fromDate(value);
    }
    if (value is int) {
      return Timestamp.fromMillisecondsSinceEpoch(value);
    }
    if (value is num) {
      return Timestamp.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value.trim());
      if (parsed != null) {
        return Timestamp.fromDate(parsed);
      }
    }
    return null;
  }

  String _normalizeStatus(Map<String, dynamic> row) =>
      (row['status'] ?? '').toString().trim().toLowerCase();

  bool _isRewardGranted(Map<String, dynamic> row) {
    final rewardGranted = row['rewardGranted'] == true;
    final rewardStatus =
        (row['rewardStatus'] ?? '').toString().trim().toLowerCase();
    final status = _normalizeStatus(row);
    return rewardGranted || rewardStatus == 'granted' || status == 'rewarded';
  }

  String _effectiveStatus(Map<String, dynamic> row) {
    if (_isRewardGranted(row)) {
      return 'rewarded';
    }
    return _normalizeStatus(row);
  }

  String _statusLabel(Map<String, dynamic> row) {
    switch (_effectiveStatus(row)) {
      case 'rewarded':
        return 'Récompensé';
      case 'accepted':
        return 'Inscrit';
      case 'pending':
      default:
        return 'En attente';
    }
  }

  String _buildInviteeDisplayName(Map<String, dynamic> userData) {
    final firstName = (userData['first_name'] ?? '').toString().trim();
    final displayName = (userData['display_name'] ?? '').toString().trim();
    final pseudo = (userData['pseudo'] ?? '').toString().trim();
    final fallback = (userData['name'] ?? '').toString().trim();
    final resolved = [
      firstName,
      displayName,
      pseudo,
      fallback,
    ].firstWhere(
      (value) => value.isNotEmpty,
      orElse: () => '',
    );
    return resolved.isNotEmpty ? resolved : 'Utilisateur invité';
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
    required List<_ReferralRowViewData> rows,
    required String emptyMessage,
    required Widget Function(_ReferralRowViewData row) itemBuilder,
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

  Color _statusColor(String statusKey) {
    switch (statusKey) {
      case 'rewarded':
        return const Color(0xFF12B76A);
      case 'accepted':
        return const Color(0xFF2E90FA);
      case 'pending':
      default:
        return const Color(0xFFF79009);
    }
  }

  Widget _buildStatusBadge(BuildContext context, _ReferralRowViewData row) {
    final color = _statusColor(row.statusKey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999.0),
      ),
      child: Text(
        row.statusLabel,
        style: FlutterFlowTheme.of(context).bodySmall.override(
              font: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
              ),
              color: color,
              letterSpacing: 0.0,
              fontWeight: FontWeight.w600,
              fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
            ),
      ),
    );
  }

  Widget _buildReferralCard(_ReferralRowViewData row) {
    final initials = row.displayName.trim().isNotEmpty
        ? row.displayName.trim().characters.first.toUpperCase()
        : 'U';
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
          Row(
            children: [
              CircleAvatar(
                radius: 22.0,
                backgroundColor: const Color(0xFFE8EEF7),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Color(0xFF1D3557),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.displayName,
                      style: const TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      row.inviteCode.isEmpty
                          ? 'Code indisponible'
                          : 'Code: ${row.inviteCode}',
                      style: const TextStyle(
                        fontSize: 13.0,
                        color: Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(context, row),
            ],
          ),
          const SizedBox(height: 12.0),
          Text(
            'Date: ${_formatDate(row.createdAt)}',
            style: const TextStyle(
              fontSize: 13.0,
              color: Color(0xFF52606D),
            ),
          ),
          if (row.rewardGranted) ...[
            const SizedBox(height: 6.0),
            const Text(
              'Récompense obtenue',
              style: TextStyle(
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
                color: Color(0xFF12B76A),
              ),
            ),
          ],
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
        child: FutureBuilder<_ReferralStatsViewData>(
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
                    subtitle: 'Vue rapide de l activite de parrainage.',
                    child: GridView.count(
                      crossAxisCount: MediaQuery.sizeOf(context).width > 900 ? 4 : 2,
                      crossAxisSpacing: 12.0,
                      mainAxisSpacing: 12.0,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio:
                          MediaQuery.sizeOf(context).width > 900 ? 1.35 : 1.1,
                      children: [
                        _buildKpiCard(
                          context,
                          label: 'Invitations en attente',
                          value: stats.pendingReferrals,
                          accentColor: const Color(0xFFF79009),
                        ),
                        _buildKpiCard(
                          context,
                          label: 'Inscriptions validees',
                          value: stats.acceptedReferrals,
                          accentColor: const Color(0xFF2E90FA),
                        ),
                        _buildKpiCard(
                          context,
                          label: 'Recompenses accordees',
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
                    title: 'SECTION 2 - Referrals recentes',
                    subtitle: 'Prénoms, statuts lisibles et dates de création.',
                    child: _buildListSection(
                      context: context,
                      rows: stats.recentReferrals,
                      emptyMessage: 'Aucune referral recente.',
                      itemBuilder: _buildReferralCard,
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

class _ReferralStatsViewData {
  const _ReferralStatsViewData({
    required this.pendingReferrals,
    required this.acceptedReferrals,
    required this.grantedRewards,
    required this.activeCampaigns,
    required this.recentReferrals,
  });

  final int pendingReferrals;
  final int acceptedReferrals;
  final int grantedRewards;
  final int activeCampaigns;
  final List<_ReferralRowViewData> recentReferrals;
}

class _ReferralRowViewData {
  const _ReferralRowViewData({
    required this.displayName,
    required this.inviteCode,
    required this.statusKey,
    required this.statusLabel,
    required this.createdAt,
    required this.rewardGranted,
  });

  final String displayName;
  final String inviteCode;
  final String statusKey;
  final String statusLabel;
  final Timestamp? createdAt;
  final bool rewardGranted;
}

