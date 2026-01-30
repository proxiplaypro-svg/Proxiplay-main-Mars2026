import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_model.dart';
import 'admin_push_notifications_page_widget.dart'
    show AdminPushNotificationsPageWidget;

class AdminPushNotificationsPageModel
    extends FlutterFlowModel<AdminPushNotificationsPageWidget> {
  final formKey = GlobalKey<FormState>();

  final searchController = TextEditingController();
  final titleController = TextEditingController();
  final bodyController = TextEditingController();

  bool scheduleEnabled = false;
  DateTime? scheduledAt;

  bool repeatEnabled = false;
  final repeatMinutesController = TextEditingController(text: '60');
  final repeatCountController = TextEditingController(text: '0'); // 0 = infinite

  // Image URL (uploaded or pasted)
  String imageUrl = '';
  bool isUploadingImage = false;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    searchController.dispose();
    titleController.dispose();
    bodyController.dispose();
    repeatMinutesController.dispose();
    repeatCountController.dispose();
  }
}


