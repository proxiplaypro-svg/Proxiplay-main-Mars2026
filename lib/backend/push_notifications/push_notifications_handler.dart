import 'dart:async';

import 'serialization_util.dart';
import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '../../flutter_flow/flutter_flow_util.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';


final _handledMessageIds = <String?>{};

class PushNotificationsHandler extends StatefulWidget {
  const PushNotificationsHandler({super.key, required this.child});

  final Widget child;

  @override
  _PushNotificationsHandlerState createState() =>
      _PushNotificationsHandlerState();
}

class _PushNotificationsHandlerState extends State<PushNotificationsHandler> {
  bool _loading = false;

  Future handleOpenedPushNotification() async {
    if (isWeb) {
      return;
    }

    final notification = await FirebaseMessaging.instance.getInitialMessage();
    if (notification != null) {
      await _handlePushNotification(notification);
    }
    FirebaseMessaging.onMessageOpenedApp.listen(_handlePushNotification);
  }

  Future _handlePushNotification(RemoteMessage message) async {
    if (_handledMessageIds.contains(message.messageId)) {
      return;
    }
    _handledMessageIds.add(message.messageId);

    safeSetState(() => _loading = true);
    try {
      final initialPageName = message.data['initialPageName'] as String;
      final initialParameterData = getInitialParameterData(message.data);
      final parametersBuilder = parametersBuilderMap[initialPageName];
      if (parametersBuilder != null) {
        final parameterData = await parametersBuilder(initialParameterData);
        if (mounted) {
          context.pushNamed(
            initialPageName,
            pathParameters: parameterData.pathParameters,
            extra: parameterData.extra,
          );
        } else {
          appNavigatorKey.currentContext?.pushNamed(
            initialPageName,
            pathParameters: parameterData.pathParameters,
            extra: parameterData.extra,
          );
        }
      }
    } catch (e) {
      print('Error: $e');
    } finally {
      safeSetState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      handleOpenedPushNotification();
    });
    FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title ?? 'Notification';
      final body = message.notification?.body ?? '';
      print('FCM: onMessage id=${message.messageId} title="$title"');
      if (!mounted) return;
      final content = body.isEmpty ? title : '$title: $body';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(content)),
      );
    });
  }

  @override
  Widget build(BuildContext context) => _loading
      ? Container(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          child: Center(
            child: Image.asset(
              'assets/images/logo_D_secondaire.png',
              width: MediaQuery.sizeOf(context).width * 0.8,
              height: double.infinity,
              fit: BoxFit.scaleDown,
            ),
          ),
        )
      : widget.child;
}

class ParameterData {
  const ParameterData(
      {this.requiredParams = const {}, this.allParams = const {}});
  final Map<String, String?> requiredParams;
  final Map<String, dynamic> allParams;

  Map<String, String> get pathParameters => Map.fromEntries(
        requiredParams.entries
            .where((e) => e.value != null)
            .map((e) => MapEntry(e.key, e.value!)),
      );
  Map<String, dynamic> get extra => Map.fromEntries(
        allParams.entries.where((e) => e.value != null),
      );

  static Future<ParameterData> Function(Map<String, dynamic>) none() =>
      (data) async => const ParameterData();
}

