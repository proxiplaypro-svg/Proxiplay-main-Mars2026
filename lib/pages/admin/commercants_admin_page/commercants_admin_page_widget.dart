import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/pages/admin/commercant_admin_detail_page/commercant_admin_detail_page_widget.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CommercantsAdminPageWidget extends StatefulWidget {
  const CommercantsAdminPageWidget({super.key});

  @override
  State<CommercantsAdminPageWidget> createState() =>
      _CommercantsAdminPageWidgetState();
}

class _MerchantAdminSummary {
  const _MerchantAdminSummary({
    required this.user,
    required this.enseigne,
    required this.totalGames,
    required this.activeGames,
  });

  final UsersRecord user;
  final EnseignesRecord? enseigne;
  final int totalGames;
  final int activeGames;

  String get commerceName =>
      enseigne?.name.isNotEmpty == true ? enseigne!.name : 'Commerce non renseigné';
  String get contactName {
    final value = '${user.firstName} ${user.lastName}'.trim();
    if (value.isNotEmpty) return value;
    if (user.displayName.isNotEmpty) return user.displayName;
    return '-';
  }

  String get email => user.email.isNotEmpty ? user.email : '-';
  String get phone => user.phoneNumber.isNotEmpty
      ? user.phoneNumber
      : (enseigne?.phoneNumber.isNotEmpty == true ? enseigne!.phoneNumber : '-');
  String get city => user.city.isNotEmpty
      ? user.city
      : (enseigne?.city.isNotEmpty == true ? enseigne!.city : '-');
  DateTime? get signupDate => user.createdTime ?? enseigne?.createdTime;
}

class _CommercantsAdminPageWidgetState extends State<CommercantsAdminPageWidget> {
  final _searchController = TextEditingController();
  String _selectedStatus = 'all';
  String _selectedCity = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _statusKey(AccountStatus? status) {
    switch (status) {
      case AccountStatus.approved:
        return 'approved';
      case AccountStatus.rejected:
        return 'rejected';
      case AccountStatus.pendingValidation:
      case null:
        return 'pending';
    }
  }

  String _statusLabel(AccountStatus? status) {
    switch (_statusKey(status)) {
      case 'approved':
        return 'Validé';
      case 'rejected':
        return 'Refusé';
      case 'pending':
        return 'En attente';
      default:
        return 'Suspendu';
    }
  }

  Color _statusColor(AccountStatus? status) {
    switch (_statusKey(status)) {
      case 'approved':
        return const Color(0xFF12B76A);
      case 'rejected':
        return const Color(0xFFEF4444);
      case 'pending':
        return const Color(0xFFF79009);
      default:
        return const Color(0xFF667085);
    }
  }

  List<_MerchantAdminSummary> _buildSummaries(
    List<UsersRecord> users,
    List<EnseignesRecord> enseignes,
    List<GamesRecord> games,
  ) {
    final enseignesByOwner = <String, List<EnseignesRecord>>{};
    for (final enseigne in enseignes) {
      final owner = enseigne.owner;
      if (owner == null) continue;
      enseignesByOwner.putIfAbsent(owner.path, () => []).add(enseigne);
    }

    final gamesByOwner = <String, List<GamesRecord>>{};
    for (final game in games) {
      final owner = game.createBy;
      if (owner == null) continue;
      gamesByOwner.putIfAbsent(owner.path, () => []).add(game);
    }

    final now = getCurrentTimestamp;
    return users.map((user) {
      final merchantGames = gamesByOwner[user.reference.path] ?? const <GamesRecord>[];
      final activeGames = merchantGames
          .where((game) =>
              game.hasEndDate() &&
              game.endDate!.isAfter(now) &&
              (!game.hasStartDate() || !game.startDate!.isAfter(now)))
          .length;
      final merchantEnseignes = enseignesByOwner[user.reference.path] ?? const <EnseignesRecord>[];
      return _MerchantAdminSummary(
        user: user,
        enseigne: merchantEnseignes.isNotEmpty ? merchantEnseignes.first : null,
        totalGames: merchantGames.length,
        activeGames: activeGames,
      );
    }).toList();
  }

