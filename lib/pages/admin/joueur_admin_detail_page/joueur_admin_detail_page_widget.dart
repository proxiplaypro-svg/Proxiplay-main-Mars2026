import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';

enum _DetailStatus {
  active,
  relaunch,
  dormant,
  neverPlayed,
  suspended,
}

class _JoueurDetailViewData {
  const _JoueurDetailViewData({
    required this.user,
    required this.participations,
    required this.participationsLoaded,
  });

  final UsersRecord user;
  final List<ParticipantsRecord> participations;
  final bool participationsLoaded;
}

class JoueurAdminDetailPageWidget extends StatefulWidget {
  const JoueurAdminDetailPageWidget({
    super.key,
    required this.userRef,
  });

  final DocumentReference userRef;

  @override
  State<JoueurAdminDetailPageWidget> createState() =>
      _JoueurAdminDetailPageWidgetState();
}

class _JoueurAdminDetailPageWidgetState
    extends State<JoueurAdminDetailPageWidget> {
  int _refreshTick = 0;

  Future<_JoueurDetailViewData> _loadViewData() async {
    final user = await UsersRecord.getDocumentOnce(widget.userRef);

    try {
      final participations = await queryParticipantsRecordOnce(
        queryBuilder: (q) => q.where('user_id', isEqualTo: widget.userRef),
      );

      return _JoueurDetailViewData(
        user: user,
        participations: participations,
        participationsLoaded: true,
      );
    } catch (_) {
      try {
        final allParticipations = await queryParticipantsRecordOnce();
        final fallbackParticipations = allParticipations
            .where((entry) => entry.userId?.path == widget.userRef.path)
            .toList(growable: false);

        return _JoueurDetailViewData(
          user: user,
          participations: fallbackParticipations,
          participationsLoaded: true,
        );
      } catch (_) {
        return _JoueurDetailViewData(
          user: user,
          participations: const [],
          participationsLoaded: false,
        );
      }
    }
  }

  bool _isSuspended(UsersRecord user) {
    final cached = user.playerStatusCached.trim().toLowerCase();
    return cached == 'suspended' || cached == 'suspendu';
  }

  _DetailStatus _deriveStatus(UsersRecord user) {
    if (_isSuspended(user)) return _DetailStatus.suspended;

    final totalPlays = user.gamesPlayedCount;
    final lastActivity = user.lastRealActivityAt;

    if (totalPlays <= 0 && lastActivity == null) {
      return _DetailStatus.neverPlayed;
    }
    if (lastActivity == null) {
      return _DetailStatus.neverPlayed;
    }

    final days = DateTime.now().difference(lastActivity).inDays;
    if (days <= 7) return _DetailStatus.active;
    if (days <= 21) return _DetailStatus.relaunch;
    return _DetailStatus.dormant;
  }

  String _statusLabel(_DetailStatus status) {
    switch (status) {
      case _DetailStatus.active:
        return 'Actif';
      case _DetailStatus.relaunch:
        return 'À relancer';
      case _DetailStatus.dormant:
        return 'Dormant';
      case _DetailStatus.neverPlayed:
        return 'Jamais joué';
      case _DetailStatus.suspended:
        return 'Suspendu';
    }
  }

  Color _statusColor(_DetailStatus status) {
    switch (status) {
      case _DetailStatus.active:
        return const Color(0xFF12B76A);
      case _DetailStatus.relaunch:
        return const Color(0xFFF79009);
      case _DetailStatus.dormant:
        return const Color(0xFFEF6820);
      case _DetailStatus.neverPlayed:
        return const Color(0xFF667085);
      case _DetailStatus.suspended:
        return const Color(0xFFB42318);
    }
  }

  Widget _buildSectionCard(BuildContext context, Widget child) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFE),
        borderRadius: BorderRadius.circular(18.0),
        border: Border.all(color: const Color(0x120E1220)),
      ),
      padding: const EdgeInsets.all(16.0),
      child: child,
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final theme = FlutterFlowTheme.of(context);
    final displayValue = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 126.0,
            child: Text(
              label,
              style: theme.bodySmall.override(
                font: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontStyle: theme.bodySmall.fontStyle,
                ),
                color: theme.secondaryText,
                letterSpacing: 0.0,
                fontWeight: FontWeight.w600,
                fontStyle: theme.bodySmall.fontStyle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: theme.bodyMedium,
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
        backgroundColor: theme.secondaryBackground,
        title: const Text('Fiche joueur'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _refreshTick++;
              });
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: KeyedSubtree(
        key: ValueKey(_refreshTick),
        child: FutureBuilder<_JoueurDetailViewData>(
          future: _loadViewData(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 20.0),
                children: [
                  _buildSectionCard(
                    context,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Fiche joueur', style: theme.headlineMedium),
                        const SizedBox(height: 8.0),
                        Text(
                          'Impossible de charger ce compte joueur.',
                          style: theme.bodyMedium.copyWith(
                            color: theme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            if (!snapshot.hasData) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 20.0),
                children: [
                  _buildSectionCard(
                    context,
                    Text(
                      'Compte joueur introuvable.',
                      style: theme.bodyMedium,
                    ),
                  ),
                ],
              );
            }

            final data = snapshot.data!;
            final user = data.user;
            final status = _deriveStatus(user);
            final participations = [...data.participations]
              ..sort((a, b) {
                final aDate =
                    a.participationDate ?? DateTime.fromMillisecondsSinceEpoch(0);
                final bDate =
                    b.participationDate ?? DateTime.fromMillisecondsSinceEpoch(0);
                return bDate.compareTo(aDate);
              });
            final realParticipationsCount = participations.length;
            final distinctGamesCount =
                participations.map((entry) => entry.parentReference.path).toSet().length;
            final distinctDaysCount = participations
                .map(
                  (entry) => entry.participationDate == null
                      ? null
                      : dateTimeFormat('d/M/y', entry.participationDate),
                )
                .whereType<String>()
                .toSet()
                .length;
            final displayName = user.pseudo.trim().isNotEmpty
                ? user.pseudo.trim()
                : ('${user.firstName} ${user.lastName}'.trim().isNotEmpty
                    ? '${user.firstName} ${user.lastName}'.trim()
                    : user.email);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 20.0),
              children: [
                _buildSectionCard(
                  context,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName.isNotEmpty ? displayName : 'Joueur',
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
                      const SizedBox(height: 8.0),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10.0,
                          vertical: 5.0,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999.0),
                          border: Border.all(
                            color: _statusColor(status).withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(
                          _statusLabel(status),
                          style: theme.bodySmall.override(
                            font: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontStyle: theme.bodySmall.fontStyle,
                            ),
                            color: _statusColor(status),
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.w700,
                            fontStyle: theme.bodySmall.fontStyle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12.0),
                _buildSectionCard(
                  context,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Identité', style: theme.titleLarge),
                      const SizedBox(height: 12.0),
                      _buildInfoRow(context, 'Pseudo', user.pseudo),
                      _buildInfoRow(context, 'Prénom', user.firstName),
                      _buildInfoRow(context, 'Nom', user.lastName),
                      _buildInfoRow(context, 'Email', user.email),
                      _buildInfoRow(context, 'Téléphone', user.phoneNumber),
                      _buildInfoRow(context, 'Ville', user.city),
                      _buildInfoRow(context, 'UID', user.uid),
                    ],
                  ),
                ),
                const SizedBox(height: 12.0),
                _buildSectionCard(
                  context,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Inscription', style: theme.titleLarge),
                      const SizedBox(height: 12.0),
                      _buildInfoRow(
                        context,
                        'Date',
                        user.createdTime != null
                            ? dateTimeFormat('d/M/y H:mm', user.createdTime)
                            : '-',
                      ),
                      _buildInfoRow(
                        context,
                        'Rôle',
                        user.userRole?.serialize() ?? 'joueur',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12.0),
                _buildSectionCard(
                  context,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Activité', style: theme.titleLarge),
                      const SizedBox(height: 12.0),
                      _buildInfoRow(
                        context,
                        'Dernière activité',
                        user.lastRealActivityAt != null
                            ? dateTimeFormat('d/M/y H:mm', user.lastRealActivityAt)
                            : 'Jamais',
                      ),
                      _buildInfoRow(
                        context,
                        'Participations enregistrées',
                        data.participationsLoaded
                            ? '$realParticipationsCount'
                            : 'Indisponible',
                      ),
                      if (data.participationsLoaded)
                        _buildInfoRow(
                          context,
                          'Jeux distincts',
                          '$distinctGamesCount',
                        ),
                      if (data.participationsLoaded)
                        _buildInfoRow(
                          context,
                          'Jours joués',
                          '$distinctDaysCount',
                        ),
                      _buildInfoRow(
                        context,
                        'Parties restantes',
                        user.hasRemainingPart() ? '${user.remainingPart}' : '-',
                      ),
                      _buildInfoRow(
                        context,
                        'Statut calculé',
                        _statusLabel(status),
                      ),
                      if (!data.participationsLoaded)
                        Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(
                            'Le détail des participations n’a pas pu être recalculé. Le compteur utilisateur n’est pas utilisé ici comme source principale.',
                            style: theme.bodySmall.copyWith(
                              color: theme.secondaryText,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
