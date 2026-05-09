import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/nav/nav.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/utils/share_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class GameLaunchPageWidget extends StatelessWidget {
  const GameLaunchPageWidget({
    super.key,
    required this.gameId,
  });

  final String? gameId;

  static String routeName = 'GameLaunchPage';
  static String routePath = 'j/:gameId';

  @override
  Widget build(BuildContext context) {
    return _GameLaunchScreen(gameId: gameId);
  }
}

class GameLaunchSchemePageWidget extends StatelessWidget {
  const GameLaunchSchemePageWidget({
    super.key,
    required this.gameId,
  });

  final String? gameId;

  static String routeName = 'GameLaunchSchemePage';
  static String routePath = 'game/:gameId';

  @override
  Widget build(BuildContext context) {
    return _GameLaunchScreen(gameId: gameId);
  }
}

class _GameLaunchScreen extends StatefulWidget {
  const _GameLaunchScreen({
    required this.gameId,
  });

  final String? gameId;

  @override
  State<_GameLaunchScreen> createState() => _GameLaunchScreenState();
}

class _GameLaunchScreenState extends State<_GameLaunchScreen> {
  bool _didRedirectToLogin = false;
  bool _didNavigateToGame = false;
  bool _didLogAuthWaitMs = false;
  final Stopwatch _authWaitStopwatch = Stopwatch()..start();

  String get _gameId => (widget.gameId ?? '').trim();

  bool get _authStateResolved => AppStateNotifier.instance.hasResolvedAuthState;
  bool get _isAuthenticatedInApp =>
      !kIsWeb &&
      ((AppStateNotifier.instance.loggedIn &&
              currentUserUid.isNotEmpty &&
              !isGuestOrAnonymous) ||
          (FirebaseAuth.instance.currentUser != null && !isGuestOrAnonymous));
  bool get _requiresLoginInApp =>
      !kIsWeb && _authStateResolved && !_isAuthenticatedInApp;

