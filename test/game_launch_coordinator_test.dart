import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/game_launch_coordinator.dart';

/// These tests exercise [GameLaunchCoordinator] directly with fake
/// participate/navigate callbacks instead of the real Firebase-backed
/// widgets. This mirrors the project's existing convention of testing
/// extracted pure logic with plain `flutter_test` (see
/// `test/account_routing_test.dart`) rather than pumping the full
/// FlutterFlow widget tree, which depends on Firebase, Rive, audio and
/// camera plugins that aren't available in this environment (the Firestore
/// emulator itself is currently blocked here by a Java version mismatch).
void main() {
  group('GameLaunchCoordinator', () {
    late GameLaunchCoordinator coordinator;
    late List<bool> launchingChanges;
    late List<String> logs;

    setUp(() {
      launchingChanges = [];
      logs = [];
      coordinator = GameLaunchCoordinator(
        screenName: 'TestScreen',
        participateTimeout: const Duration(milliseconds: 200),
        mountTimeout: const Duration(milliseconds: 60),
        logger: logs.add,
      );
    });

    GameParticipationOutcome winOutcome({Object? raw}) =>
        GameParticipationOutcome(
          succeeded: true,
          alreadyParticipatedToday: false,
          raw: raw,
        );

    GameParticipationOutcome alreadyPlayedOutcome() =>
        const GameParticipationOutcome(
          succeeded: true,
          alreadyParticipatedToday: true,
        );

    GameParticipationOutcome errorOutcome() => const GameParticipationOutcome(
          succeeded: false,
          alreadyParticipatedToday: false,
          errorCode: 'internal',
          errorMessage: 'boom',
        );

    Future<GameNavigationResult> immediateMount(
      GameParticipationOutcome _,
    ) async {
      final mountedBy = Completer<void>();
      return GameLaunchCoordinator.runNavigation(
        mountedBy: mountedBy,
        mountTimeout: const Duration(milliseconds: 60),
        push: () async {
          mountedBy.complete();
          return;
        },
        awaitReturn: (pushFuture) => pushFuture,
      );
    }

    test('lancement normal: happy path mounts and releases the lock',
        () async {
      var participateCalls = 0;
      var navigateCalls = 0;

      await coordinator.launch(
        gameId: 'game-1',
        onLaunchingChanged: launchingChanges.add,
        participate: () async {
          participateCalls++;
          return winOutcome();
        },
        navigate: (outcome) async {
          navigateCalls++;
          return immediateMount(outcome);
        },
      );

      expect(participateCalls, 1);
      expect(navigateCalls, 1);
      expect(coordinator.isLaunching, isFalse);
      expect(launchingChanges, [true, false]);
      expect(
        logs.any((l) => l.contains('event=participation_confirmee_serveur')),
        isTrue,
      );
      expect(logs.any((l) => l.contains('event=page_jeu_montee')), isTrue);
      expect(
        logs.any((l) => l.contains('event=verrou_lancement_libere')),
        isTrue,
      );
    });

    test('double clic rapide: second call is ignored while the first is in flight',
        () async {
      var participateCalls = 0;
      final firstCallStarted = Completer<void>();
      final releaseFirstCall = Completer<void>();

      final firstLaunch = coordinator.launch(
        gameId: 'game-1',
        onLaunchingChanged: launchingChanges.add,
        participate: () async {
          participateCalls++;
          firstCallStarted.complete();
          await releaseFirstCall.future;
          return winOutcome();
        },
        navigate: immediateMount,
      );

      await firstCallStarted.future;
      expect(coordinator.isLaunching, isTrue);

      // Second tap while the first participate() call is still pending.
      final secondLaunch = coordinator.launch(
        gameId: 'game-1',
        onLaunchingChanged: launchingChanges.add,
        participate: () async {
          participateCalls++;
          return winOutcome();
        },
        navigate: immediateMount,
      );

      await secondLaunch;
      expect(
        participateCalls,
        1,
        reason: 'the second tap must not trigger a second server call',
      );
      expect(
        logs.any((l) => l.contains('event=lancement_ignore_deja_en_cours')),
        isTrue,
      );

      releaseFirstCall.complete();
      await firstLaunch;
      expect(participateCalls, 1);
      expect(coordinator.isLaunching, isFalse);
    });

    test('navigation échouée: lock is released and onNavigationFailed fires',
        () async {
      var navigationFailedCalls = 0;

      await coordinator.launch(
        gameId: 'game-1',
        onLaunchingChanged: launchingChanges.add,
        participate: () async => winOutcome(),
        navigate: (outcome) async => GameLaunchCoordinator.runNavigation(
          mountedBy: Completer<void>(),
          mountTimeout: const Duration(milliseconds: 60),
          push: () async => throw Exception('navigator threw'),
          awaitReturn: (pushFuture) => pushFuture,
        ),
        onNavigationFailed: () async => navigationFailedCalls++,
      );

      expect(navigationFailedCalls, 1);
      expect(coordinator.isLaunching, isFalse);
      expect(launchingChanges, [true, false]);
      expect(
        logs.any((l) => l.contains('event=lancement_erreur_navigation')),
        isTrue,
      );
      // A navigation failure must never be logged/treated as a mount.
      expect(logs.any((l) => l.contains('event=page_jeu_montee')), isFalse);
    });

    test(
        'écran de jeu qui ne se monte pas: timeout is reported and lock is still released',
        () async {
      var mountTimedOutCalls = 0;

      await coordinator.launch(
        gameId: 'game-1',
        onLaunchingChanged: launchingChanges.add,
        participate: () async => winOutcome(),
        navigate: (outcome) async => GameLaunchCoordinator.runNavigation(
          mountedBy: Completer<void>(), // never completed: screen never mounts
          mountTimeout: const Duration(milliseconds: 30),
          push: () async {},
          awaitReturn: (pushFuture) => pushFuture,
        ),
        onMountTimedOut: () => mountTimedOutCalls++,
      );

      expect(mountTimedOutCalls, 1);
      expect(coordinator.isLaunching, isFalse);
      expect(launchingChanges, [true, false]);
      expect(
        logs.any(
          (l) => l.contains('event=lancement_timeout_montage_page_jeu'),
        ),
        isTrue,
      );
    });

    test('retour arrière immédiat: mount then immediate pop still refreshes and releases the lock',
        () async {
      var afterReturnRan = false;

      await coordinator.launch(
        gameId: 'game-1',
        onLaunchingChanged: launchingChanges.add,
        participate: () async => winOutcome(),
        navigate: (outcome) async {
          final mountedBy = Completer<void>();
          return GameLaunchCoordinator.runNavigation(
            mountedBy: mountedBy,
            mountTimeout: const Duration(milliseconds: 60),
            push: () async {
              mountedBy.complete();
            },
            awaitReturn: (pushFuture) async {
              await pushFuture; // simulates the user popping immediately
              afterReturnRan = true;
            },
          );
        },
      );

      expect(afterReturnRan, isTrue);
      expect(coordinator.isLaunching, isFalse);
      expect(logs.any((l) => l.contains('event=page_jeu_montee')), isTrue);
    });

    test(
        'deuxième tentative sur un jeu réellement déjà joué: no navigation, dialog callback fires',
        () async {
      var navigateCalls = 0;
      var alreadyPlayedCalls = 0;

      await coordinator.launch(
        gameId: 'game-1',
        onLaunchingChanged: launchingChanges.add,
        participate: () async => alreadyPlayedOutcome(),
        navigate: (outcome) async {
          navigateCalls++;
          return immediateMount(outcome);
        },
        onAlreadyPlayed: (outcome) async => alreadyPlayedCalls++,
      );

      expect(navigateCalls, 0,
          reason: 'a genuinely already-played game must never navigate');
      expect(alreadyPlayedCalls, 1);
      expect(coordinator.isLaunching, isFalse);
      expect(
        logs.any((l) => l.contains('event=lancement_refuse_deja_joue')),
        isTrue,
      );
    });

    test('server error: lock is released and onParticipationError fires',
        () async {
      var errorCalls = 0;

      await coordinator.launch(
        gameId: 'game-1',
        onLaunchingChanged: launchingChanges.add,
        participate: () async => errorOutcome(),
        navigate: immediateMount,
        onParticipationError: (outcome) async {
          errorCalls++;
          expect(outcome.errorCode, 'internal');
        },
      );

      expect(errorCalls, 1);
      expect(coordinator.isLaunching, isFalse);
      expect(
        logs.any((l) => l.contains('event=lancement_echec_participation')),
        isTrue,
      );
    });

    test('server hang: participate timeout releases the lock without navigating',
        () async {
      var navigateCalls = 0;
      var errorCalls = 0;

      await coordinator.launch(
        gameId: 'game-1',
        onLaunchingChanged: launchingChanges.add,
        participate: () async {
          // Never completes within participateTimeout (200ms).
          await Future<void>.delayed(const Duration(seconds: 5));
          return winOutcome();
        },
        navigate: (outcome) async {
          navigateCalls++;
          return immediateMount(outcome);
        },
        onParticipationError: (outcome) async {
          errorCalls++;
          expect(outcome.errorCode, 'timeout-client');
        },
      );

      expect(navigateCalls, 0);
      expect(errorCalls, 1);
      expect(coordinator.isLaunching, isFalse);
      expect(
        logs.any((l) => l.contains('event=lancement_timeout_appel_serveur')),
        isTrue,
      );
    });
  });
}
