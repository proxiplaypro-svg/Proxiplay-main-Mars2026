import 'dart:async';

import 'package:flutter/foundation.dart';

/// Outcome of a `participateInGameTransaction` call, decoupled from the
/// FlutterFlow-generated response type so [GameLaunchCoordinator] can be
/// unit-tested without Firebase.
///
/// IMPORTANT (see audit): by the time this outcome exists with
/// `succeeded == true`, the Cloud Function has already committed its
/// Firestore transaction — `remaining_part` is decremented and the
/// `participants` / `participants_details` docs are already written.
/// Nothing below this point can undo that from the client.
class GameParticipationOutcome {
  const GameParticipationOutcome({
    required this.succeeded,
    required this.alreadyParticipatedToday,
    this.errorMessage,
    this.errorCode,
    this.raw,
  });

  final bool succeeded;
  final bool alreadyParticipatedToday;
  final String? errorMessage;
  final String? errorCode;

  /// The original, page-specific response object (e.g.
  /// `ParticipateInGameTransactionCloudFunctionCallResponse`), carried
  /// through untyped so this file has no Firebase/FlutterFlow dependency.
  final Object? raw;

  bool get isNewParticipation => succeeded && !alreadyParticipatedToday;
}

/// Outcome of attempting to show the game screen after a participation was
/// confirmed server-side.
enum GameNavigationResult {
  /// The navigation call itself threw before a route could even be pushed
  /// (or the caller detected it could not proceed, e.g. widget unmounted).
  navigationFailed,

  /// Navigation succeeded and the game screen confirmed it rendered at
  /// least one frame before the mount timeout elapsed.
  mounted,

  /// Navigation succeeded but no mount confirmation arrived before the
  /// timeout elapsed. The participation is already committed server-side;
  /// this only means we have no proof the player ever saw it.
  mountTimedOut,
}

/// Centralizes the "launch a game" orchestration shared by every entry
/// point that calls `participateInGameTransaction` (jeu_detail_joueur_page,
/// share_jeu_page, QR scan, ...).
///
/// The Cloud Function commits the participation atomically and returns
/// only after that commit — see `participate_in_game_transaction.js`. This
/// coordinator cannot prevent that server-side consumption; its job is to:
///  - guarantee a single in-flight launch at a time (lock),
///  - never leave the lock stuck, whatever happens (timeout + finally),
///  - never let a caller surface a local "already played" state before the
///    game screen is actually shown,
///  - log every transition explicitly so a genuine incident (participation
///    consumed but never displayed) can be told apart from normal play.
class GameLaunchCoordinator {
  GameLaunchCoordinator({
    required this.screenName,
    this.participateTimeout = const Duration(seconds: 20),
    this.mountTimeout = const Duration(seconds: 8),
    void Function(String message)? logger,
  }) : _log = logger ?? debugPrint;

  final String screenName;
  final Duration participateTimeout;
  final Duration mountTimeout;
  final void Function(String message) _log;

  bool _isLaunching = false;
  bool get isLaunching => _isLaunching;

  void _logEvent(String gameId, String event, {String? detail}) {
    final suffix = (detail != null && detail.isNotEmpty) ? ' detail=$detail' : '';
    _log('[GAME_LAUNCH] screen=$screenName gameId=$gameId event=$event$suffix');
  }

