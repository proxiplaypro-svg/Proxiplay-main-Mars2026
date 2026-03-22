import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '/auth/firebase_auth/auth_util.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';

class AdminScheduledNotificationsPageWidget extends StatelessWidget {
  const AdminScheduledNotificationsPageWidget({super.key});

  static String routeName = 'AdminScheduledNotificationsPage';
  static String routePath = 'adminScheduledNotifications';

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

    final createdBy = currentUserReference?.path ?? '';
    final query = FirebaseFirestore.instance
        .collection('ff_push_notifications')
        .where('created_by', isEqualTo: createdBy)
        .where('status', isEqualTo: 'scheduled')
        .orderBy('scheduled_time');

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications planifiées')),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Center(
                child: Text('Aucune campagne planifiée.'),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final title = (data['notification_title'] ?? '').toString();
                final target = (data['target_user_group'] ?? 'All').toString();
                final status = (data['status'] ?? '').toString();
                final scheduledAt = data['scheduled_time'];
                final scheduledText = scheduledAt is Timestamp
                    ? dateTimeFormat('d/M HH:mm', scheduledAt.toDate())
                    : 'Date inconnue';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: FlutterFlowTheme.of(context).primaryBackground,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: FlutterFlowTheme.of(context).alternate),
                  ),
                  child: ListTile(
                    title: Text(title.isNotEmpty ? title : '(Sans titre)'),
                    subtitle: Text('$target · $scheduledText'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          status,
                          style: FlutterFlowTheme.of(context).labelSmall,
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
