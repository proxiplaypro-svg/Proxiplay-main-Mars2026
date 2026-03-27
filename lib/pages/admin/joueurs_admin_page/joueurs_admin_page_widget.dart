import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/pages/admin/joueur_admin_detail_page/joueur_admin_detail_page_widget.dart';

enum _PlayerActivityStatus {
  active,
  relaunch,
  dormant,
  neverPlayed,
  suspended,
}

class _PlayerListItem {
  const _PlayerListItem({
    required this.user,
    required this.status,
  });

  final UsersRecord user;
  final _PlayerActivityStatus status;

  String get displayName {
    if (user.pseudo.trim().isNotEmpty) return user.pseudo.trim();
    final fullName = '${user.firstName} ${user.lastName}'.trim();
    if (fullName.isNotEmpty) return fullName;
    if (user.displayName.trim().isNotEmpty) return user.displayName.trim();
    if (user.email.trim().isNotEmpty) return user.email.trim();
    return 'Joueur sans nom';
  }

  String get email => user.email.trim().isNotEmpty ? user.email.trim() : '-';
  String get city => user.city.trim().isNotEmpty ? user.city.trim() : '-';
}

class JoueursAdminPageWidget extends StatefulWidget {
  const JoueursAdminPageWidget({super.key});

  @override
  State<JoueursAdminPageWidget> createState() => _JoueursAdminPageWidgetState();
}

class _JoueursAdminPageWidgetState extends State<JoueursAdminPageWidget> {
  final _searchController = TextEditingController();
  String _statusFilter = 'all';
  int _refreshTick = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<UsersRecord>> _loadPlayers() {
    return queryUsersRecordOnce(
      queryBuilder: (q) => q.where(
        'user_role',
        isEqualTo: Roles.joueur.serialize(),
      ),
    );
  }

  bool _isSuspended(UsersRecord user) {
    final cached = user.playerStatusCached.trim().toLowerCase();
    return cached == 'suspended' || cached == 'suspendu';
  }

  _PlayerActivityStatus _deriveStatus(UsersRecord user) {
    if (_isSuspended(user)) return _PlayerActivityStatus.suspended;

    final totalPlays = user.gamesPlayedCount;
    final lastActivity = user.lastRealActivityAt;

    if (totalPlays <= 0 && lastActivity == null) {
      return _PlayerActivityStatus.neverPlayed;
    }
    if (lastActivity == null) {
      return _PlayerActivityStatus.neverPlayed;
    }

    final days = DateTime.now().difference(lastActivity).inDays;
    if (days <= 7) return _PlayerActivityStatus.active;
    if (days <= 21) return _PlayerActivityStatus.relaunch;
    return _PlayerActivityStatus.dormant;
  }

  String _statusLabel(_PlayerActivityStatus status) {
    switch (status) {
      case _PlayerActivityStatus.active:
        return 'Actif';
      case _PlayerActivityStatus.relaunch:
        return 'À relancer';
      case _PlayerActivityStatus.dormant:
        return 'Dormant';
      case _PlayerActivityStatus.neverPlayed:
        return 'Jamais joué';
      case _PlayerActivityStatus.suspended:
        return 'Suspendu';
    }
  }

  Color _statusColor(_PlayerActivityStatus status) {
    switch (status) {
      case _PlayerActivityStatus.active:
        return const Color(0xFF12B76A);
      case _PlayerActivityStatus.relaunch:
        return const Color(0xFFF79009);
      case _PlayerActivityStatus.dormant:
        return const Color(0xFFEF6820);
      case _PlayerActivityStatus.neverPlayed:
        return const Color(0xFF667085);
      case _PlayerActivityStatus.suspended:
        return const Color(0xFFB42318);
    }
  }

  List<_PlayerListItem> _buildItems(List<UsersRecord> players) {
    return players
        .map(
          (user) => _PlayerListItem(
            user: user,
            status: _deriveStatus(user),
          ),
        )
        .toList(growable: false);
  }