  /// Attempts to launch a game for [gameId].
  ///
  /// Returns without throwing in every case; failures are reported through
  /// the optional callbacks so callers can show UI, while the lock is
  /// always released via `finally`.
  ///
  /// An `alreadyParticipatedToday` outcome is treated the same as a fresh
  /// participation for navigation purposes: the Cloud Function now caches
  /// the player's last real result (see `resolveCachedLastResult` server
  /// side) and hands it back instead of a dead-end message, so [navigate]
  /// is called either way and the game screen renders that real (or, for
  /// pre-fix data, generic fallback) outcome rather than blocking the
  /// player behind a dialog with nothing to show.
  Future<void> launch({
    required String gameId,
    required Future<GameParticipationOutcome> Function() participate,
    required Future<GameNavigationResult> Function(
      GameParticipationOutcome outcome,
    ) navigate,
    required void Function(bool isLaunching) onLaunchingChanged,
    Future<void> Function(GameParticipationOutcome outcome)?
        onParticipationError,
    Future<void> Function()? onNavigationFailed,
    void Function()? onMountTimedOut,
  }) async {
    if (_isLaunching) {
      _logEvent(gameId, 'lancement_ignore_deja_en_cours');
      return;
    }

    _isLaunching = true;
    onLaunchingChanged(true);
    _logEvent(gameId, 'lancement_demande');

    try {
      final outcome = await _participateWithTimeout(gameId, participate);

      if (!outcome.succeeded) {
        _logEvent(
          gameId,
          'lancement_echec_participation',
          detail: outcome.errorCode ?? outcome.errorMessage,
        );
        await onParticipationError?.call(outcome);
        return;
      }

      _logEvent(
        gameId,
        outcome.alreadyParticipatedToday
            ? 'deja_joue_relecture_resultat'
            : 'participation_confirmee_serveur',
      );

      final navigationResult = await navigate(outcome);
      switch (navigationResult) {
        case GameNavigationResult.navigationFailed:
          _logEvent(
            gameId,
            'lancement_erreur_navigation',
            detail: 'participation deja enregistree cote serveur, '
                'ecran de jeu non affiche',
          );
          await onNavigationFailed?.call();
          break;
        case GameNavigationResult.mounted:
          _logEvent(gameId, 'page_jeu_montee');
          break;
        case GameNavigationResult.mountTimedOut:
          _logEvent(
            gameId,
            'lancement_timeout_montage_page_jeu',
            detail: 'aucune confirmation visuelle recue, participation '
                'potentiellement invisible pour le joueur',
          );
          onMountTimedOut?.call();
          break;
      }
    } finally {
      _isLaunching = false;
      onLaunchingChanged(false);
      _logEvent(gameId, 'verrou_lancement_libere');
    }
  }

  Future<GameParticipationOutcome> _participateWithTimeout(
    String gameId,
    Future<GameParticipationOutcome> Function() participate,
  ) async {
    try {
      return await participate().timeout(participateTimeout);
    } on TimeoutException {
      _logEvent(gameId, 'lancement_timeout_appel_serveur');
      return const GameParticipationOutcome(
        succeeded: false,
        alreadyParticipatedToday: false,
        errorCode: 'timeout-client',
        errorMessage: 'Le serveur met trop de temps a repondre. Reessayez.',
      );
    } catch (error) {
      _logEvent(gameId, 'lancement_erreur_appel_serveur', detail: '$error');
      return GameParticipationOutcome(
        succeeded: false,
        alreadyParticipatedToday: false,
        errorCode: 'client-error',
        errorMessage: 'Une erreur est survenue.',
        raw: error,
      );
    }
  }

  /// Standard "push then wait (bounded) for mount confirmation" pattern on
  /// top of an imperative [Navigator.push]-style call.
  ///
  /// [push] must push the route and return its "on pop" future. [mountedBy]
  /// is a [Completer] the pushed screen must complete once it has rendered
  /// its first frame. [awaitReturn] is invoked with the push future once we
  /// know whether it mounted, and should contain any work that must only
  /// happen after the player has actually returned from the game screen
  /// (e.g. refreshing locally-cached "already played" state).
  static Future<GameNavigationResult> runNavigation({
    required Completer<void> mountedBy,
    required Future<void> Function() push,
    required Duration mountTimeout,
    required Future<void> Function(Future<void> pushFuture) awaitReturn,
  }) async {
    final Future<void> pushFuture;
    try {
      pushFuture = push();
    } catch (_) {
      return GameNavigationResult.navigationFailed;
    }

    // `push` may itself be `async` and reject later rather than throwing
    // synchronously (e.g. the route builder fails). Turn that into a flag
    // instead of an unhandled rejection, without losing the error for the
    // "already mounted, something odd happened after" case below.
    var pushFailed = false;
    final safePushFuture = pushFuture.catchError((Object _, StackTrace __) {
      pushFailed = true;
    });

    final didMount = await mountedBy.future
        .then((_) => true)
        .timeout(mountTimeout, onTimeout: () => false);

    await awaitReturn(safePushFuture);

    if (pushFailed && !didMount) {
      return GameNavigationResult.navigationFailed;
    }

    return didMount
        ? GameNavigationResult.mounted
        : GameNavigationResult.mountTimedOut;
  }
}
