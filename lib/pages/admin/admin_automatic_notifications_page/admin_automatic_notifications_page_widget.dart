import 'package:flutter/material.dart';

import '/auth/firebase_auth/auth_util.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'admin_automatic_notifications_data.dart';

class AdminAutomaticNotificationsPageWidget extends StatefulWidget {
  const AdminAutomaticNotificationsPageWidget({super.key});

  static String routeName = 'AdminAutomaticNotificationsPage';
  static String routePath = 'adminAutomaticNotifications';

  @override
  State<AdminAutomaticNotificationsPageWidget> createState() =>
      _AdminAutomaticNotificationsPageWidgetState();
}

class _AdminAutomaticNotificationsPageWidgetState
    extends State<AdminAutomaticNotificationsPageWidget> {
  List<AutomaticNotificationScenario> _scenarios = const [];

  @override
  void initState() {
    super.initState();
    _reloadScenarios();
  }

  void _reloadScenarios() {
    _scenarios = AutomaticNotificationsRepository.instance.all();
  }

  Future<void> _openScenario(AutomaticNotificationScenario scenario) async {
    final updated = await context.pushNamed(
      AdminAutomaticNotificationConfigPageWidget.routeName,
      queryParameters: {
        'scenarioId': serializeParam(
          scenario.id,
          ParamType.String,
        ),
      }.withoutNulls,
    );
    if (updated != null && mounted) {
      setState(_reloadScenarios);
    }
  }

  Future<void> _createScenario() async {
    final created = await context.pushNamed(
      AdminAutomaticNotificationConfigPageWidget.routeName,
      queryParameters: {
        'isNew': serializeParam(true, ParamType.bool),
      }.withoutNulls,
    );
    if (created != null && mounted) {
      setState(_reloadScenarios);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserDocument == null && loggedIn) {
      return const Scaffold(body: Center(child: SizedBox.shrink()));
    }
    if (currentUserDocument?.userRole != Roles.admin) {
      return Scaffold(
        body: Center(
          child: Text('Admin only.', style: FlutterFlowTheme.of(context).bodyMedium),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications automatiques')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createScenario,
        icon: const Icon(Icons.add),
        label: const Text('Créer une notification automatique'),
      ),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          itemCount: _scenarios.length,
          itemBuilder: (context, index) => _scenarioTile(context, _scenarios[index]),
        ),
      ),
    );
  }

  Widget _scenarioTile(
      BuildContext context, AutomaticNotificationScenario scenario) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openScenario(scenario),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).primaryBackground,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: FlutterFlowTheme.of(context).alternate),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scenario.title,
                        style: FlutterFlowTheme.of(context).titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        scenario.description,
                        style: FlutterFlowTheme.of(context).bodySmall,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        scenario.summary,
                        style: FlutterFlowTheme.of(context).labelMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: [
                    Switch(
                      value: scenario.isEnabled,
                      onChanged: (value) {
                        AutomaticNotificationsRepository.instance
                            .toggleScenario(scenario.id, value);
                        setState(_reloadScenarios);
                      },
                    ),
                    const SizedBox(height: 8),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: FlutterFlowTheme.of(context).secondaryText,
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
}