final parametersBuilderMap =
    <String, Future<ParameterData> Function(Map<String, dynamic>)>{
  'HomeJoueurPage': ParameterData.none(),
  'LoginPage': ParameterData.none(),
  'InscriptionPage': ParameterData.none(),
  'InscriptionInformationsPage': ParameterData.none(),
  'ResetPassword': ParameterData.none(),
  'HomeCommercantPage': ParameterData.none(),
  'JeuxCommercantPage': ParameterData.none(),
  'StatCommercantPage': ParameterData.none(),
  'ProfilCommercantPage': ParameterData.none(),
  'ProfilJoueurPage': ParameterData.none(),
  'HomeAdminPage': ParameterData.none(),
  'JeuDetailCommercantPage': (data) async => ParameterData(
        allParams: {
          'gameDoc': await getDocumentParameter<GamesRecord>(
              data, 'gameDoc', GamesRecord.fromSnapshot),
          'enseigneDoc': await getDocumentParameter<EnseignesRecord>(
              data, 'enseigneDoc', EnseignesRecord.fromSnapshot),
        },
      ),
  'MesEnseignesCommercantPage': ParameterData.none(),
  'FavorisJoueurPage': ParameterData.none(),
  'EnseigneJoueurPage': ParameterData.none(),
  'InscriptionIdentityCardPage': ParameterData.none(),
  'InscriptionIdentityPhotoPage': ParameterData.none(),
  'WaitingValidationPage': ParameterData.none(),
  'EditCommercantPage': ParameterData.none(),
  'EditJoueurPage': ParameterData.none(),
  'AddEnseigneCommercantPage': ParameterData.none(),
  'AddHoraireCommercantPage': (data) async => ParameterData(
        allParams: {
          'enseigneRef': getParameter<DocumentReference>(data, 'enseigneRef'),
          'created': getParameter<bool>(data, 'created'),
        },
      ),
  'UpdateEnseigneCommercantPage': (data) async => ParameterData(
        allParams: {
          'enseigneDocument': await getDocumentParameter<EnseignesRecord>(
              data, 'enseigneDocument', EnseignesRecord.fromSnapshot),
        },
      ),
  'photoEnseigneCommercantPage': (data) async => ParameterData(
        allParams: {
          'enseigneRef': getParameter<DocumentReference>(data, 'enseigneRef'),
        },
      ),
  'AddGameCommercantPage': (data) async => ParameterData(
        allParams: {
          'enseigneRef': getParameter<DocumentReference>(data, 'enseigneRef'),
          'enseigne': getParameter<String>(data, 'enseigne'),
        },
      ),
  'SelectedEnseignesForAddGameCommercantPage': ParameterData.none(),
  'JeuDetailJoueurPage': (data) async => ParameterData(
        allParams: {
          'gameDoc': await getDocumentParameter<GamesRecord>(
              data, 'gameDoc', GamesRecord.fromSnapshot),
          'enseigneDoc': await getDocumentParameter<EnseignesRecord>(
              data, 'enseigneDoc', EnseignesRecord.fromSnapshot),
        },
      ),
  'EnseigneDetailJoueurPage': (data) async => ParameterData(
        allParams: {
          'enseigneDoc': await getDocumentParameter<EnseignesRecord>(
              data, 'enseigneDoc', EnseignesRecord.fromSnapshot),
        },
      ),
  'rejetInscriptionPage': ParameterData.none(),
  'LotsJoueurPage': ParameterData.none(),
  'lotDetailJoueurPage': (data) async => ParameterData(
        allParams: {
          'lot': await getDocumentParameter<PrizesRecord>(
              data, 'lot', PrizesRecord.fromSnapshot),
        },
      ),
  'ValidationLotCommercantPage': (data) async => ParameterData(
        allParams: {
          'prize': await getDocumentParameter<PrizesRecord>(
              data, 'prize', PrizesRecord.fromSnapshot),
        },
      ),
  'playJoueurPage': (data) async => ParameterData(
        allParams: {
          'game': await getDocumentParameter<GamesRecord>(
              data, 'game', GamesRecord.fromSnapshot),
        },
      ),
  'PartageJeuJoueurPage': (data) async => ParameterData(
        allParams: {
          'gameDoc': await getDocumentParameter<GamesRecord>(
              data, 'gameDoc', GamesRecord.fromSnapshot),
          'enseigneDoc': await getDocumentParameter<EnseignesRecord>(
              data, 'enseigneDoc', EnseignesRecord.fromSnapshot),
        },
      ),
  'ShareJeuPage': (data) async => ParameterData(
        allParams: {
          'gameDoc': await getDocumentParameter<GamesRecord>(
              data, 'gameDoc', GamesRecord.fromSnapshot),
          'enseigneDoc': await getDocumentParameter<EnseignesRecord>(
              data, 'enseigneDoc', EnseignesRecord.fromSnapshot),
        },
      ),
  'aboCommercantPage': ParameterData.none(),
  'SelectedAutoEnseignesForAddGameCommercantPage': ParameterData.none(),
  'contactPage': ParameterData.none(),
  'deleteCommAdminPage': ParameterData.none(),
  'legalPage': ParameterData.none(),
};

Map<String, dynamic> getInitialParameterData(Map<String, dynamic> data) {
  try {
    final parameterDataStr = data['parameterData'];
    if (parameterDataStr == null ||
        parameterDataStr is! String ||
        parameterDataStr.isEmpty) {
      return {};
    }
    return jsonDecode(parameterDataStr) as Map<String, dynamic>;
  } catch (e) {
    print('Error parsing parameter data: $e');
    return {};
  }
}
