import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CommercantAdminDetailPageWidget extends StatefulWidget {
  const CommercantAdminDetailPageWidget({
    super.key,
    required this.userRef,
  });

  final DocumentReference userRef;

  @override
  State<CommercantAdminDetailPageWidget> createState() =>
      _CommercantAdminDetailPageWidgetState();
}

class _CommercantAdminDetailPageWidgetState
    extends State<CommercantAdminDetailPageWidget> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _storeNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _googlePlaceIdController = TextEditingController();

  bool _isEditing = false;
  bool _isUnlocking = false;
  String? _lastSeedKey;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _storeNameController.dispose();
    _addressController.dispose();
    _googlePlaceIdController.dispose();
    super.dispose();
  }

  void _seedControllers(UsersRecord user, EnseignesRecord? enseigne) {
    final seedKey = [
      user.reference.path,
      user.firstName,
      user.lastName,
      user.email,
      user.phoneNumber,
      user.city,
      enseigne?.reference.path ?? '',
      enseigne?.name ?? '',
      enseigne?.address ?? '',
      enseigne?.city ?? '',
      enseigne?.googlePlaceId ?? '',
    ].join('|');
    if (_isEditing || _lastSeedKey == seedKey) {
      return;
    }
    _lastSeedKey = seedKey;
    _firstNameController.text = user.firstName;
    _lastNameController.text = user.lastName;
    _emailController.text = user.email;
    _phoneController.text =
        user.phoneNumber.isNotEmpty ? user.phoneNumber : (enseigne?.phoneNumber ?? '');
    _cityController.text = user.city.isNotEmpty ? user.city : (enseigne?.city ?? '');
    _storeNameController.text = enseigne?.name ?? '';
    _addressController.text = enseigne?.address ?? '';
    _googlePlaceIdController.text = enseigne?.googlePlaceId ?? '';
  }

  String _statusLabel(AccountStatus? status) {
    switch (status) {
      case AccountStatus.approved:
        return 'Validé';
      case AccountStatus.rejected:
        return 'Refusé';
      case AccountStatus.pendingValidation:
      case AccountStatus.pendingIdentityCard:
      case AccountStatus.pendingIdentityPhoto:
      case AccountStatus.pendingInfo:
      case null:
        return 'En attente';
    }
  }

  Color _statusColor(AccountStatus? status) {
    switch (status) {
      case AccountStatus.approved:
        return const Color(0xFF12B76A);
      case AccountStatus.rejected:
        return const Color(0xFFEF4444);
      case AccountStatus.pendingValidation:
      case AccountStatus.pendingIdentityCard:
      case AccountStatus.pendingIdentityPhoto:
      case AccountStatus.pendingInfo:
      case null:
        return const Color(0xFFF79009);
    }
  }

  Widget _buildSectionCard(BuildContext context, Widget child) {
    return Container(
      width: double.infinity,
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
      padding: const EdgeInsets.all(18.0),
      child: child,
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
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
              if (subtitle != null) ...[
                const SizedBox(height: 6.0),
                Text(
                  subtitle,
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
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12.0),
          trailing,
        ],
      ],
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
            width: 110.0,
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
              style: theme.bodyMedium.override(
                font: GoogleFonts.inter(
                  fontWeight: FontWeight.w400,
                  fontStyle: theme.bodyMedium.fontStyle,
                ),
                letterSpacing: 0.0,
                fontWeight: FontWeight.w400,
                fontStyle: theme.bodyMedium.fontStyle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
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

  Future<void> _notifyMerchantAccountStatus(String uid) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('notifyMerchantAccountStatus')
          .call({'uid': uid});
    } catch (e) {
      // Le changement de statut est déjà enregistré ; un échec de
      // notification ne doit pas bloquer l'action admin.
      debugPrint('[CommercantAdminDetailPage] notify failed uid=$uid: $e');
    }
  }

  Future<void> _updateStatus(UsersRecord user, AccountStatus status) async {
    await user.reference.update(createUsersRecordData(accountStatus: status));
    await _notifyMerchantAccountStatus(user.reference.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Statut mis à jour : ${_statusLabel(status)}')),
    );
  }

  String _unlockButtonLabel(UsersRecord user) {
    final firestoreLooksApproved =
        user.accountStatus == AccountStatus.approved &&
        user.userRole == Roles.commercant;

    return firestoreLooksApproved
        ? 'Forcer le déblocage'
        : 'Valider et débloquer';
  }

  Future<void> _unlockMerchant(UsersRecord user) async {
    if (_isUnlocking) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Débloquer le commerçant'),
            content: Text(
              'Cette action va forcer la validation du compte pour '
              '${user.email.isNotEmpty ? user.email : user.reference.id}.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Confirmer'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _isUnlocking = true);

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('unlockCommercantAccount');

      await callable.call({
        'commercantUid': user.uid,
      });
      await _notifyMerchantAccountStatus(user.reference.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Commerçant validé et débloqué avec succès.'),
        ),
      );

      setState(() {});
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message?.isNotEmpty == true
                ? error.message!
                : 'Erreur backend pendant le déblocage du commerçant.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur inattendue : $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUnlocking = false);
      }
    }
  }

  Future<void> _saveMainInfo(
    UsersRecord user,
    EnseignesRecord? enseigne,
  ) async {
    await user.reference.update(
      createUsersRecordData(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        city: _cityController.text.trim(),
      ),
    );
    if (enseigne != null) {
      final trimmedPlaceId = _googlePlaceIdController.text.trim();
      await enseigne.reference.update({
        ...createEnseignesRecordData(
          name: _storeNameController.text.trim(),
          address: _addressController.text.trim(),
          city: _cityController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
        ),
        // Champ absent du document si non renseigne : createEnseignesRecordData
        // (via withoutNulls) ne peut pas exprimer une suppression de champ
        // existant, d'ou l'ecriture directe de FieldValue.delete() ici pour
        // permettre de retirer une association Google deja enregistree.
        'google_place_id':
            trimmedPlaceId.isEmpty ? FieldValue.delete() : trimmedPlaceId,
      });
    }
    setState(() {
      _isEditing = false;
      _lastSeedKey = null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Informations commerçant mises à jour.')),
    );
  }

  String _formatHoraires(List<HorairesRecord> horaires) {
    if (horaires.isEmpty) {
      return '-';
    }
    final sorted = [...horaires]..sort((a, b) => a.order.compareTo(b.order));
    String formatTime(DateTime? value) =>
        value == null ? '--:--' : dateTimeFormat('Hm', value);
    String formatDay(DayOfTheWeek? day) {
      switch (day) {
        case DayOfTheWeek.Lundi:
          return 'Lundi';
        case DayOfTheWeek.Mardi:
          return 'Mardi';
        case DayOfTheWeek.Mercredi:
          return 'Mercredi';
        case DayOfTheWeek.Jeudi:
          return 'Jeudi';
        case DayOfTheWeek.Vendredi:
          return 'Vendredi';
        case DayOfTheWeek.Samedi:
          return 'Samedi';
        case DayOfTheWeek.Dimanche:
          return 'Dimanche';
        case null:
          return 'Jour';
      }
    }

    return sorted.map((horaire) {
      if (!horaire.isOpen) {
        return '${formatDay(horaire.day)} : fermé';
      }
      if (horaire.isFullDay &&
          horaire.hasOpeningDay() &&
          horaire.hasClosingDay()) {
        return '${formatDay(horaire.day)} : '
            '${formatTime(horaire.openingDay)}-${formatTime(horaire.closingDay)}';
      }
      final parts = <String>[];
      if (horaire.hasOpeningMorning() && horaire.hasClosingMorning()) {
        parts.add(
          '${formatTime(horaire.openingMorning)}-${formatTime(horaire.closingMorning)}',
        );
      }
      if (horaire.hasOpeningAfternoon() && horaire.hasClosingAfternoon()) {
        parts.add(
          '${formatTime(horaire.openingAfternoon)}-${formatTime(horaire.closingAfternoon)}',
        );
      }
      final slots = parts.isEmpty ? '-' : parts.join(' / ');
      return '${formatDay(horaire.day)} : $slots';
    }).join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.secondaryBackground,
      appBar: AppBar(
        backgroundColor: theme.secondaryBackground,
        title: Text(
          'Fiche commerçant',
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
      body: StreamBuilder<UsersRecord>(
        stream: UsersRecord.getDocument(widget.userRef),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final user = userSnapshot.data!;
          return StreamBuilder<List<EnseignesRecord>>(
            stream: queryEnseignesRecord(
              queryBuilder: (q) => q.where('owner', isEqualTo: user.reference),
            ),
            builder: (context, enseigneSnapshot) {
              if (!enseigneSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final enseignes = enseigneSnapshot.data!;
              final enseigne = enseignes.isNotEmpty ? enseignes.first : null;
              _seedControllers(user, enseigne);
              return StreamBuilder<List<GamesRecord>>(
                stream: queryGamesRecord(
                  queryBuilder: (q) =>
                      q.where('create_by', isEqualTo: user.reference),
                ),
                builder: (context, gamesSnapshot) {
                  if (!gamesSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final games = gamesSnapshot.data!;
                  final now = getCurrentTimestamp;
                  final activeGames = games
                      .where((game) =>
                          game.hasEndDate() &&
                          game.endDate!.isAfter(now) &&
                          (!game.hasStartDate() ||
                              !game.startDate!.isAfter(now)))
                      .length;
                  final pastGames = games.length - activeGames;
                  final statusColor = _statusColor(user.accountStatus);

                  final content = ListView(
                    padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 24.0),
                    children: [
                      _buildSectionCard(
                        context,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        enseigne?.name.isNotEmpty == true
                                            ? enseigne!.name
                                            : '${user.firstName} ${user.lastName}'
                                                .trim(),
                                        style: theme.headlineSmall.override(
                                          font: GoogleFonts.interTight(
                                            fontWeight: FontWeight.w700,
                                            fontStyle:
                                                theme.headlineSmall.fontStyle,
                                          ),
                                          letterSpacing: 0.0,
                                          fontWeight: FontWeight.w700,
                                          fontStyle:
                                              theme.headlineSmall.fontStyle,
                                        ),
                                      ),
                                      const SizedBox(height: 6.0),
                                      Text(
                                        user.email.isNotEmpty ? user.email : '-',
                                        style: theme.bodyMedium.override(
                                          font: GoogleFonts.inter(
                                            fontWeight: FontWeight.w400,
                                            fontStyle:
                                                theme.bodyMedium.fontStyle,
                                          ),
                                          color: theme.secondaryText,
                                          letterSpacing: 0.0,
                                          fontWeight: FontWeight.w400,
                                          fontStyle:
                                              theme.bodyMedium.fontStyle,
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
                                    _statusLabel(user.accountStatus),
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
                            const SizedBox(height: 16.0),
                            Wrap(
                              spacing: 10.0,
                              runSpacing: 10.0,
                              children: [
                                _buildStatChip(
                                  context,
                                  label: 'Jeux actifs',
                                  value: '$activeGames',
                                ),
                                _buildStatChip(
                                  context,
                                  label: 'Jeux passés',
                                  value: '$pastGames',
                                ),
                                _buildStatChip(
                                  context,
                                  label: 'Total jeux',
                                  value: '${games.length}',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      _buildSectionCard(
                        context,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(
                              context,
                              title: 'Informations de contact',
                              trailing: TextButton(
                                onPressed: () {
                                  setState(() {
                                    _isEditing = !_isEditing;
                                  });
                                },
                                child: Text(_isEditing ? 'Annuler' : 'Modifier'),
                              ),
                            ),
                            const SizedBox(height: 14.0),
                            if (_isEditing) ...[
                              _buildEditField(
                                context,
                                label: 'Prénom',
                                controller: _firstNameController,
                              ),
                              const SizedBox(height: 12.0),
                              _buildEditField(
                                context,
                                label: 'Nom',
                                controller: _lastNameController,
                              ),
                              const SizedBox(height: 12.0),
                              _buildEditField(
                                context,
                                label: 'Email',
                                controller: _emailController,
                              ),
                              const SizedBox(height: 12.0),
                              _buildEditField(
                                context,
                                label: 'Téléphone',
                                controller: _phoneController,
                              ),
                            ] else ...[
                              _buildInfoRow(context, 'Prénom', user.firstName),
                              _buildInfoRow(context, 'Nom', user.lastName),
                              _buildInfoRow(context, 'Email', user.email),
                              _buildInfoRow(
                                context,
                                'Téléphone',
                                user.phoneNumber.isNotEmpty
                                    ? user.phoneNumber
                                    : (enseigne?.phoneNumber ?? ''),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      _buildSectionCard(
                        context,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(
                              context,
                              title: 'Informations commerce',
                              subtitle:
                                  enseignes.length > 1 ? '${enseignes.length} commerces liés' : null,
                            ),
                            const SizedBox(height: 14.0),
                            if (_isEditing) ...[
                              _buildEditField(
                                context,
                                label: 'Nom du commerce',
                                controller: _storeNameController,
                              ),
                              const SizedBox(height: 12.0),
                              _buildEditField(
                                context,
                                label: 'Ville',
                                controller: _cityController,
                              ),
                              const SizedBox(height: 12.0),
                              _buildEditField(
                                context,
                                label: 'Adresse',
                                controller: _addressController,
                                maxLines: 2,
                              ),
                            ] else ...[
                              _buildInfoRow(
                                context,
                                'Commerce',
                                enseigne?.name ?? '-',
                              ),
                              _buildInfoRow(
                                context,
                                'Ville',
                                user.city.isNotEmpty
                                    ? user.city
                                    : (enseigne?.city ?? ''),
                              ),
                              _buildInfoRow(
                                context,
                                'Adresse',
                                enseigne?.address ?? '',
                              ),
                              if (enseigne != null)
                                StreamBuilder<List<HorairesRecord>>(
                                  stream: queryHorairesRecord(
                                    parent: enseigne.reference,
                                    queryBuilder: (q) => q.orderBy('order'),
                                  ),
                                  builder: (context, horairesSnapshot) {
                                    final horaires = horairesSnapshot.data ?? const <HorairesRecord>[];
                                    return _buildInfoRow(
                                      context,
                                      'Horaires',
                                      _formatHoraires(horaires),
                                    );
                                  },
                                )
                              else
                                _buildInfoRow(context, 'Horaires', ''),
                            ],
                          ],
                        ),
                      ),
                      if (enseigne != null) ...[
                        const SizedBox(height: 16.0),
                        _buildGoogleFicheCard(context, enseigne),
                      ],
                      const SizedBox(height: 16.0),
                      _buildSectionCard(
                        context,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(
                              context,
                              title: 'Statut du compte',
                            ),
                            const SizedBox(height: 14.0),
                            _buildInfoRow(
                              context,
                              'Statut',
                              _statusLabel(user.accountStatus),
                            ),
                            _buildInfoRow(
                              context,
                              'Inscription',
                              user.hasCreatedTime()
                                  ? dateTimeFormat('d/M/y', user.createdTime)
                                  : '-',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      _buildSectionCard(
                        context,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(
                              context,
                              title: 'Jeux liés au commerçant',
                            ),
                            const SizedBox(height: 14.0),
                            _buildInfoRow(context, 'Jeux en cours', '$activeGames'),
                            _buildInfoRow(context, 'Jeux passés', '$pastGames'),
                            _buildInfoRow(context, 'Nombre total', '${games.length}'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      _buildSectionCard(
                        context,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(
                              context,
                              title: 'Actions admin',
                              subtitle:
                                  'Actions disponibles sur les champs et statuts existants.',
                            ),
                            const SizedBox(height: 14.0),
                            Wrap(
                              spacing: 10.0,
                              runSpacing: 10.0,
                              children: [
                                FilledButton(
                                  onPressed:
                                      _isUnlocking ? null : () => _unlockMerchant(user),
                                  child: Text(
                                    _isUnlocking
                                        ? 'Déblocage...'
                                        : _unlockButtonLabel(user),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: user.accountStatus == AccountStatus.rejected
                                      ? null
                                      : () => _updateStatus(
                                            user,
                                            AccountStatus.rejected,
                                          ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.error,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Refuser le compte'),
                                ),
                                OutlinedButton(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'La suspension/réactivation n’est pas disponible sans statut backend dédié.',
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Text('Suspendre / réactiver'),
                                ),
                                if (_isEditing)
                                  FilledButton(
                                    onPressed: () => _saveMainInfo(user, enseigne),
                                    child: const Text('Enregistrer les modifications'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );

                  return content;
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildGoogleFicheCard(BuildContext context, EnseignesRecord enseigne) {
    final theme = FlutterFlowTheme.of(context);
    final isLinked = hasGooglePlaceId(enseigne);
    final statusColor =
        isLinked ? const Color(0xFF12B76A) : const Color(0xFF98A2B3);
    return _buildSectionCard(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            title: 'Fiche Google',
            subtitle:
                'Association manuelle a une fiche Google via son Place ID. '
                'Aucune donnee Google (avis, note, horaires, photos...) '
                'n\'est recuperee automatiquement pour le moment.',
          ),
          const SizedBox(height: 14.0),
          Container(
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999.0),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Text(
              isLinked ? 'Google : associé' : 'Google : non associé',
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
          const SizedBox(height: 14.0),
          if (_isEditing)
            _buildEditField(
              context,
              label: 'Google Place ID (ex: ChIJ...)',
              controller: _googlePlaceIdController,
            )
          else
            _buildInfoRow(
              context,
              'Place ID',
              enseigne.googlePlaceId ?? '',
            ),
        ],
      ),
    );
  }

  Widget _buildStatChip(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FC),
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: const Color(0x120E1220)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
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
    );
  }
}
