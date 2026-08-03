import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import '/config/firebase_environment.dart';
import '/firebase_options.dart';

Future<FirebaseApp>? _initFirebaseFuture;
bool _firestoreSettingsConfigured = false;
bool _devEmulatorsConfigured = false;
String? _configuredDevEmulatorHost;

Future<FirebaseApp> initFirebase() {
  final inFlight = _initFirebaseFuture;
  if (inFlight != null) {
    return inFlight;
  }

  final future = _initFirebaseInternal();
  _initFirebaseFuture = future;
  return future;
}

Future<FirebaseApp> _initFirebaseInternal() async {
  try {
    final environment = await FirebaseEnvironment.load();
    final app = Firebase.apps.isEmpty
        ? await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          )
        : Firebase.app();

    if (environment.isDev) {
      await _configureDevEmulators(
        app: app,
        environment: environment,
      );
    }

    if (!_firestoreSettingsConfigured && !kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      _firestoreSettingsConfigured = true;
    }

    final options = app.options;
    debugPrint(
      'FIREBASE INIT projectId=${options.projectId} '
      'appId=${options.appId} '
      'messagingSenderId=${options.messagingSenderId}',
    );

    return app;
  } catch (error) {
    _initFirebaseFuture = null;
    rethrow;
  }
}

Future<void> _configureDevEmulators({
  required FirebaseApp app,
  required FirebaseEnvironment environment,
}) async {
  final host = environment.resolvedEmulatorHost;

  if (_devEmulatorsConfigured) {
    if (_configuredDevEmulatorHost != host) {
      throw StateError(
        'Firebase emulators are already configured for '
        '$_configuredDevEmulatorHost in this isolate, cannot reconfigure '
        'to $host.',
      );
    }
    return;
  }

  try {
    await FirebaseAuth.instance.useAuthEmulator(
      host,
      FirebaseEnvironment.authPort,
    );
    FirebaseFirestore.instance.useFirestoreEmulator(
      host,
      FirebaseEnvironment.firestorePort,
    );
    FirebaseFunctions.instanceFor(
      region: FirebaseEnvironment.functionsRegion,
    ).useFunctionsEmulator(
      host,
      FirebaseEnvironment.functionsPort,
    );

    _devEmulatorsConfigured = true;
    _configuredDevEmulatorHost = host;

    debugPrint(
      'APP_ENV=dev projectId=${app.options.projectId} '
      'emulatorHost=$host auth=${FirebaseEnvironment.authPort} '
      'firestore=${FirebaseEnvironment.firestorePort} '
      'functions=${FirebaseEnvironment.functionsPort} '
      'region=${FirebaseEnvironment.functionsRegion}',
    );
  } catch (error, stackTrace) {
    debugPrint('DEV FIREBASE EMULATOR CONFIGURATION FAILED');
    debugPrint('error=$error');
    debugPrint('stackTrace=$stackTrace');
    try {
      await app.delete();
    } catch (deleteError) {
      debugPrint('DEV FIREBASE EMULATOR CLEANUP FAILED error=$deleteError');
    }
    rethrow;
  }
}
