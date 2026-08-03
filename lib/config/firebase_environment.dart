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
  });

  static const String appEnvDefine =
      String.fromEnvironment('APP_ENV', defaultValue: 'prod');
  static const String emulatorHostDefine =
      String.fromEnvironment('EMULATOR_HOST', defaultValue: '');

  static const int authPort = 9099;
  static const int firestorePort = 8080;
  static const int functionsPort = 5001;
  static const String functionsRegion = 'us-central1';

  final AppEnvironment appEnvironment;
  final FirebaseRuntimePlatform runtimePlatform;
  final String emulatorHostOverride;

  bool get isDev => appEnvironment == AppEnvironment.dev;
  bool get isProd => appEnvironment == AppEnvironment.prod;
  bool get shouldUseEmulators => isDev;

  String? get emulatorHostOrNull {
    final trimmed = emulatorHostOverride.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String get resolvedEmulatorHost {
    final explicitHost = emulatorHostOrNull;
    if (explicitHost != null) {
      return explicitHost;
    }

    if (!isDev) {
      throw StateError(
        'resolvedEmulatorHost is only available when APP_ENV=dev.',
      );
    }

    switch (runtimePlatform.platform) {
      case FirebaseTargetPlatform.web:
        return '127.0.0.1';
      case FirebaseTargetPlatform.android:
        if (runtimePlatform.isPhysicalDevice == false) {
          return '10.0.2.2';
        }
        throw StateError(
          'APP_ENV=dev on a physical Android device requires '
          '--dart-define=EMULATOR_HOST=<reachable-lan-ip>. '
          'No fallback to Firebase production is allowed.',
        );
      case FirebaseTargetPlatform.ios:
        if (runtimePlatform.isPhysicalDevice == false) {
          return '127.0.0.1';
        }
        throw StateError(
          'APP_ENV=dev on a physical iOS device requires '
          '--dart-define=EMULATOR_HOST=<reachable-lan-ip>. '
          'No fallback to Firebase production is allowed.',
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
  }) {
    return FirebaseEnvironment(
      appEnvironment: parseAppEnvironment(appEnv),
      runtimePlatform: runtimePlatform,
      emulatorHostOverride: emulatorHost ?? '',
    );
  }

  static Future<FirebaseEnvironment> load() async {
    final runtimePlatform = await FirebaseRuntimePlatform.detect();
    return fromValues(
      appEnv: appEnvDefine,
      emulatorHost: emulatorHostDefine,
      runtimePlatform: runtimePlatform,
    );
  }
}
