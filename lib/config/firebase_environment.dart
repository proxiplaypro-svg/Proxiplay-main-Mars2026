import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

enum AppEnvironment {
  prod,
  dev,
}

enum FirebaseTargetPlatform {
  android,
  ios,
  web,
  unsupported,
}

class FirebaseRuntimePlatform {
  const FirebaseRuntimePlatform._({
    required this.platform,
    required this.label,
    this.isPhysicalDevice,
  });

  const FirebaseRuntimePlatform.web()
      : this._(
          platform: FirebaseTargetPlatform.web,
          label: 'web',
        );

  const FirebaseRuntimePlatform.android({
    required bool isPhysicalDevice,
  }) : this._(
          platform: FirebaseTargetPlatform.android,
          label: 'android',
          isPhysicalDevice: isPhysicalDevice,
        );

  const FirebaseRuntimePlatform.ios({
    required bool isPhysicalDevice,
  }) : this._(
          platform: FirebaseTargetPlatform.ios,
          label: 'ios',
          isPhysicalDevice: isPhysicalDevice,
        );

  const FirebaseRuntimePlatform.unsupported({
    required String label,
  }) : this._(
          platform: FirebaseTargetPlatform.unsupported,
          label: label,
        );

  final FirebaseTargetPlatform platform;
  final String label;
  final bool? isPhysicalDevice;

  static Future<FirebaseRuntimePlatform> detect() async {
    if (kIsWeb) {
      return const FirebaseRuntimePlatform.web();
    }

    final deviceInfo = DeviceInfoPlugin();
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final info = await deviceInfo.androidInfo;
        return FirebaseRuntimePlatform.android(
          isPhysicalDevice: info.isPhysicalDevice,
        );
      case TargetPlatform.iOS:
        final info = await deviceInfo.iosInfo;
        return FirebaseRuntimePlatform.ios(
          isPhysicalDevice: info.isPhysicalDevice,
        );
      default:
        return FirebaseRuntimePlatform.unsupported(
          label: defaultTargetPlatform.name,
        );
    }
  }
}

class FirebaseEnvironment {
  const FirebaseEnvironment({
    required this.appEnvironment,
    required this.runtimePlatform,
    required this.emulatorHostOverride,
    required this.emulatorModeRequested,
  });

  static const String appEnvDefine =
      String.fromEnvironment('APP_ENV', defaultValue: 'prod');
  static const String emulatorHostDefine =
      String.fromEnvironment('EMULATOR_HOST', defaultValue: '');
  static const bool emulatorModeDefine = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
    defaultValue: false,
  );

  static const int authPort = 9099;
  static const int firestorePort = 8080;
  static const int functionsPort = 5001;
  static const int storagePort = 9199;
  static const String functionsRegion = 'us-central1';

  final AppEnvironment appEnvironment;
  final FirebaseRuntimePlatform runtimePlatform;
  final String emulatorHostOverride;
  final bool emulatorModeRequested;

  bool get isDev => appEnvironment == AppEnvironment.dev;
  bool get isProd => appEnvironment == AppEnvironment.prod;
  // This must remain opt-in. APP_ENV=dev alone must never redirect Firebase.
  bool get shouldUseEmulators => emulatorModeRequested && kDebugMode;

  static bool get isLocalEmulatorMode => emulatorModeDefine && kDebugMode;

  String? get emulatorHostOrNull {
    final trimmed = emulatorHostOverride.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String get resolvedEmulatorHost {
    final explicitHost = emulatorHostOrNull;
    if (explicitHost != null) {
      return explicitHost;
    }

    if (!shouldUseEmulators) {
      throw StateError(
        'resolvedEmulatorHost is only available with '
        'USE_FIREBASE_EMULATORS=true in a debug build.',
      );
    }

    switch (runtimePlatform.platform) {
      case FirebaseTargetPlatform.web:
        return '127.0.0.1';
      case FirebaseTargetPlatform.android:
        // On a USB device, `adb reverse` maps its loopback interface to the
        // workstation. An explicit EMULATOR_HOST still supports LAN testing.
        return runtimePlatform.isPhysicalDevice == false
            ? '10.0.2.2'
            : '127.0.0.1';
      case FirebaseTargetPlatform.ios:
        if (runtimePlatform.isPhysicalDevice == false) {
          return '127.0.0.1';
        }
        throw StateError(
          'A physical iOS device requires --dart-define=EMULATOR_HOST='
          '<reachable-lan-ip> when USE_FIREBASE_EMULATORS=true.',
        );
      case FirebaseTargetPlatform.unsupported:
        throw UnsupportedError(
          'APP_ENV=dev is only supported on Android, iOS, and Web. '
          'Current platform: ${runtimePlatform.label}.',
        );
    }
  }

  static AppEnvironment parseAppEnvironment(String? rawValue) {
    final normalized = (rawValue ?? '').trim().toLowerCase();
    return normalized == 'dev' ? AppEnvironment.dev : AppEnvironment.prod;
  }

  static FirebaseEnvironment fromValues({
    required String? appEnv,
    required String? emulatorHost,
    required FirebaseRuntimePlatform runtimePlatform,
    bool useFirebaseEmulators = false,
  }) {
    return FirebaseEnvironment(
      appEnvironment: parseAppEnvironment(appEnv),
      runtimePlatform: runtimePlatform,
      emulatorHostOverride: emulatorHost ?? '',
      emulatorModeRequested: useFirebaseEmulators,
    );
  }

  static Future<FirebaseEnvironment> load() async {
    final runtimePlatform = await FirebaseRuntimePlatform.detect();
    return fromValues(
      appEnv: appEnvDefine,
      emulatorHost: emulatorHostDefine,
      runtimePlatform: runtimePlatform,
      useFirebaseEmulators: emulatorModeDefine,
    );
  }
}