  @override
  void initState() {
    super.initState();
    debugPrint('[QR_DEEPLINK_RECEIVED] gameId=$_gameId uri=${Uri.base.toString()}');
    debugPrint(
      '[QR_AUTH_STATE_ON_DEEPLINK] isLoggedIn=$_isAuthenticatedInApp authResolved=$_authStateResolved',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncDeepLinkFlow();
    });
  }

  void _syncDeepLinkFlow() {
    if (!mounted || _gameId.isEmpty || kIsWeb) {
      return;
    }
    debugPrint(
      '[QR_AUTH_STATE_ON_DEEPLINK] isLoggedIn=$_isAuthenticatedInApp authResolved=$_authStateResolved',
    );
    if (!_authStateResolved) {
      return;
    }
    if (!_didLogAuthWaitMs) {
      _didLogAuthWaitMs = true;
      _authWaitStopwatch.stop();
      debugPrint('[QR_AUTH_WAIT_MS] ${_authWaitStopwatch.elapsedMilliseconds}ms');
    }
    if (_isAuthenticatedInApp && _didRedirectToLogin) {
      debugPrint('[QR_UNEXPECTED_LOGIN_WHILE_AUTHENTICATED] gameId=$_gameId');
      return;
    }
    _maybeRedirectToLogin();
  }

  void _maybeRedirectToLogin() {
    if (!mounted ||
        !_requiresLoginInApp ||
        _didRedirectToLogin ||
        _gameId.isEmpty) {
      return;
    }
    _didRedirectToLogin = true;
    FFAppState().pendingDeepLinkGameId = _gameId;
    debugPrint('[DEEPLINK_AUTH_REQUIRED] gameId=$_gameId');
    GoRouter.of(context).setRedirectLocationIfUnset('/j/$_gameId');
    context.goNamed(LoginPageWidget.routeName);
  }

  Future<void> _openInApp() async {
    if (_gameId.isEmpty) {
      return;
    }
    final deepLinkUrl = buildGameDeepLink(_gameId);
    debugPrint('[QR_LINK_NATIVE_ATTEMPT] url=$deepLinkUrl');
    await launchUrl(
      Uri.parse(deepLinkUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _openStore(String url) async {
    if (url.trim().isEmpty) {
      return;
    }
    await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _maybeOpenNativeGame(GamesRecord? game) async {
    if (kIsWeb ||
        _didNavigateToGame ||
        !_authStateResolved ||
        _requiresLoginInApp ||
        game == null ||
        !mounted) {
      return;
    }
    _didNavigateToGame = true;
    FFAppState().clearPendingDeepLinkGameId();
    GoRouter.of(context).clearRedirectLocation();

    EnseignesRecord? enseigneDoc;
    final enseigneRef = game.enseigneId;
    if (enseigneRef != null) {
      try {
        enseigneDoc = await EnseignesRecord.getDocumentOnce(enseigneRef);
      } catch (_) {
        enseigneDoc = null;
      }
    }

    if (!mounted) {
      return;
    }
    debugPrint('[QR_OPEN_GAME_AUTHENTICATED] gameId=${game.reference.id}');
    context.goNamed(
      JeuDetailJoueurPageWidget.routeName,
      extra: <String, dynamic>{
        'gameDoc': game,
        'enseigneDoc': enseigneDoc,
        'source': 'qr_link',
      },
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required Future<void> Function() onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () async => onPressed(),
        style: ElevatedButton.styleFrom(
          backgroundColor: FlutterFlowTheme.of(context).primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
        ),
        child: Text(
          label,
          style: FlutterFlowTheme.of(context).titleSmall.override(
                font: GoogleFonts.interTight(
                  fontWeight: FontWeight.w700,
                  fontStyle: FlutterFlowTheme.of(context).titleSmall.fontStyle,
                ),
                color: Colors.white,
                letterSpacing: 0.0,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required String label,
    required String url,
  }) {
    final isEnabled = url.trim().isNotEmpty;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: isEnabled ? () async => _openStore(url) : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          side: BorderSide(
            color: FlutterFlowTheme.of(context).alternate,
          ),
        ),
        child: Text(
          label,
          style: FlutterFlowTheme.of(context).bodyMedium.override(
                font: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                ),
                letterSpacing: 0.0,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncDeepLinkFlow();
    });
    final gameRef = _gameId.isEmpty ? null : GamesRecord.collection.doc(_gameId);

    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520.0),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: FlutterFlowTheme.of(context).secondaryBackground,
                  borderRadius: BorderRadius.circular(24.0),
                ),
                child: StreamBuilder<DocumentSnapshot>(
                  stream: gameRef != null ? gameRef.snapshots() : null,
                  builder: (context, snapshot) {
                    final gameDoc = snapshot.data;
                    final game = gameDoc != null && gameDoc.exists
                        ? GamesRecord.fromSnapshot(gameDoc)
                        : null;
                    if (game != null) {
                      _maybeOpenNativeGame(game);
                    }

                    final isMissingGame = snapshot.connectionState ==
                            ConnectionState.active &&
                        (gameDoc == null || !gameDoc.exists);
                    if (isMissingGame) {
                      debugPrint('[DEEPLINK_GAME_NOT_FOUND] gameId=$_gameId');
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Image.asset(
                            'assets/images/logo_D_secondaire.png',
                            height: 56.0,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 24.0),
                        Text(
                          'Ouvrir ce jeu dans Proxiplay',
                          style: FlutterFlowTheme.of(context)
                              .headlineMedium
                              .override(
                                font: GoogleFonts.interTight(
                                  fontWeight: FontWeight.w700,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .headlineMedium
                                      .fontStyle,
                                ),
                                letterSpacing: 0.0,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 12.0),
                        Text(
                          isMissingGame
                              ? 'Ce jeu est indisponible pour le moment.'
                              : 'Ce lien ouvre un jeu Proxiplay. Ouvrez l application pour acceder directement au jeu, ou telechargez Proxiplay si elle n est pas encore installee.',
                          style: FlutterFlowTheme.of(context)
                              .bodyMedium
                              .override(
                                font: GoogleFonts.inter(
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .fontStyle,
                                ),
                                letterSpacing: 0.0,
                              ),
                        ),
                        if (_gameId.isNotEmpty) ...[
                          const SizedBox(height: 12.0),
                          SelectableText(
                            buildGameQrLink(_gameId),
                            style: FlutterFlowTheme.of(context)
                                .bodySmall
                                .override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .bodySmall
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodySmall
                                        .fontStyle,
                                  ),
                                  color:
                                      FlutterFlowTheme.of(context).secondaryText,
                                  letterSpacing: 0.0,
                                ),
                          ),
                        ],
                        const SizedBox(height: 24.0),
                        _buildPrimaryButton(
                          label: 'Ouvrir dans l application',
                          onPressed: _openInApp,
                        ),
                        const SizedBox(height: 12.0),
                        _buildSecondaryButton(
                          label: 'Telecharger Proxiplay',
                          url: Theme.of(context).platform == TargetPlatform.iOS
                              ? proxiplayIosStoreUrl
                              : proxiplayAndroidStoreUrl,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
