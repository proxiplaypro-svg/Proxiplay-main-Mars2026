import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/widgets/startup_config_flow.dart';

void main() {
  group('resolveStartupConfigState', () {
    test('uses fallback ready state on error when fallback is allowed', () async {
      final state = await resolveStartupConfigState(
        loader: () async => throw StateError('boom'),
        timeout: const Duration(milliseconds: 50),
        allowFallbackOnFailure: true,
      );

      expect(state.isReady, isTrue);
      expect(state.result.usedFallback, isTrue);
      expect(state.result.error, isA<StateError>());
    });

    test('returns blocking error state on timeout when fallback is disabled', () async {
      final completer = Completer<StartupConfigResult>();

      final state = await resolveStartupConfigState(
        loader: () => completer.future,
        timeout: const Duration(milliseconds: 10),
        allowFallbackOnFailure: false,
      );

      expect(state.hasError, isTrue);
      expect(state.result.usedFallback, isTrue);
      expect(state.result.fromTimeout, isTrue);
    });
  });

  group('Startup config UI', () {
    testWidgets('shows app when configuration loads immediately',
        (tester) async {
      await tester.pumpWidget(
        _StartupConfigHarness(
          loader: () async => const StartupConfigResult(
            maintenanceMode: false,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('App prête'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows visible loading state while configuration is slow',
        (tester) async {
      final completer = Completer<StartupConfigResult>();

      await tester.pumpWidget(
        _StartupConfigHarness(
          loader: () => completer.future,
          timeout: const Duration(seconds: 1),
        ),
      );

      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Préparation de ProxiPlay...'), findsOneWidget);

      completer.complete(const StartupConfigResult(maintenanceMode: false));
      await tester.pumpAndSettle();

      expect(find.text('App prête'), findsOneWidget);
    });

    testWidgets('opens the app with a safe fallback when configuration fails',
        (tester) async {
      await tester.pumpWidget(
        _StartupConfigHarness(
          loader: () async => throw StateError('remote config failed'),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('App prête'), findsOneWidget);
      expect(find.text('Mode secours actif'), findsOneWidget);
    });

    testWidgets('opens the app with a safe fallback when configuration times out',
        (tester) async {
      final completer = Completer<StartupConfigResult>();

      await tester.pumpWidget(
        _StartupConfigHarness(
          loader: () => completer.future,
          timeout: const Duration(milliseconds: 50),
        ),
      );

      await tester.pump();
      expect(find.text('Préparation de ProxiPlay...'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();

      expect(find.text('App prête'), findsOneWidget);
      expect(find.text('Mode secours actif'), findsOneWidget);
    });

    testWidgets('retry succeeds after a blocking startup failure',
        (tester) async {
      var attempt = 0;

      await tester.pumpWidget(
        _StartupConfigHarness(
          allowFallbackOnFailure: false,
          loader: () async {
            attempt += 1;
            if (attempt == 1) {
              throw StateError('first failure');
            }
            return const StartupConfigResult(maintenanceMode: false);
          },
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Impossible de préparer l’application.'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Réessayer'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Réessayer'));
      await tester.pump();
      expect(
        find.text('Préparation de ProxiPlay...').evaluate().isNotEmpty ||
            find.text('App prête').evaluate().isNotEmpty,
        isTrue,
      );

      await tester.pumpAndSettle();
      expect(find.text('App prête'), findsOneWidget);
      expect(attempt, 2);
    });

    testWidgets('never renders a blank screen in covered scenarios',
        (tester) async {
      final completer = Completer<StartupConfigResult>();

      await tester.pumpWidget(
        _StartupConfigHarness(
          allowFallbackOnFailure: false,
          loader: () => completer.future,
          timeout: const Duration(milliseconds: 200),
        ),
      );

      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.completeError(StateError('still failing'));
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();

      expect(find.text('Impossible de préparer l’application.'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Réessayer'), findsOneWidget);
    });
  });
}

class _StartupConfigHarness extends StatefulWidget {
  const _StartupConfigHarness({
    required this.loader,
    this.timeout = const Duration(milliseconds: 200),
    this.allowFallbackOnFailure = true,
  });

  final StartupConfigLoader loader;
  final Duration timeout;
  final bool allowFallbackOnFailure;

  @override
  State<_StartupConfigHarness> createState() => _StartupConfigHarnessState();
}

class _StartupConfigHarnessState extends State<_StartupConfigHarness> {
  StartupConfigViewState _state = const StartupConfigViewState.loading();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _state = const StartupConfigViewState.loading();
      });
    }

    final resolvedState = await resolveStartupConfigState(
      loader: widget.loader,
      timeout: widget.timeout,
      allowFallbackOnFailure: widget.allowFallbackOnFailure,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _state = resolvedState;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: switch (_state.phase) {
        StartupConfigPhase.loading => const StartupConfigLoadingScreen(),
        StartupConfigPhase.error => StartupConfigRetryScreen(
            onRetry: () {
              unawaited(_load());
            },
          ),
        StartupConfigPhase.ready => Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('App prête'),
                  if (_state.result.usedFallback)
                    const Text('Mode secours actif'),
                ],
              ),
            ),
          ),
      },
    );
  }
}
