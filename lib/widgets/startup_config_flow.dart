import 'dart:async';

import 'package:flutter/material.dart';

class StartupConfigResult {
  const StartupConfigResult({
    required this.maintenanceMode,
    this.usedFallback = false,
    this.error,
    this.stackTrace,
    this.fromTimeout = false,
  });

  const StartupConfigResult.fallback({
    this.maintenanceMode = false,
    this.error,
    this.stackTrace,
    this.fromTimeout = false,
  }) : usedFallback = true;

  final bool maintenanceMode;
  final bool usedFallback;
  final Object? error;
  final StackTrace? stackTrace;
  final bool fromTimeout;
}

typedef StartupConfigLoader = Future<StartupConfigResult> Function();

enum StartupConfigPhase {
  loading,
  ready,
  error,
}

class StartupConfigViewState {
  const StartupConfigViewState._({
    required this.phase,
    required this.result,
  });

  const StartupConfigViewState.loading()
      : this._(
          phase: StartupConfigPhase.loading,
          result: const StartupConfigResult(maintenanceMode: false),
        );

  const StartupConfigViewState.ready(StartupConfigResult result)
      : this._(
          phase: StartupConfigPhase.ready,
          result: result,
        );

  const StartupConfigViewState.error(StartupConfigResult result)
      : this._(
          phase: StartupConfigPhase.error,
          result: result,
        );

  final StartupConfigPhase phase;
  final StartupConfigResult result;

  bool get isLoading => phase == StartupConfigPhase.loading;
  bool get isReady => phase == StartupConfigPhase.ready;
  bool get hasError => phase == StartupConfigPhase.error;
}

Future<StartupConfigViewState> resolveStartupConfigState({
  required StartupConfigLoader loader,
  required Duration timeout,
  bool allowFallbackOnFailure = true,
  StartupConfigResult fallbackResult = const StartupConfigResult.fallback(),
}) async {
  try {
    final result = await loader().timeout(timeout);
    if (result.error != null && !allowFallbackOnFailure) {
      return StartupConfigViewState.error(result);
    }
    if (result.error != null && result.usedFallback && allowFallbackOnFailure) {
      return StartupConfigViewState.ready(result);
    }
    return StartupConfigViewState.ready(result);
  } on TimeoutException catch (error, stackTrace) {
    final timeoutFallback = StartupConfigResult.fallback(
      maintenanceMode: fallbackResult.maintenanceMode,
      error: error,
      stackTrace: stackTrace,
      fromTimeout: true,
    );
    return allowFallbackOnFailure
        ? StartupConfigViewState.ready(timeoutFallback)
        : StartupConfigViewState.error(timeoutFallback);
  } catch (error, stackTrace) {
    final runtimeFallback = StartupConfigResult.fallback(
      maintenanceMode: fallbackResult.maintenanceMode,
      error: error,
      stackTrace: stackTrace,
    );
    return allowFallbackOnFailure
        ? StartupConfigViewState.ready(runtimeFallback)
        : StartupConfigViewState.error(runtimeFallback);
  }
}

class StartupConfigLoadingScreen extends StatelessWidget {
  const StartupConfigLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/icon.png',
                  width: 96.0,
                  height: 96.0,
                ),
                const SizedBox(height: 20.0),
                const SizedBox(
                  width: 28.0,
                  height: 28.0,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: Color(0xFF2C2F5B),
                  ),
                ),
                const SizedBox(height: 18.0),
                Text(
                  'Préparation de ProxiPlay...',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1F2937),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StartupConfigRetryScreen extends StatelessWidget {
  const StartupConfigRetryScreen({
    super.key,
    required this.onRetry,
  });

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/icon.png',
                  width: 96.0,
                  height: 96.0,
                ),
                const SizedBox(height: 20.0),
                Text(
                  'Impossible de préparer l’application.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1F2937),
                      ),
                ),
                const SizedBox(height: 12.0),
                Text(
                  'Vérifiez votre connexion puis réessayez.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF4B5563),
                      ),
                ),
                const SizedBox(height: 20.0),
                ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C2F5B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22.0,
                      vertical: 14.0,
                    ),
                  ),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
