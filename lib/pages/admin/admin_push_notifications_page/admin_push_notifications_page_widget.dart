import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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

  // Step 0 = pick recipients, Step 1 = compose/send
  int _step = 0;

  _AudienceMode _audienceMode = _AudienceMode.allUsers;
  final Map<String, UsersRecord> _selectedUsers = {};

  bool _searchMode = false;
  List<UsersRecord> _searchResults = [];
  Timer? _searchDebounce;
  bool _searchLoading = false;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => AdminPushNotificationsPageModel());

    _pagingController.addPageRequestListener((pageKey) {
      _fetchUsersPage(pageKey);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _pagingController.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _fetchUsersPage(DocumentSnapshot? pageKey) async {
    try {
      // Order by a field that exists for all users.
      Query q = UsersRecord.collection
          .orderBy('created_time', descending: true)
          .limit(_pageSize);

      if (pageKey != null) {
        q = q.startAfterDocument(pageKey);
      }

      final QuerySnapshot snap = await q.get();
      final docs = snap.docs;
      final users =
          docs.map((d) => UsersRecord.fromSnapshot(d)).toList(growable: false);

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
        setState(() {
          _searchMode = false;
          _searchResults = [];
          _searchLoading = false;
        });
        return;
      }

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
    // Simple server-side prefix search on email + display_name and merge results.
    final queryLower = q.toLowerCase();
    final endLower = '$queryLower\uf8ff';
    final end = '$q\uf8ff';

    final byEmail = await UsersRecord.collection
        .orderBy('email')
        .startAt([queryLower])
        .endAt([endLower])
        .limit(25)
        .get();
    final byName = await UsersRecord.collection
        .orderBy('display_name')
        .startAt([q])
        .endAt([end])
        .limit(25)
        .get();

    final map = <String, UsersRecord>{};
    for (final d in byEmail.docs) {
      final u = UsersRecord.fromSnapshot(d);
      map[u.reference.path] = u;
    }
    for (final d in byName.docs) {
      final u = UsersRecord.fromSnapshot(d);
      map[u.reference.path] = u;
    }
    return map.values.toList();
  }

  void _toggleSelected(UsersRecord u) {
    final key = u.reference.path;
    setState(() {
      if (_selectedUsers.containsKey(key)) {
        _selectedUsers.remove(key);
      } else {
        _selectedUsers[key] = u;
      }
    });
  }

  bool _matchesAudienceFilter(UsersRecord u) {
    switch (_audienceMode) {
      case _AudienceMode.adminsOnly:
        return u.userRole == Roles.admin;
      case _AudienceMode.professionals:
        return u.userRole == Roles.commercant;
      case _AudienceMode.normalUsers:
        return u.userRole != Roles.admin;
      case _AudienceMode.selectedUsers:
      case _AudienceMode.allUsers:
        return true;
    }
  }

  Future<void> _pickAndUploadImage() async {
    final selectedMedia = await selectMediaWithSourceBottomSheet(
      context: context,
      allowPhoto: true,
      imageQuality: 85,
    );
    if (selectedMedia == null || selectedMedia.isEmpty) return;

    setState(() => _model.isUploadingImage = true);
    try {
      final file = selectedMedia.first;
      final url = await uploadData(file.storagePath, file.bytes);
      if (url != null) {
        setState(() => _model.imageUrl = url);
      }
    } finally {
      if (mounted) setState(() => _model.isUploadingImage = false);
    }
  }

  Future<void> _send() async {
    if (_model.formKey.currentState == null ||
        !_model.formKey.currentState!.validate()) {
      return;
    }

    if (_audienceMode == _AudienceMode.selectedUsers && _selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one user.')),
      );
      return;
    }

    // Check if user is actually authenticated
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('ERROR: No authenticated user found!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not authenticated. Please log in again.')),
      );
      return;
    }
    print('Auth user: ${user.uid}, email: ${user.email}');

    // Force token refresh to ensure we have a valid token
    try {
      final token = await user.getIdToken(true);
      print('Got fresh token: ${token?.substring(0, 20)}...');
    } catch (e) {
      print('Token refresh error: $e');
    }

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

    print('Calling createAdminPushNotification...');
    final res = await makeCloudCall('createAdminPushNotification', {
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

    print('Cloud call result: $res');
    final ok = res['ok'] == true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Notification queued.' : 'Failed to queue notification.'),
      ),
    );
  }

  Widget _userBadge(UsersRecord u) {
    final isAdmin = u.userRole == Roles.admin;
    final isPro = u.userRole == Roles.commercant;
    if (!isAdmin && !isPro) return const SizedBox.shrink();

    final label = isAdmin ? 'ADMIN' : 'PRO';
    final color = isAdmin
        ? FlutterFlowTheme.of(context).primary
        : FlutterFlowTheme.of(context).secondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: FlutterFlowTheme.of(context).labelSmall.override(
              fontSize: 10,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
      ),
    );
  }

  Widget _userTile(UsersRecord u) {
    final isSelected = _selectedUsers.containsKey(u.reference.path);
    return ListTile(
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: FlutterFlowTheme.of(context).primaryBackground,
      title: Row(
        children: [
          Expanded(
            child: Text(
              u.displayName.isNotEmpty
                  ? u.displayName
                  : (u.email.isNotEmpty ? u.email : u.uid),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _userBadge(u),
        ],
      ),
      subtitle: Text(u.email, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () {
        // UX: tapping a user selects them and switches to "Selected users" mode.
        setState(() => _audienceMode = _AudienceMode.selectedUsers);
        _toggleSelected(u);
      },
      trailing: _audienceMode == _AudienceMode.selectedUsers
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => _toggleSelected(u),
            )
          : null,
    );
  }

  Widget _selectedUsersHeader() {
    if (_audienceMode != _AudienceMode.selectedUsers) return const SizedBox.shrink();
    if (_selectedUsers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'To: (no users selected)',
          style: FlutterFlowTheme.of(context).labelMedium,
        ),
      );
    }

    final labels = _selectedUsers.values
        .take(3)
        .map((u) => u.displayName.isNotEmpty
            ? u.displayName
            : (u.email.isNotEmpty ? u.email : u.uid))
        .toList();
    final extraCount = _selectedUsers.length - labels.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: FlutterFlowTheme.of(context).secondaryBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: FlutterFlowTheme.of(context).alternate),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people_alt, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'To: ${labels.join(", ")}${extraCount > 0 ? " +$extraCount" : ""}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FlutterFlowTheme.of(context).bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Clear selected users',
            onPressed: () => setState(() => _selectedUsers.clear()),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _usersPanel() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Text(
            'Recipients',
            style: FlutterFlowTheme.of(context).titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Card(
            elevation: 0,
            color: FlutterFlowTheme.of(context).secondaryBackground,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextFormField(
                    controller: _model.searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search users (name or email)',
                      filled: true,
                      fillColor: FlutterFlowTheme.of(context).primaryBackground,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: _model.searchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.close),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: _audienceMode == _AudienceMode.allUsers,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _audienceMode = _AudienceMode.allUsers;
                              _selectedUsers.clear();
                            } else {
                              _audienceMode = _AudienceMode.selectedUsers;
                            }
                          });
                        },
                      ),
                      const Text('All users'),
                      const SizedBox(width: 12),
                      DropdownButton<_AudienceMode>(
                        value: _audienceMode,
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _audienceMode = v;
                            if (_audienceMode != _AudienceMode.selectedUsers) {
                              _selectedUsers.clear();
                            }
                          });
                        },
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(
                            value: _AudienceMode.allUsers,
                            child: Text('All users'),
                          ),
                          DropdownMenuItem(
                            value: _AudienceMode.professionals,
                            child: Text('Professionals'),
                          ),
                          DropdownMenuItem(
                            value: _AudienceMode.normalUsers,
                            child: Text('Normal users'),
                          ),
                          DropdownMenuItem(
                            value: _AudienceMode.adminsOnly,
                            child: Text('Admins only'),
                          ),
                          DropdownMenuItem(
                            value: _AudienceMode.selectedUsers,
                            child: Text('Selected users'),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (_audienceMode == _AudienceMode.selectedUsers)
                        Text(
                          '${_selectedUsers.length} selected',
                          style: FlutterFlowTheme.of(context).labelMedium,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Card(
              elevation: 1,
              color: FlutterFlowTheme.of(context).secondaryBackground,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _searchMode
                    ? (_searchLoading
                        ? const Center(child: CircularProgressIndicator())
                        : () {
                            final filtered = _searchResults
                                .where(_matchesAudienceFilter)
                                .toList(growable: false);
                            if (filtered.isEmpty) {
                              return const Center(child: Text('No users found.'));
                            }
                            return ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, i) => _userTile(filtered[i]),
                            );
                          }())
                    : PagedListView<DocumentSnapshot?, UsersRecord>(
                        pagingController: _pagingController,
                        builderDelegate:
                            PagedChildBuilderDelegate<UsersRecord>(
                          itemBuilder: (context, item, index) =>
                              _matchesAudienceFilter(item)
                                  ? _userTile(item)
                                  : const SizedBox.shrink(),
                          firstPageProgressIndicatorBuilder: (_) =>
                              const Center(child: CircularProgressIndicator()),
                          newPageProgressIndicatorBuilder: (_) =>
                              const Center(child: CircularProgressIndicator()),
                          noItemsFoundIndicatorBuilder: (_) =>
                              const Center(child: Text('No users.')),
                          firstPageErrorIndicatorBuilder: (_) => Center(
                            child: Text(
                              'Failed to load users.\n${_pagingController.error}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _composePanel({bool isPhone = false}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Compose', style: FlutterFlowTheme.of(context).titleMedium),
          const SizedBox(height: 8),
          _selectedUsersHeader(),
          if (isPhone)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _step = 0),
                child: const Text('Edit recipients'),
              ),
            ),
          Card(
            elevation: 0,
            color: FlutterFlowTheme.of(context).secondaryBackground,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextFormField(
                    controller: _model.titleController,
                    decoration: InputDecoration(
                      labelText: 'Title',
                      filled: true,
                      fillColor: FlutterFlowTheme.of(context).primaryBackground,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _model.bodyController,
                    decoration: InputDecoration(
                      labelText: 'Message',
                      filled: true,
                      fillColor: FlutterFlowTheme.of(context).primaryBackground,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    minLines: 3,
                    maxLines: 6,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: _model.imageUrl,
                          key: ValueKey(_model.imageUrl),
                          decoration: InputDecoration(
                            labelText: 'Image URL (optional)',
                            filled: true,
                            fillColor: FlutterFlowTheme.of(context).primaryBackground,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (v) => _model.imageUrl = v.trim(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FFButtonWidget(
                        onPressed: _model.isUploadingImage ? null : _pickAndUploadImage,
                        text: _model.isUploadingImage ? 'Uploading...' : 'Upload',
                        options: FFButtonOptions(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Schedule'),
                        selected: _model.scheduleEnabled,
                        onSelected: (v) async {
                          if (!v) {
                            setState(() {
                              _model.scheduleEnabled = false;
                              _model.scheduledAt = null;
                            });
                            return;
                          }
                          final now = DateTime.now();
                          final date = await showDatePicker(
                            context: context,
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 365)),
                            initialDate: now,
                          );
                          if (date == null) return;
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(
                                now.add(const Duration(minutes: 5))),
                          );
                          if (time == null) return;
                          final dt = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                          setState(() {
                            _model.scheduleEnabled = true;
                            _model.scheduledAt = dt;
                          });
                        },
                      ),
                      FilterChip(
                        label: const Text('Repeat'),
                        selected: _model.repeatEnabled,
                        onSelected: (v) => setState(() => _model.repeatEnabled = v),
                      ),
                      if (_model.scheduleEnabled && _model.scheduledAt != null)
                        Text(
                          'At: ${dateTimeFormat("y-MM-dd HH:mm", _model.scheduledAt)}',
                          style: FlutterFlowTheme.of(context).labelMedium,
                        ),
                    ],
                  ),
                  if (_model.repeatEnabled) ...[
                    const SizedBox(height: 12),
                    Text('Repeat settings',
                        style: FlutterFlowTheme.of(context).titleSmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _model.repeatMinutesController,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Every (minutes)'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _model.repeatCountController,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Count (0 = infinite)'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FFButtonWidget(
            onPressed: _send,
            text: _model.scheduleEnabled ? 'Schedule' : 'Send now',
            options: FFButtonOptions(
              height: 48,
              color: FlutterFlowTheme.of(context).primary,
              elevation: 2,
              borderRadius: BorderRadius.circular(14),
              textStyle: FlutterFlowTheme.of(context)
                  .titleSmall
                  .override(color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Note: schedule/repeat require Firebase Functions deployment (included in repo).',
            style: FlutterFlowTheme.of(context).labelSmall,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Guard: only admins should see this page (wait for user doc to load).
    if (currentUserDocument == null && loggedIn) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (currentUserDocument?.userRole != Roles.admin) {
      return Scaffold(
        body: Center(
          child: Text('Admin only.', style: FlutterFlowTheme.of(context).bodyMedium),
        ),
      );
    }

    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      appBar: AppBar(
        title: const Text('Admin Notifications'),
        elevation: 0,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        foregroundColor: FlutterFlowTheme.of(context).primaryText,
      ),
      body: SafeArea(
        child: Form(
          key: _model.formKey,
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isPhone = constraints.maxWidth < 600;
                    if (!isPhone) {
                      // Tablet/desktop: split view
                      return Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                    color: FlutterFlowTheme.of(context).alternate,
                                  ),
                                ),
                              ),
                              child: _usersPanel(),
                            ),
                          ),
                          Expanded(flex: 3, child: _composePanel()),
                        ],
                      );
                    }

                    // Phone: 2-step flow
                    return Column(
                      children: [
                        Expanded(
                          child: IndexedStack(
                            index: _step,
                            children: [
                              _usersPanel(),
                              _composePanel(isPhone: true),
                            ],
                          ),
                        ),
                        if (_step == 0)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: FlutterFlowTheme.of(context).alternate,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () {
                                      if (_audienceMode ==
                                              _AudienceMode.selectedUsers &&
                                          _selectedUsers.isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Select at least one user.'),
                                          ),
                                        );
                                        return;
                                      }
                                      setState(() => _step = 1);
                                    },
                                    child: const Text('Next'),
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
            ],
          ),
        ),
      ),
    );
  }
}




