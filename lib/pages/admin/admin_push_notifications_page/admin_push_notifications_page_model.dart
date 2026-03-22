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

  // Configuration relance joueurs inactifs
  bool inactiveReLaunchEnabled = false;
  final inactivityFrequencyDaysController = TextEditingController(text: '7');

  // Configuration notification nouveau jeu
  bool newGameNotificationEnabled = false;
  bool newGameUseCityFilter = true;

  // Configuration notification jeu bientôt terminé (ÉTAPE 5)
  bool gameEndingNotificationEnabled = false;
  bool gameEndingUseCityFilter = true;
  final gameEndingDaysBeforeController = TextEditingController(text: '3');
  Map<String, bool> gameEndingTargetStatuses = {'actif': true, 'a_relancer': true};
  bool gameEndingConfigLoading = false;
  bool gameEndingConfigSaving = false;

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
    inactivityFrequencyDaysController.dispose();
    gameEndingDaysBeforeController.dispose();
  }
}


