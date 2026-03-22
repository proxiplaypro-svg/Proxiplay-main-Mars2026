import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '/auth/firebase_auth/auth_util.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';

class AdminNotificationsCenterPageWidget extends StatelessWidget {
  const AdminNotificationsCenterPageWidget({super.key});

  static String routeName = 'AdminNotificationsCenterPage';
  static String routePath = 'adminNotificationsCenter';

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

    final createdBy = currentUserReference?.path ?? '';
    final notificationsCollection =
        FirebaseFirestore.instance.collection('ff_push_notifications');
    final configDoc =
        FirebaseFirestore.instance.collection('app_config').doc('notifications_auto');
    final scheduledQuery = notificationsCollection
        .where('created_by', isEqualTo: createdBy)
        .where('status', isEqualTo: 'scheduled');
    final latestQuery = notificationsCollection
        .where('created_by', isEqualTo: createdBy)
        .orderBy('created_at', descending: true)
        .limit(1);

    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
      appBar: AppBar(
        title: const Text('Centre de notifications'),
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: configDoc.snapshots(),
          builder: (context, configSnapshot) {
            final config =
                configSnapshot.data?.data() as Map<String, dynamic>? ?? const {};
            final activeAutomaticCount = [
              config['game_ending_enabled'] == true,
              config['new_game_enabled'] == true,
              config['inactive_relaunch_enabled'] == true,
            ].where((value) => value).length;

            return StreamBuilder<QuerySnapshot>(
              stream: scheduledQuery.snapshots(),
              builder: (context, scheduledSnapshot) {
                final scheduledCount = scheduledSnapshot.data?.docs.length ?? 0;
                return StreamBuilder<QuerySnapshot>(
                  stream: latestQuery.snapshots(),
                  builder: (context, latestSnapshot) {
                    final latestData = latestSnapshot.data?.docs.isNotEmpty == true
                        ? latestSnapshot.data!.docs.first.data()
                            as Map<String, dynamic>
                        : null;
                    final latestTitle =
                        (latestData?['notification_title'] ?? '').toString().trim();
                    final latestDate = latestData?['created_at'];
                    final latestText = latestDate is Timestamp
                        ? '${latestTitle.isNotEmpty ? latestTitle : 'Dernier envoi'} · ${dateTimeFormat('d/M HH:mm', latestDate.toDate())}'
                        : 'Aucun envoi récent';

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      children: [
                        _summaryCard(
                          context,
                          activeAutomaticCount: activeAutomaticCount,
                          scheduledCount: scheduledCount,
                          latestText: latestText,
                        ),
                        const SizedBox(height: 18),
                        _actionCard(
                          context,
                          icon: Icons.auto_awesome_outlined,
                          title: 'Notifications automatiques',
                          subtitle:
                              'Configurer les scénarios automatiques et leurs règles.',
                          color: const Color(0xFF7A5AF8),
                          onTap: () => context.pushNamed(
                            AdminAutomaticNotificationsPageWidget.routeName,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _actionCard(
                          context,
                          icon: Icons.send_outlined,
                          title: 'Envoyer une notification',
                          subtitle:
                              'Choisir une audience, composer un message et l’envoyer.',
                          color: const Color(0xFF2E90FA),
                          onTap: () => context.pushNamed(
                            AdminPushNotificationsPageWidget.routeName,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _actionCard(
                          context,
                          icon: Icons.schedule_outlined,
                          title: 'Notifications planifiées',
                          subtitle:
                              'Voir les campagnes programmées et gérer leur statut.',
                          color: const Color(0xFFF79009),
                          onTap: () => context.pushNamed(
                            AdminScheduledNotificationsPageWidget.routeName,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _actionCard(
                          context,
                          icon: Icons.analytics_outlined,
                          title: 'Historique / statistiques',
                          subtitle:
                              'Consulter les notifications envoyées et leurs résultats.',
                          color: const Color(0xFF12B76A),
                          onTap: () => context.pushNamed(
                            AdminPushNotificationsHistoryPageWidget.routeName,
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
      ),
    );
  }

  Widget _summaryCard(
    BuildContext context, {
    required int activeAutomaticCount,
    required int scheduledCount,
    required String latestText,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).primaryBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: FlutterFlowTheme.of(context).alternate),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vue d’ensemble',
            style: FlutterFlowTheme.of(context).titleMedium,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  context,
                  label: 'Automatiques actives',
                  value: activeAutomaticCount.toString(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _miniStat(
                  context,
                  label: 'Planifiées',
                  value: scheduledCount.toString(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            latestText,
            style: FlutterFlowTheme.of(context).bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _miniStat(BuildContext context,
      {required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: FlutterFlowTheme.of(context).headlineSmall),
          const SizedBox(height: 4),
          Text(label, style: FlutterFlowTheme.of(context).bodySmall),
        ],
      ),
    );
  }

  Widget _actionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).primaryBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: FlutterFlowTheme.of(context).titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: FlutterFlowTheme.of(context).bodySmall),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
