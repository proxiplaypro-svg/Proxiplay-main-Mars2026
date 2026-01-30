import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '/auth/firebase_auth/auth_util.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';

class AdminPushNotificationsHistoryPageWidget extends StatelessWidget {
  const AdminPushNotificationsHistoryPageWidget({super.key});

  static String routeName = 'AdminPushNotificationsHistoryPage';
  static String routePath = 'adminPushNotificationsHistory';

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

    final createdBy = currentUserReference?.path ?? '';
    final query = FirebaseFirestore.instance
        .collection('ff_push_notifications')
        .where('created_by', isEqualTo: createdBy)
        .orderBy('created_at', descending: true)
        .limit(50);

    return Scaffold(
      appBar: AppBar(title: const Text('Sent notifications')),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(child: Text('No notifications sent yet.'));
            }

            final docs = snapshot.data!.docs;
            return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final title = (data['notification_title'] ?? '').toString();
                final body = (data['notification_text'] ?? '').toString();
                final status = (data['status'] ?? '').toString();
                final createdAt = data['created_at'];
                final createdAtText = createdAt is Timestamp
                    ? dateTimeFormat('y-MM-dd HH:mm', createdAt.toDate())
                    : '';
                final numSent = data['num_sent']?.toString() ?? '';
                final error = (data['error'] ?? '').toString();

                return ListTile(
                  title: Text(
                    title.isNotEmpty ? title : '(No title)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    body.isNotEmpty ? body : '(No message)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(status, style: FlutterFlowTheme.of(context).labelSmall),
                      if (numSent.isNotEmpty)
                        Text('sent: $numSent',
                            style: FlutterFlowTheme.of(context).labelSmall),
                    ],
                  ),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      showDragHandle: true,
                      builder: (_) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.isNotEmpty ? title : '(No title)',
                              style: FlutterFlowTheme.of(context).titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(body.isNotEmpty ? body : '(No message)'),
                            const SizedBox(height: 12),
                            if (createdAtText.isNotEmpty)
                              Text('Sent: $createdAtText'),
                            if (status.isNotEmpty) Text('Status: $status'),
                            if (numSent.isNotEmpty) Text('Sent count: $numSent'),
                            if (error.isNotEmpty) Text('Error: $error'),
                          ],
                        ),
                      ),
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
}