  List<_PlayerListItem> _applyFilters(List<_PlayerListItem> input) {
    final query = _searchController.text.trim().toLowerCase();

    return input.where((item) {
      final haystack = [
        item.user.pseudo,
        item.user.firstName,
        item.user.lastName,
        item.user.displayName,
        item.user.email,
        item.user.city,
      ].join(' ').toLowerCase();

      final matchesSearch = query.isEmpty || haystack.contains(query);
      final matchesStatus = _statusFilter == 'all' ||
          (_statusFilter == 'active' &&
              item.status == _PlayerActivityStatus.active) ||
          (_statusFilter == 'relaunch' &&
              item.status == _PlayerActivityStatus.relaunch) ||
          (_statusFilter == 'dormant' &&
              item.status == _PlayerActivityStatus.dormant) ||
          (_statusFilter == 'never' &&
              item.status == _PlayerActivityStatus.neverPlayed) ||
          (_statusFilter == 'suspended' &&
              item.status == _PlayerActivityStatus.suspended);

      return matchesSearch && matchesStatus;
    }).toList(growable: false);
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

  Widget _buildKpiCard(
    BuildContext context, {
    required String label,
    required int value,
    required Color accent,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
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
          const SizedBox(height: 4.0),
          Text(
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
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, _PlayerActivityStatus status) {
    final theme = FlutterFlowTheme.of(context);
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999.0),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        _statusLabel(status),
        style: theme.bodySmall.override(
          font: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontStyle: theme.bodySmall.fontStyle,
          ),
          color: color,
          letterSpacing: 0.0,
          fontWeight: FontWeight.w700,
          fontStyle: theme.bodySmall.fontStyle,
        ),
      ),
    );
  }

  Widget _buildStatusChips() {
    const filters = [
      ('all', 'Tous'),
      ('active', 'Actifs'),
      ('relaunch', 'À relancer'),
      ('dormant', 'Dormants'),
      ('never', 'Jamais joué'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((entry) {
          final selected = _statusFilter == entry.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              label: Text(entry.$2),
              selected: selected,
              showCheckmark: false,
              onSelected: (_) {
                setState(() {
                  _statusFilter = entry.$1;
                });
              },
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  Widget _buildPlayerCard(BuildContext context, _PlayerListItem item) {
    final theme = FlutterFlowTheme.of(context);
    final created = item.user.createdTime;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFE),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0x120E1220)),
      ),
      padding: const EdgeInsets.all(14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName,
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
                      item.email,
                      style: theme.bodySmall.override(
                        font: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          fontStyle: theme.bodySmall.fontStyle,
                        ),
                        color: theme.secondaryText,
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w500,
                        fontStyle: theme.bodySmall.fontStyle,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10.0),
              _buildStatusBadge(context, item.status),
            ],
          ),
          const SizedBox(height: 10.0),
          Text(
            'Ville : ${item.city}',
            style: theme.bodySmall,
          ),
          const SizedBox(height: 4.0),
          Text(
            'Inscription : ${created != null ? dateTimeFormat('d/M/y', created) : '-'}',
            style: theme.bodySmall,
          ),
          const SizedBox(height: 12.0),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        JoueurAdminDetailPageWidget(userRef: item.user.reference),
                  ),
                );
              },
              child: const Text('Voir'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        backgroundColor: theme.secondaryBackground,
        appBar: AppBar(
          backgroundColor: theme.secondaryBackground,
          title: Text(
            'Comptes joueurs',
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
        body: KeyedSubtree(
          key: ValueKey(_refreshTick),
          child: FutureBuilder<List<UsersRecord>>(
            future: _loadPlayers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 20.0),
                  children: [
                    _buildSectionCard(
                      context,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Comptes joueurs',
                            style: theme.headlineMedium,
                          ),
                          const SizedBox(height: 6.0),
                          Text(
                            'Suivi, recherche et consultation des comptes joueurs Proxiplay',
                            style: theme.bodyMedium.copyWith(
                              color: theme.secondaryText,
                            ),
                          ),
                          const SizedBox(height: 16.0),
                          TextField(
                            enabled: false,
                            decoration: InputDecoration(
                              hintText: 'Chargement des joueurs...',
                              prefixIcon: const Icon(Icons.search_rounded),
                              filled: true,
                              fillColor: const Color(0xFFF6F7FB),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14.0),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24.0),
                          const Center(child: CircularProgressIndicator()),
                        ],
                      ),
                    ),
                  ],
                );
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
                          Text('Comptes joueurs', style: theme.headlineMedium),
                          const SizedBox(height: 8.0),
                          Text(
                            'Impossible de charger les comptes joueurs.',
                            style: theme.bodyMedium.copyWith(
                              color: theme.secondaryText,
                            ),
                          ),
                          const SizedBox(height: 16.0),
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _refreshTick++;
                              });
                            },
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }

              final players = _buildItems(snapshot.data ?? const []);
              final filtered = _applyFilters(players);
              final activeCount = players
                  .where((item) => item.status == _PlayerActivityStatus.active)
                  .length;
              final neverCount = players
                  .where((item) => item.status == _PlayerActivityStatus.neverPlayed)
                  .length;
              final relaunchCount = players
                  .where((item) => item.status == _PlayerActivityStatus.relaunch)
                  .length;
              final dormantCount = players
                  .where((item) => item.status == _PlayerActivityStatus.dormant)
                  .length;

              return ListView(
                padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 20.0),
                children: [
                  _buildSectionCard(
                    context,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Comptes joueurs',
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
                          'Suivi, recherche et consultation des comptes joueurs Proxiplay',
                          style: theme.bodyMedium.override(
                            font: GoogleFonts.inter(
                              fontWeight: FontWeight.w400,
                              fontStyle: theme.bodyMedium.fontStyle,
                            ),
                            color: theme.secondaryText,
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.w400,
                            fontStyle: theme.bodyMedium.fontStyle,
                          ),
                        ),
                        const SizedBox(height: 14.0),
                        TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Rechercher un joueur...',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: const Color(0xFFF6F7FB),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14.0),
                              borderSide: const BorderSide(
                                color: Color(0x120E1220),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14.0),
                              borderSide: const BorderSide(
                                color: Color(0x120E1220),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14.0),
                              borderSide: BorderSide(
                                color: theme.primary,
                                width: 1.2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14.0),
                        Wrap(
                          spacing: 10.0,
                          runSpacing: 10.0,
                          children: [
                            SizedBox(
                              width: 132.0,
                              child: _buildKpiCard(
                                context,
                                label: 'Total joueurs',
                                value: players.length,
                                accent: const Color(0xFF2E90FA),
                              ),
                            ),
                            SizedBox(
                              width: 132.0,
                              child: _buildKpiCard(
                                context,
                                label: 'Actifs',
                                value: activeCount,
                                accent: const Color(0xFF12B76A),
                              ),
                            ),
                            SizedBox(
                              width: 132.0,
                              child: _buildKpiCard(
                                context,
                                label: 'Jamais joué',
                                value: neverCount,
                                accent: const Color(0xFF667085),
                              ),
                            ),
                            SizedBox(
                              width: 132.0,
                              child: _buildKpiCard(
                                context,
                                label: 'À relancer',
                                value: relaunchCount,
                                accent: const Color(0xFFF79009),
                              ),
                            ),
                            SizedBox(
                              width: 132.0,
                              child: _buildKpiCard(
                                context,
                                label: 'Dormants',
                                value: dormantCount,
                                accent: const Color(0xFFEF6820),
                              ),
                            ),
                          ],
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
                        Text(
                          'Filtres',
                          style: theme.titleMedium,
                        ),
                        const SizedBox(height: 10.0),
                        _buildStatusChips(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  _buildSectionCard(
                    context,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          filtered.isEmpty
                              ? 'Aucun joueur trouvé'
                              : '${filtered.length} joueur${filtered.length > 1 ? 's' : ''}',
                          style: theme.titleMedium,
                        ),
                        const SizedBox(height: 12.0),
                        if (players.isEmpty)
                          Text(
                            'Aucun compte joueur n’a été trouvé.',
                            style: theme.bodyMedium.copyWith(
                              color: theme.secondaryText,
                            ),
                          )
                        else if (filtered.isEmpty)
                          Text(
                            'Aucun joueur ne correspond à votre recherche.',
                            style: theme.bodyMedium.copyWith(
                              color: theme.secondaryText,
                            ),
                          )
                        else
                          Column(
                            children: filtered
                                .map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10.0),
                                    child: _buildPlayerCard(context, item),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
