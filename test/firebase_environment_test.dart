import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/config/firebase_environment.dart';

void main() {
  group('FirebaseEnvironment', () {
    test('empty environment defaults to PROD', () {
      final environment = FirebaseEnvironment.fromValues(
        appEnv: null,
        emulatorHost: null,
        runtimePlatform: const FirebaseRuntimePlatform.web(),
      );

      expect(environment.appEnvironment, AppEnvironment.prod);
      expect(environment.isProd, isTrue);
      expect(environment.shouldUseEmulators, isFalse);
    });

    test('APP_ENV=prod stays in PROD', () {
      final environment = FirebaseEnvironment.fromValues(
        appEnv: 'prod',
        emulatorHost: null,
        runtimePlatform: const FirebaseRuntimePlatform.web(),
      );

      expect(environment.appEnvironment, AppEnvironment.prod);
      expect(environment.shouldUseEmulators, isFalse);
    });

    test('APP_ENV=dev alone does not enable emulators', () {
      final environment = FirebaseEnvironment.fromValues(
        appEnv: 'dev',
        emulatorHost: null,
        runtimePlatform: const FirebaseRuntimePlatform.web(),
      );

      expect(environment.appEnvironment, AppEnvironment.dev);
      expect(environment.shouldUseEmulators, isFalse);
    });

    test('explicit EMULATOR_HOST takes priority', () {
      final environment = FirebaseEnvironment.fromValues(
        appEnv: 'dev',
        emulatorHost: '192.168.1.20',
        useFirebaseEmulators: true,
        runtimePlatform: const FirebaseRuntimePlatform.android(
          isPhysicalDevice: true,
        ),
      );

      expect(environment.resolvedEmulatorHost, '192.168.1.20');
    });

    test('Android emulator resolves to 10.0.2.2', () {
      final environment = FirebaseEnvironment.fromValues(
        appEnv: 'dev',
        emulatorHost: null,
        useFirebaseEmulators: true,
        runtimePlatform: const FirebaseRuntimePlatform.android(
          isPhysicalDevice: false,
        ),
      );

      expect(environment.resolvedEmulatorHost, '10.0.2.2');
    });

    test('iOS simulator resolves to 127.0.0.1', () {
      final environment = FirebaseEnvironment.fromValues(
        appEnv: 'dev',
        emulatorHost: null,
        useFirebaseEmulators: true,
        runtimePlatform: const FirebaseRuntimePlatform.ios(
          isPhysicalDevice: false,
        ),
      );

      expect(environment.resolvedEmulatorHost, '127.0.0.1');
    });

    test('Web resolves to 127.0.0.1', () {
      final environment = FirebaseEnvironment.fromValues(
        appEnv: 'dev',
        emulatorHost: null,
        useFirebaseEmulators: true,
        runtimePlatform: const FirebaseRuntimePlatform.web(),
      );

      expect(environment.resolvedEmulatorHost, '127.0.0.1');
    });

    test('unsupported platform throws a clear error in DEV', () {
      final environment = FirebaseEnvironment.fromValues(
        appEnv: 'dev',
        emulatorHost: null,
        useFirebaseEmulators: true,
        runtimePlatform: const FirebaseRuntimePlatform.unsupported(
          label: 'windows',
        ),
      );

      expect(
        () => environment.resolvedEmulatorHost,
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('Android, iOS, and Web'),
          ),
        ),
      );
    });

    test('physical Android uses loopback for adb reverse', () {
      final environment = FirebaseEnvironment.fromValues(
        appEnv: 'dev',
        emulatorHost: null,
        useFirebaseEmulators: true,
        runtimePlatform: const FirebaseRuntimePlatform.android(
          isPhysicalDevice: true,
        ),
      );

      expect(environment.resolvedEmulatorHost, '127.0.0.1');
    });

    test('PROD never enables emulators', () {
      final environment = FirebaseEnvironment.fromValues(
        appEnv: 'prod',
        emulatorHost: '127.0.0.1',
        runtimePlatform: const FirebaseRuntimePlatform.web(),
      );

      expect(environment.shouldUseEmulators, isFalse);
      expect(environment.isDev, isFalse);
    });
  });
}