  List<_MerchantAdminSummary> _applyFilters(List<_MerchantAdminSummary> input) {
    final query = _searchController.text.trim().toLowerCase();
    return input.where((merchant) {
      final matchesStatus =
          _selectedStatus == 'all' || _statusKey(merchant.user.accountStatus) == _selectedStatus;
      final matchesCity = _selectedCity == 'all' || merchant.city == _selectedCity;
      final haystack = [
        merchant.commerceName,
        merchant.contactName,
        merchant.email,
        merchant.phone,
        merchant.city,
      ].join(' ').toLowerCase();
      final matchesSearch = query.isEmpty || haystack.contains(query);
      return matchesStatus && matchesCity && matchesSearch;
    }).toList()
      ..sort((a, b) {
        final aDate = a.signupDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.signupDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
  }

  Widget _buildSearchField(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Rechercher un commerçant, un commerce, un email...',
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: const Color(0xFFF6F7FB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.0),
          borderSide: const BorderSide(color: Color(0x120E1220)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.0),
          borderSide: BorderSide(color: theme.primary, width: 1.2),
        ),
      ),
    );
  }

  Widget _buildFilterField(
    BuildContext context, {
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final normalizedItems = items
        .map(
          (item) => DropdownMenuItem<String>(
            value: item.value,
            child: item.child is Text
                ? Text(
                    (item.child as Text).data ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : item.child,
          ),
        )
        .toList();

    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      items: normalizedItems,
      selectedItemBuilder: (context) => normalizedItems
          .map(
            (item) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                item.child is Text ? (item.child as Text).data ?? '' : '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF6F7FB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        errorStyle: const TextStyle(fontSize: 0, height: 0),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.0),
          borderSide: const BorderSide(color: Color(0x120E1220)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.0),
          borderSide: BorderSide(
            color: FlutterFlowTheme.of(context).primary,
            width: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _buildMerchantCard(BuildContext context, _MerchantAdminSummary merchant) {
    final theme = FlutterFlowTheme.of(context);
    final statusColor = _statusColor(merchant.user.accountStatus);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20.0),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  CommercantAdminDetailPageWidget(userRef: merchant.user.reference),
            ),
          );
        },
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFFFCFCFE),
            borderRadius: BorderRadius.circular(20.0),
            border: Border.all(color: const Color(0x0D0E1220)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x090E1220),
                blurRadius: 10.0,
                offset: Offset(0.0, 3.0),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
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
                            merchant.commerceName,
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
                            merchant.contactName,
                            style: theme.bodyMedium.override(
                              font: GoogleFonts.inter(
                                fontWeight: FontWeight.w500,
                                fontStyle: theme.bodyMedium.fontStyle,
                              ),
                              color: theme.primaryText,
                              letterSpacing: 0.0,
                              fontWeight: FontWeight.w500,
                              fontStyle: theme.bodyMedium.fontStyle,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999.0),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 8.0,
                      ),
                      child: Text(
                        _statusLabel(merchant.user.accountStatus),
                        style: theme.bodySmall.override(
                          font: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontStyle: theme.bodySmall.fontStyle,
                          ),
                          color: statusColor,
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w700,
                          fontStyle: theme.bodySmall.fontStyle,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12.0),
                _buildInfoLine(context, Icons.mail_outline_rounded, merchant.email),
                const SizedBox(height: 8.0),
                _buildInfoLine(context, Icons.phone_outlined, merchant.phone),
                const SizedBox(height: 8.0),
                _buildInfoLine(context, Icons.location_on_outlined, merchant.city),
                const SizedBox(height: 14.0),
                Row(
                  children: [
                    _buildStatChip(
                      context,
                      label: 'Jeux actifs',
                      value: '${merchant.activeGames}',
                    ),
                    const SizedBox(width: 10.0),
                    _buildStatChip(
                      context,
                      label: 'Inscription',
                      value: merchant.signupDate != null
                          ? dateTimeFormat('d/M/y', merchant.signupDate)
                          : '-',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoLine(BuildContext context, IconData icon, String value) {
    final theme = FlutterFlowTheme.of(context);
    final displayValue = value.trim().isEmpty ? '-' : value.trim();
    return Row(
      children: [
        Icon(icon, size: 16.0, color: theme.secondaryText),
        const SizedBox(width: 8.0),
        Expanded(
          child: Text(
            displayValue,
            style: theme.bodySmall.override(
              font: GoogleFonts.inter(
                fontWeight: FontWeight.w400,
                fontStyle: theme.bodySmall.fontStyle,
              ),
              color: theme.secondaryText,
              letterSpacing: 0.0,
              fontWeight: FontWeight.w400,
              fontStyle: theme.bodySmall.fontStyle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF6F7FB),
          borderRadius: BorderRadius.circular(14.0),
          border: Border.all(color: const Color(0x120E1220)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
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
            const SizedBox(height: 2.0),
            Text(
              label,
              style: theme.bodySmall.override(
                font: GoogleFonts.inter(
                  fontWeight: FontWeight.w400,
                  fontStyle: theme.bodySmall.fontStyle,
                ),
                color: theme.secondaryText,
                letterSpacing: 0.0,
                fontWeight: FontWeight.w400,
                fontStyle: theme.bodySmall.fontStyle,
              ),
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
        backgroundColor: theme.secondaryBackground,
        title: Text(
          'Gestion des commerçants',
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
      body: StreamBuilder<List<UsersRecord>>(
        stream: queryUsersRecord(
          queryBuilder: (q) => q.where(
            'user_role',
            isEqualTo: Roles.commercant.serialize(),
          ),
        ),
        builder: (context, usersSnapshot) {
          if (!usersSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<List<EnseignesRecord>>(
            stream: queryEnseignesRecord(),
            builder: (context, enseignesSnapshot) {
              if (!enseignesSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return StreamBuilder<List<GamesRecord>>(
                stream: queryGamesRecord(),
                builder: (context, gamesSnapshot) {
                  if (!gamesSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allMerchants = _buildSummaries(
                    usersSnapshot.data!,
                    enseignesSnapshot.data!,
                    gamesSnapshot.data!,
                  );
                  final cities = allMerchants
                      .map((m) => m.city)
                      .where((city) => city != '-' && city.trim().isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort();
                  final visibleMerchants = _applyFilters(allMerchants);

                  return ListView(
                    padding:
                        const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 20.0),
                    children: [
                      Text(
                        'Recherche, filtrage et consultation des comptes commerçants.',
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
                      const SizedBox(height: 16.0),
                      _buildSearchField(context),
                      const SizedBox(height: 12.0),
                      Row(
                        children: [
                          Expanded(
                            child: _buildFilterField(
                              context,
                              value: _selectedStatus,
                              items: const [
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Text('Tous les statuts'),
                                ),
                                DropdownMenuItem(
                                  value: 'pending',
                                  child: Text('En attente'),
                                ),
                                DropdownMenuItem(
                                  value: 'approved',
                                  child: Text('Validé'),
                                ),
                                DropdownMenuItem(
                                  value: 'rejected',
                                  child: Text('Refusé'),
                                ),
                                DropdownMenuItem(
                                  value: 'suspended',
                                  child: Text('Suspendu'),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _selectedStatus = value ?? 'all';
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12.0),
                          Expanded(
                            child: _buildFilterField(
                              context,
                              value: _selectedCity,
                              items: [
                                const DropdownMenuItem(
                                  value: 'all',
                                  child: Text('Toutes les villes'),
                                ),
                                ...cities.map(
                                  (city) => DropdownMenuItem(
                                    value: city,
                                    child: Text(city),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _selectedCity = value ?? 'all';
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14.0),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F7FB),
                          borderRadius: BorderRadius.circular(16.0),
                          border: Border.all(color: const Color(0x120E1220)),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14.0,
                          vertical: 12.0,
                        ),
                        child: Text(
                          '${visibleMerchants.length} commerçant${visibleMerchants.length > 1 ? 's' : ''} affiché${visibleMerchants.length > 1 ? 's' : ''}',
                          style: theme.bodyMedium.override(
                            font: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontStyle: theme.bodyMedium.fontStyle,
                            ),
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.w600,
                            fontStyle: theme.bodyMedium.fontStyle,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      if (_selectedStatus == 'suspended')
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(16.0),
                            border: Border.all(color: const Color(0x33F79009)),
                          ),
                          padding: const EdgeInsets.all(14.0),
                          child: Text(
                            'Le statut suspendu n’existe pas encore dans les données actuelles. Aucun compte ne peut être filtré comme suspendu pour le moment.',
                            style: theme.bodySmall.override(
                              font: GoogleFonts.inter(
                                fontWeight: FontWeight.w400,
                                fontStyle: theme.bodySmall.fontStyle,
                              ),
                              color: const Color(0xFF9A5B13),
                              letterSpacing: 0.0,
                              fontWeight: FontWeight.w400,
                              fontStyle: theme.bodySmall.fontStyle,
                            ),
                          ),
                        )
                      else if (visibleMerchants.isEmpty)
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F7FB),
                            borderRadius: BorderRadius.circular(18.0),
                            border: Border.all(color: const Color(0x120E1220)),
                          ),
                          padding: const EdgeInsets.all(20.0),
                          child: Text(
                            'Aucun commerçant ne correspond aux filtres actuels.',
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
                        )
                      else
                        ...visibleMerchants.map(
                          (merchant) => Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: _buildMerchantCard(context, merchant),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
