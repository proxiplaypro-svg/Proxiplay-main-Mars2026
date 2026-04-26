import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/cloud_functions/cloud_functions.dart';
import '/backend/firebase_storage/storage.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/upload_data.dart';
import '/pages/admin/admin_push_notifications_history_page/admin_push_notifications_history_page_widget.dart';

import 'admin_push_notifications_page_model.dart';

enum _AudienceMode { allUsers, normalUsers, professionals, adminsOnly, selectedUsers }

class AdminPushNotificationsPageWidget extends StatefulWidget {
  const AdminPushNotificationsPageWidget({super.key});

  static String routeName = 'AdminPushNotificationsPage';
  static String routePath = 'adminPushNotifications';

  @override
  State<AdminPushNotificationsPageWidget> createState() =>
      _AdminPushNotificationsPageWidgetState();
}

class _AdminPushNotificationsPageWidgetState
    extends State<AdminPushNotificationsPageWidget> {
  late AdminPushNotificationsPageModel _model;

  static const _pageSize = 25;
  final PagingController<DocumentSnapshot?, UsersRecord> _pagingController =
      PagingController(firstPageKey: null);

  _AudienceMode _audienceMode = _AudienceMode.allUsers;
  final Map<String, UsersRecord> _selectedUsers = {};

  bool _searchMode = false;
  List<UsersRecord> _searchResults = [];
  Timer? _searchDebounce;
  bool _searchLoading = false;
  final TextEditingController _inactivePlayerTestUidController =
      TextEditingController(text: 'UID_CIBLE');
  bool _inactivePlayerTestLoading = false;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => AdminPushNotificationsPageModel());
    _pagingController.addPageRequestListener(_fetchUsersPage);
    _loadGameEndingConfig();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _inactivePlayerTestUidController.dispose();
    _pagingController.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _loadGameEndingConfig() async {
    if (!mounted) return;
    setState(() => _model.gameEndingConfigLoading = true);
    try {
      final result = await makeCloudCall('adminGetNotificationsConfig', {});
      if (!mounted) return;
      setState(() {
        _model.gameEndingNotificationEnabled =
            result['game_ending_enabled'] ?? false;
        _model.gameEndingDaysBeforeController.text =
            (result['game_ending_days_before'] ?? 3).toString();
        final statuses =
            result['game_ending_target_statuses'] ?? ['actif', 'a_relancer'];
        _model.gameEndingTargetStatuses = {
          'actif': statuses.contains('actif'),
          'a_relancer': statuses.contains('a_relancer'),
        };
        _model.gameEndingUseCityFilter =
            result['game_ending_use_city_filter'] ?? true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur chargement config: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _model.gameEndingConfigLoading = false);
      }
    }
  }

  Future<void> _saveGameEndingConfig() async {
    if (!mounted) return;
    setState(() => _model.gameEndingConfigSaving = true);
    try {
      final daysBefore =
          int.tryParse(_model.gameEndingDaysBeforeController.text.trim()) ?? 3;
      final targetStatuses = _model.gameEndingTargetStatuses.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .toList();

      if (targetStatuses.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sélectionnez au moins un statut.')),
        );
        return;
      }

      final result = await makeCloudCall('adminSetNotificationsConfig', {
        'game_ending_enabled': _model.gameEndingNotificationEnabled,
        'game_ending_days_before': daysBefore,
        'game_ending_target_statuses': targetStatuses,
        'game_ending_use_city_filter': _model.gameEndingUseCityFilter,
      });

      if (!mounted) return;
      final ok = result['ok'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Configuration enregistrée.' : 'Erreur lors de la sauvegarde.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _model.gameEndingConfigSaving = false);
      }
    }
  }

  Future<void> _fetchUsersPage(DocumentSnapshot? pageKey) async {
    try {
      Query query = UsersRecord.collection
          .orderBy('created_time', descending: true)
          .limit(_pageSize);

      if (pageKey != null) {
        query = query.startAfterDocument(pageKey);
      }

      final snapshot = await query.get();
      final docs = snapshot.docs;
      final users =
          docs.map((doc) => UsersRecord.fromSnapshot(doc)).toList(growable: false);
      final isLastPage = users.length < _pageSize;

      if (isLastPage) {
        _pagingController.appendLastPage(users);
      } else {
        _pagingController.appendPage(users, docs.last);
      }
    } catch (e) {
      _pagingController.error = e;
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final query = value.trim();
      if (query.isEmpty) {
        if (!mounted) return;
        setState(() {
          _searchMode = false;
          _searchResults = [];
          _searchLoading = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _searchMode = true;
        _searchLoading = true;
      });

      final results = await _searchUsers(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searchLoading = false;
      });
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _model.searchController.clear();
    setState(() {
      _searchMode = false;
      _searchResults = [];
      _searchLoading = false;
    });
  }

  Future<List<UsersRecord>> _searchUsers(String q) async {
    final queryLower = q.toLowerCase();
    final byEmail = await UsersRecord.collection
        .orderBy('email')
        .startAt([queryLower])
        .endAt(['$queryLower\uf8ff'])
        .limit(25)
        .get();
    final byName = await UsersRecord.collection
        .orderBy('display_name')
        .startAt([q])
        .endAt(['$q\uf8ff'])
        .limit(25)
        .get();

    final usersByPath = <String, UsersRecord>{};
    for (final doc in byEmail.docs) {
      final user = UsersRecord.fromSnapshot(doc);
      usersByPath[user.reference.path] = user;
    }
    for (final doc in byName.docs) {
      final user = UsersRecord.fromSnapshot(doc);
      usersByPath[user.reference.path] = user;
    }
    return usersByPath.values.toList();
  }

  bool _matchesAudienceFilter(UsersRecord user) {
    switch (_audienceMode) {
      case _AudienceMode.adminsOnly:
        return user.userRole == Roles.admin;
      case _AudienceMode.professionals:
        return user.userRole == Roles.commercant;
      case _AudienceMode.normalUsers:
        return user.userRole != Roles.admin && user.userRole != Roles.commercant;
      case _AudienceMode.selectedUsers:
      case _AudienceMode.allUsers:
        return true;
    }
  }

  void _toggleSelected(UsersRecord user) {
    final key = user.reference.path;
    setState(() {
      if (_selectedUsers.containsKey(key)) {
        _selectedUsers.remove(key);
      } else {
        _selectedUsers[key] = user;
      }
    });
  }

  Future<void> _pickAndUploadImage() async {
    final selectedMedia = await selectMedia(
      mediaSource: MediaSource.photoGallery,
      imageQuality: 85,
    );
    if (selectedMedia == null || selectedMedia.isEmpty) return;

    setState(() => _model.isUploadingImage = true);
    try {
      final file = selectedMedia.first;
      final url = await uploadData(file.storagePath, file.bytes);
      if (url != null && mounted) {
        setState(() => _model.imageUrl = url);
      }
    } finally {
      if (mounted) {
        setState(() => _model.isUploadingImage = false);
      }
    }
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _model.scheduledAt ?? now,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _model.scheduledAt ?? now.add(const Duration(minutes: 5)),
      ),
    );
    if (time == null || !mounted) return;

    setState(() {
      _model.scheduleEnabled = true;
      _model.scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _send() async {
    if (_model.formKey.currentState == null ||
        !_model.formKey.currentState!.validate()) {
      return;
    }

    if (_audienceMode == _AudienceMode.selectedUsers && _selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez au moins un utilisateur.')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expirée. Reconnectez-vous.')),
      );
      return;
    }

    try {
      await user.getIdToken(true);
    } catch (_) {}

    final scheduledMs = _model.scheduleEnabled && _model.scheduledAt != null
        ? _model.scheduledAt!.millisecondsSinceEpoch
        : 0;
    final repeatEveryMinutes = _model.repeatEnabled
        ? int.tryParse(_model.repeatMinutesController.text.trim()) ?? 0
        : 0;
    final repeatCount = _model.repeatEnabled
        ? int.tryParse(_model.repeatCountController.text.trim()) ?? 0
        : 0;

    final targetUserGroup = switch (_audienceMode) {
      _AudienceMode.allUsers => 'All',
      _AudienceMode.adminsOnly => 'Admins',
      _AudienceMode.professionals => 'Professionals',
      _AudienceMode.normalUsers => 'NormalUsers',
      _AudienceMode.selectedUsers => 'All',
    };

    final userRefs = _audienceMode == _AudienceMode.selectedUsers
        ? _selectedUsers.keys.toList()
        : <String>[];

    final result = await makeCloudCall('createAdminPushNotification', {
      'title': _model.titleController.text.trim(),
      'body': _model.bodyController.text.trim(),
      'imageUrl': _model.imageUrl,
      'targetDevice': 'All',
      'targetUserGroup': targetUserGroup,
      'userRefs': userRefs,
      'scheduledTimeMs': scheduledMs,
      'repeatEveryMinutes': repeatEveryMinutes > 0 ? repeatEveryMinutes : null,
      'repeatCount': _model.repeatEnabled ? repeatCount : null,
    }.withoutNulls);

    final ok = result['ok'] == true;
    final id = result['id']?.toString() ?? '';
    if (!mounted) return;

    if (!ok || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Échec de création de la notification.')),
      );
      return;
    }

    if (scheduledMs > 0 || repeatEveryMinutes > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification planifiée.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notification en file d’envoi...')),
    );

    try {
      final docRef =
          FirebaseFirestore.instance.collection('ff_push_notifications').doc(id);
      final status = await docRef
          .snapshots()
          .map((snapshot) => snapshot.data()?['status']?.toString())
          .where((value) => value == 'succeeded' || value == 'failed')
          .first
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'succeeded'
                ? 'Notification envoyée.'
                : 'Échec lors de l’envoi.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification créée, statut en attente.')),
      );
    }
  }

  Future<void> _runInactivePlayerDryRunTest() async {
    final uid = _inactivePlayerTestUidController.text.trim();
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Renseignez un UID cible.')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expirée. Reconnectez-vous.')),
      );
      return;
    }

    setState(() => _inactivePlayerTestLoading = true);
    try {
      await user.getIdToken(true);
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final result = await functions
          .httpsCallable('runInactivePlayerAutomationsManual')
          .call({
        'automationId': 'inactive_players_7d',
        'dryRun': true,
        'onlyUserIds': [uid],
        'limit': 1,
      });

      final data = result.data is Map
          ? Map<String, dynamic>.from(result.data as Map)
          : <String, dynamic>{};
      final jsonResponse = const JsonEncoder.withIndent('  ').convert(data);

      debugPrint(
        '[runInactivePlayerAutomationsManual] dryRun response:\n$jsonResponse',
      );
      print('[runInactivePlayerAutomationsManual] dryRun response:\n$jsonResponse');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test dry-run exécuté. Réponse JSON dans les logs.'),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        '[runInactivePlayerAutomationsManual] error code=${error.code} message=${error.message}',
      );
      print(
        '[runInactivePlayerAutomationsManual] error code=${error.code} message=${error.message}',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message?.isNotEmpty == true
                ? error.message!
                : 'Erreur lors du test dry-run.',
          ),
        ),
      );
    } catch (error) {
      debugPrint('[runInactivePlayerAutomationsManual] error=$error');
      print('[runInactivePlayerAutomationsManual] error=$error');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors du test dry-run: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _inactivePlayerTestLoading = false);
      }
    }
  }

  String _audienceTitle() {
    switch (_audienceMode) {
      case _AudienceMode.allUsers:
        return 'Tous les utilisateurs';
      case _AudienceMode.normalUsers:
        return 'Joueurs';
      case _AudienceMode.professionals:
        return 'Commerçants';
      case _AudienceMode.adminsOnly:
        return 'Administrateurs';
      case _AudienceMode.selectedUsers:
        return 'Sélection manuelle';
    }
  }

  String _audienceSubtitle() {
    switch (_audienceMode) {
      case _AudienceMode.allUsers:
        return 'Diffusion large sur toute la base.';
      case _AudienceMode.normalUsers:
        return 'Ciblage des comptes joueurs uniquement.';
      case _AudienceMode.professionals:
        return 'Ciblage des comptes commerçants.';
      case _AudienceMode.adminsOnly:
        return 'Réservé aux administrateurs.';
      case _AudienceMode.selectedUsers:
        final count = _selectedUsers.length;
        return count == 0
            ? 'Choisissez précisément les comptes à notifier.'
            : '$count utilisateur${count > 1 ? 's' : ''} sélectionné${count > 1 ? 's' : ''}.';
    }
  }

  String _sendButtonLabel() {
    if (_model.scheduleEnabled) return 'Planifier l’envoi';
    if (_model.repeatEnabled) return 'Créer la campagne récurrente';
    return 'Envoyer maintenant';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'succeeded':
        return const Color(0xFF12B76A);
      case 'failed':
        return const Color(0xFFF04438);
      case 'scheduled':
        return const Color(0xFFF79009);
      default:
        return FlutterFlowTheme.of(context).primary;
    }
  }

  Widget _buildTopBanner() {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D2939), Color(0xFF344054)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Centre de gestion des notifications',
                    style: theme.headlineSmall.override(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Créez, planifiez et suivez vos pushs administrateur depuis un seul écran.',
                    style: theme.bodyMedium.override(
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _bannerPill(
                icon: Icons.group_outlined,
                label: _audienceTitle(),
              ),
              _bannerPill(
                icon: Icons.schedule_outlined,
                label: _model.scheduleEnabled && _model.scheduledAt != null
                    ? dateTimeFormat('d/M HH:mm', _model.scheduledAt)
                    : 'Envoi immédiat',
              ),
              _bannerPill(
                icon: Icons.tune_outlined,
                label: _model.gameEndingNotificationEnabled
                    ? 'Auto fin de jeu active'
                    : 'Automatisations à vérifier',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bannerPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: FlutterFlowTheme.of(context).labelMedium.override(
                  color: Colors.white,
                ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
  }) {
    return Container(
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: FlutterFlowTheme.of(context).alternate.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _sectionHeader({
    required String title,
    required String subtitle,
    IconData? icon,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: FlutterFlowTheme.of(context).primary),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: FlutterFlowTheme.of(context).titleLarge),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: FlutterFlowTheme.of(context).bodySmall.override(
                      color: FlutterFlowTheme.of(context).secondaryText,
                    ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _audienceChip(_AudienceMode mode, String label, IconData icon) {
    final selected = _audienceMode == mode;
    final theme = FlutterFlowTheme.of(context);
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: selected ? Colors.white : theme.primaryText,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
      labelStyle: theme.labelLarge.override(
        color: selected ? Colors.white : theme.primaryText,
      ),
      backgroundColor: theme.primaryBackground,
      selectedColor: theme.primary,
      side: BorderSide(
        color: selected ? theme.primary : theme.alternate,
      ),
      onSelected: (_) {
        setState(() {
          _audienceMode = mode;
          if (mode != _AudienceMode.selectedUsers) {
            _selectedUsers.clear();
          }
        });
      },
    );
  }

  Widget _summaryStat({
    required String label,
    required String value,
    required IconData icon,
    Color? accent,
  }) {
    final color = accent ?? FlutterFlowTheme.of(context).primary;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).primaryBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 14),
            Text(value, style: FlutterFlowTheme.of(context).headlineSmall),
            const SizedBox(height: 4),
            Text(label, style: FlutterFlowTheme.of(context).bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _selectionSummary() {
    final names = _selectedUsers.values
        .take(4)
        .map((user) {
          if (user.displayName.isNotEmpty) return user.displayName;
          if (user.email.isNotEmpty) return user.email;
          return user.uid;
        })
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).primaryBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: FlutterFlowTheme.of(context).alternate),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.people_alt_outlined,
                color: FlutterFlowTheme.of(context).primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Ciblage actuel',
                style: FlutterFlowTheme.of(context).titleSmall,
              ),
              const Spacer(),
              if (_audienceMode == _AudienceMode.selectedUsers &&
                  _selectedUsers.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _selectedUsers.clear()),
                  child: const Text('Vider'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _audienceSubtitle(),
            style: FlutterFlowTheme.of(context).bodyMedium,
          ),
          if (_audienceMode == _AudienceMode.selectedUsers &&
              _selectedUsers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: names
                  .map(
                    (name) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context)
                            .primary
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(name),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _userBadge(UsersRecord user) {
    final isAdmin = user.userRole == Roles.admin;
    final isPro = user.userRole == Roles.commercant;
    if (!isAdmin && !isPro) return const SizedBox.shrink();

    final label = isAdmin ? 'ADMIN' : 'PRO';
    final color = isAdmin
        ? const Color(0xFF7F56D9)
        : const Color(0xFF12B76A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: FlutterFlowTheme.of(context).labelSmall.override(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _userTile(UsersRecord user) {
    final isSelected = _selectedUsers.containsKey(user.reference.path);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        setState(() => _audienceMode = _AudienceMode.selectedUsers);
        _toggleSelected(user);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? FlutterFlowTheme.of(context).primary.withValues(alpha: 0.07)
              : FlutterFlowTheme.of(context).primaryBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? FlutterFlowTheme.of(context).primary
                : FlutterFlowTheme.of(context).alternate,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: FlutterFlowTheme.of(context)
                    .secondary
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                _initialForUser(user),
                style: FlutterFlowTheme.of(context).titleMedium.override(
                      color: FlutterFlowTheme.of(context).secondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName.isNotEmpty
                        ? user.displayName
                        : (user.email.isNotEmpty ? user.email : user.uid),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FlutterFlowTheme.of(context).bodyLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email.isNotEmpty ? user.email : user.uid,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FlutterFlowTheme.of(context).bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _userBadge(user),
            const SizedBox(width: 8),
            Checkbox(
              value: isSelected,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              onChanged: (_) {
                setState(() => _audienceMode = _AudienceMode.selectedUsers);
                _toggleSelected(user);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _initialForUser(UsersRecord user) {
    final source = user.displayName.isNotEmpty
        ? user.displayName
        : (user.email.isNotEmpty ? user.email : user.uid);
    return source.substring(0, 1).toUpperCase();
  }

  Widget _buildRecipientsPanel() {
    final filteredSearchResults =
        _searchResults.where(_matchesAudienceFilter).toList(growable: false);

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            title: 'Destinataires',
            subtitle: 'Choisissez une audience large ou une sélection précise.',
            icon: Icons.group_outlined,
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _audienceChip(
                _AudienceMode.allUsers,
                'Tous',
                Icons.public_outlined,
              ),
              _audienceChip(
                _AudienceMode.normalUsers,
                'Joueurs',
                Icons.sports_esports_outlined,
              ),
              _audienceChip(
                _AudienceMode.professionals,
                'Commerçants',
                Icons.storefront_outlined,
              ),
              _audienceChip(
                _AudienceMode.adminsOnly,
                'Admins',
                Icons.admin_panel_settings_outlined,
              ),
              _audienceChip(
                _AudienceMode.selectedUsers,
                'Sélection manuelle',
                Icons.how_to_reg_outlined,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _selectionSummary(),
          const SizedBox(height: 18),
          TextFormField(
            controller: _model.searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Rechercher par nom ou email',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _model.searchController.text.isNotEmpty
                  ? IconButton(
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close),
                    )
                  : null,
              filled: true,
              fillColor: FlutterFlowTheme.of(context).primaryBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 420,
            child: _searchMode
                ? _searchLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredSearchResults.isEmpty
                        ? Center(
                            child: Text(
                              'Aucun utilisateur trouvé.',
                              style: FlutterFlowTheme.of(context).bodyMedium,
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredSearchResults.length,
                            itemBuilder: (context, index) =>
                                _userTile(filteredSearchResults[index]),
                          )
                : PagedListView<DocumentSnapshot?, UsersRecord>(
                    pagingController: _pagingController,
                    builderDelegate: PagedChildBuilderDelegate<UsersRecord>(
                      itemBuilder: (context, item, index) {
                        if (!_matchesAudienceFilter(item)) {
                          return const SizedBox.shrink();
                        }
                        return _userTile(item);
                      },
                      firstPageProgressIndicatorBuilder: (_) =>
                          const Center(child: CircularProgressIndicator()),
                      newPageProgressIndicatorBuilder: (_) =>
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      noItemsFoundIndicatorBuilder: (_) => Center(
                        child: Text(
                          'Aucun utilisateur disponible.',
                          style: FlutterFlowTheme.of(context).bodyMedium,
                        ),
                      ),
                      firstPageErrorIndicatorBuilder: (_) => Center(
                        child: Text(
                          'Erreur de chargement.\n${_pagingController.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposePanel() {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            title: 'Composer la notification',
            subtitle: 'Préparez le contenu, l’image et le mode d’envoi.',
            icon: Icons.edit_notifications_outlined,
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _model.titleController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Titre',
              hintText: 'Ex: Nouveau jeu disponible aujourd’hui',
              filled: true,
              fillColor: FlutterFlowTheme.of(context).primaryBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Titre requis' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _model.bodyController,
            onChanged: (_) => setState(() {}),
            minLines: 4,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: 'Message',
              hintText: 'Expliquez clairement l’action attendue.',
              alignLabelWithHint: true,
              filled: true,
              fillColor: FlutterFlowTheme.of(context).primaryBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Message requis' : null,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _model.imageUrl,
                  key: ValueKey(_model.imageUrl),
                  decoration: InputDecoration(
                    labelText: 'Image URL',
                    hintText: 'Optionnel',
                    filled: true,
                    fillColor: FlutterFlowTheme.of(context).primaryBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) => setState(() {
                    _model.imageUrl = value.trim();
                  }),
                ),
              ),
              const SizedBox(width: 10),
              FFButtonWidget(
                onPressed: _model.isUploadingImage ? null : _pickAndUploadImage,
                text: _model.isUploadingImage ? 'Upload...' : 'Uploader',
                options: FFButtonOptions(
                  height: 52,
                  color: FlutterFlowTheme.of(context).primary,
                  textStyle: FlutterFlowTheme.of(context)
                      .labelLarge
                      .override(color: Colors.white),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilterChip(
                selected: _model.scheduleEnabled,
                label: Text(
                  _model.scheduleEnabled && _model.scheduledAt != null
                      ? 'Planifié le ${dateTimeFormat('d/M HH:mm', _model.scheduledAt)}'
                      : 'Planifier',
                ),
                onSelected: (selected) async {
                  if (!selected) {
                    setState(() {
                      _model.scheduleEnabled = false;
                      _model.scheduledAt = null;
                    });
                    return;
                  }
                  await _pickSchedule();
                },
              ),
              FilterChip(
                selected: _model.repeatEnabled,
                label: const Text('Récurrence'),
                onSelected: (selected) =>
                    setState(() => _model.repeatEnabled = selected),
              ),
            ],
          ),
          if (_model.repeatEnabled) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _model.repeatMinutesController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Toutes les X minutes',
                      filled: true,
                      fillColor: FlutterFlowTheme.of(context).primaryBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _model.repeatCountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Nombre d’envois',
                      helperText: '0 = illimité',
                      filled: true,
                      fillColor: FlutterFlowTheme.of(context).primaryBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          _buildPreviewCard(),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FFButtonWidget(
              onPressed: _send,
              text: _sendButtonLabel(),
              icon: const Icon(Icons.send_rounded, size: 18),
              options: FFButtonOptions(
                height: 54,
                color: const Color(0xFF101828),
                textStyle: FlutterFlowTheme.of(context)
                    .titleSmall
                    .override(color: Colors.white, fontWeight: FontWeight.w700),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _buildTemporaryInactivePlayerTestCard(),
        ],
      ),
    );
  }

  Widget _buildPreviewCard() {
    final title = _model.titleController.text.trim();
    final body = _model.bodyController.text.trim();
    final hasImage = _model.imageUrl.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).primaryBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: FlutterFlowTheme.of(context).alternate),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.visibility_outlined,
                color: FlutterFlowTheme.of(context).primary,
              ),
              const SizedBox(width: 8),
              Text('Aperçu', style: FlutterFlowTheme.of(context).titleSmall),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).secondaryBackground,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: FlutterFlowTheme.of(context).alternate.withValues(alpha: 0.8),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: FlutterFlowTheme.of(context)
                        .primary
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.notifications_none_rounded,
                    color: FlutterFlowTheme.of(context).primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? 'Titre de la notification' : title,
                        style: FlutterFlowTheme.of(context).titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        body.isEmpty
                            ? 'Le message envoyé apparaîtra ici.'
                            : body,
                        style: FlutterFlowTheme.of(context).bodyMedium,
                      ),
                      if (hasImage) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Image jointe',
                          style: FlutterFlowTheme.of(context).labelMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemporaryInactivePlayerTestCard() {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDB022)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.science_outlined,
                color: Color(0xFFB54708),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Test admin temporaire: inactive_player',
                  style: theme.titleSmall.override(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF7A2E0E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Callable manuel en dry-run uniquement. Aucun envoi réel tant que dryRun reste à true.',
            style: theme.bodyMedium.override(
              color: const Color(0xFF7A2E0E),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _inactivePlayerTestUidController,
            decoration: InputDecoration(
              labelText: 'UID cible',
              hintText: 'UID_CIBLE',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FFButtonWidget(
              onPressed:
                  _inactivePlayerTestLoading ? null : _runInactivePlayerDryRunTest,
              text: _inactivePlayerTestLoading
                  ? 'Test dry-run en cours...'
                  : 'Lancer test admin temporaire',
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              options: FFButtonOptions(
                height: 52,
                color: const Color(0xFFB54708),
                textStyle: theme.labelLarge.override(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutomationPanel() {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            title: 'Automatisation fin de jeu',
            subtitle: 'Gérez le rappel automatique envoyé avant la clôture d’un jeu.',
            icon: Icons.auto_awesome_outlined,
          ),
          const SizedBox(height: 18),
          if (_model.gameEndingConfigLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            Row(
              children: [
                _summaryStat(
                  label: 'Statut',
                  value: _model.gameEndingNotificationEnabled ? 'Actif' : 'Inactif',
                  icon: Icons.power_settings_new_outlined,
                  accent: _model.gameEndingNotificationEnabled
                      ? const Color(0xFF12B76A)
                      : const Color(0xFFF79009),
                ),
                const SizedBox(width: 12),
                _summaryStat(
                  label: 'Délai',
                  value: '${_model.gameEndingDaysBeforeController.text} j',
                  icon: Icons.timelapse_outlined,
                  accent: const Color(0xFF2E90FA),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SwitchListTile.adaptive(
              value: _model.gameEndingNotificationEnabled,
              contentPadding: EdgeInsets.zero,
              title: const Text('Activer les notifications automatiques'),
              subtitle: const Text(
                'Envoie un rappel avant la fin des jeux concernés.',
              ),
              onChanged: (value) =>
                  setState(() => _model.gameEndingNotificationEnabled = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _model.gameEndingDaysBeforeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Nombre de jours avant la fin',
                filled: true,
                fillColor: FlutterFlowTheme.of(context).primaryBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Statuts ciblés', style: FlutterFlowTheme.of(context).titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilterChip(
                  selected: _model.gameEndingTargetStatuses['actif'] ?? false,
                  label: const Text('actif'),
                  onSelected: (value) => setState(() {
                    _model.gameEndingTargetStatuses['actif'] = value;
                  }),
                ),
                FilterChip(
                  selected:
                      _model.gameEndingTargetStatuses['a_relancer'] ?? false,
                  label: const Text('a_relancer'),
                  onSelected: (value) => setState(() {
                    _model.gameEndingTargetStatuses['a_relancer'] = value;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              value: _model.gameEndingUseCityFilter,
              contentPadding: EdgeInsets.zero,
              title: const Text('Filtrer par ville'),
              subtitle: const Text(
                'Limite les notifications aux utilisateurs de la zone du commerçant.',
              ),
              onChanged: (value) =>
                  setState(() => _model.gameEndingUseCityFilter = value),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FFButtonWidget(
                onPressed:
                    _model.gameEndingConfigSaving ? null : _saveGameEndingConfig,
                text: _model.gameEndingConfigSaving
                    ? 'Enregistrement...'
                    : 'Enregistrer la configuration',
                options: FFButtonOptions(
                  height: 52,
                  color: FlutterFlowTheme.of(context).primary,
                  textStyle: FlutterFlowTheme.of(context)
                      .labelLarge
                      .override(color: Colors.white),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentHistoryPanel() {
    final createdBy = currentUserReference?.path ?? '';
    final query = FirebaseFirestore.instance
        .collection('ff_push_notifications')
        .where('created_by', isEqualTo: createdBy)
        .orderBy('created_at', descending: true)
        .limit(6);

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            title: 'Historique récent',
            subtitle: 'Suivez les dernières notifications créées depuis ce compte admin.',
            icon: Icons.history_outlined,
            trailing: TextButton(
              onPressed: () => context.pushNamed(
                AdminPushNotificationsHistoryPageWidget.routeName,
              ),
              child: const Text('Voir tout'),
            ),
          ),
          const SizedBox(height: 18),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: FlutterFlowTheme.of(context).primaryBackground,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    'Aucune notification récente.',
                    style: FlutterFlowTheme.of(context).bodyMedium,
                  ),
                );
              }

              return Column(
                children: docs.map((doc) {
                  final data = doc.data();
                  final title =
                      (data['notification_title'] ?? '').toString().trim();
                  final body = (data['notification_text'] ?? '').toString().trim();
                  final status = (data['status'] ?? '').toString().trim();
                  final createdAt = data['created_at'];
                  final createdAtText = createdAt is Timestamp
                      ? dateTimeFormat('d/M HH:mm', createdAt.toDate())
                      : 'En attente';
                  final sentCount = data['num_sent']?.toString() ?? '-';

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: FlutterFlowTheme.of(context).primaryBackground,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: FlutterFlowTheme.of(context).alternate,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title.isEmpty ? '(Sans titre)' : title,
                                style: FlutterFlowTheme.of(context).titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _statusColor(status).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                status.isEmpty ? 'started' : status,
                                style: FlutterFlowTheme.of(context)
                                    .labelSmall
                                    .override(
                                      color: _statusColor(status),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          body.isEmpty ? '(Sans message)' : body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FlutterFlowTheme.of(context).bodyMedium,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_outlined,
                              size: 16,
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                            const SizedBox(width: 6),
                            Text(createdAtText),
                            const SizedBox(width: 16),
                            Icon(
                              Icons.send_outlined,
                              size: 16,
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                            const SizedBox(width: 6),
                            Text('Envoyés: $sentCount'),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserDocument == null && loggedIn) {
      return const Scaffold(body: Center(child: SizedBox.shrink()));
    }
    if (currentUserDocument?.userRole != Roles.admin) {
      return Scaffold(
        body: Center(
          child: Text(
            'Admin only.',
            style: FlutterFlowTheme.of(context).bodyMedium,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Envoyer une notification'),
        elevation: 0,
        backgroundColor: const Color(0xFFF5F7FB),
        foregroundColor: FlutterFlowTheme.of(context).primaryText,
      ),
      body: SafeArea(
        child: Form(
          key: _model.formKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 1100;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: isCompact
                    ? Column(
                        children: [
                          _buildRecipientsPanel(),
                          const SizedBox(height: 16),
                          _buildComposePanel(),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: _buildRecipientsPanel()),
                          const SizedBox(width: 16),
                          Expanded(flex: 6, child: _buildComposePanel()),
                        ],
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}
