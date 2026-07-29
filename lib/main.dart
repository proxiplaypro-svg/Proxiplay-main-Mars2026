import '/custom_code/actions/index.dart' as actions;
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
// --- AJOUT : Import pour savoir si on est sur le Web (kIsWeb) ---
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'dart:io' show Platform;
// ----------------------------------------------------------------

import 'dart:async';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'auth/firebase_auth/firebase_user_provider.dart';
import 'auth/firebase_auth/auth_util.dart';
import 'auth/firebase_auth/firebase_persistence.dart';

import 'backend/push_notifications/push_notifications_util.dart';
import 'backend/firebase/firebase_config.dart';
import 'flutter_flow/flutter_flow_util.dart';
import 'flutter_flow/internationalization.dart';
import 'flutter_flow/permissions_util.dart';
import 'package:permission_handler/permission_handler.dart';
import 'utils/perf_trace.dart';
import 'utils/share_links.dart';
import 'widgets/startup_config_flow.dart';

import 'services/remote_config_service.dart';
import 'services/global_ticker_service.dart';
import 'pages/status_screens/maintenance_screen.dart';
import 'widgets/app_update_gate.dart';

class AppBootstrapResult {
  const AppBootstrapResult({
    required this.appState,
    required this.firebaseInitialized,
    this.bootstrapError,
    this.bootstrapStackTrace,
  });

  final FFAppState appState;
  final bool firebaseInitialized;
  final Object? bootstrapError;
  final StackTrace? bootstrapStackTrace;
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await initFirebase();
  await FirebasePersistenceManager().initializePersistence();
}

void main() async {
  PerfTrace.log('APP_START');
  WidgetsFlutterBinding.ensureInitialized();

  // Filet de securite global : si un widget plante pendant sa construction
  // (donnee malformee, reference vers un document supprime, etc.), on
  // affiche ce message plutot que la boite rouge/grise par defaut de
  // Flutter, qui peut laisser l'ecran ephemere de jeu (ScratchCardWidget)
  // vide ou casse sans aucune explication pour le joueur.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('[UI_BUILD_ERROR] ${details.exception}');
    if (kDebugMode) {
      return ErrorWidget(details.exception);
    }
    return Container(
      color: Colors.white,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24.0),
      child: const Text(
        'Un problème est survenu. Réessayez.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF4B5563), fontSize: 14.0),
      ),
    );
  };

  GoRouter.optionURLReflectsImperativeAPIs = true;
  usePathUrlStrategy();

  final appState = FFAppState(); // Initialize FFAppState
  Object? bootstrapError;
  StackTrace? bootstrapStackTrace;
  var firebaseInitialized = false;

  try {
    await initFirebase().timeout(const Duration(seconds: 12));
    firebaseInitialized = true;
  } catch (error, stackTrace) {
    bootstrapError = error;
    bootstrapStackTrace = stackTrace;
    debugPrint('[APP_BOOTSTRAP] firebase_init_failed error=$error');
    debugPrint('[APP_BOOTSTRAP] firebase_init_stack=$stackTrace');
  }

  try {
    await appState
        .initializePersistedState()
        .timeout(const Duration(seconds: 5));
  } catch (error, stackTrace) {
    bootstrapError ??= error;
    bootstrapStackTrace ??= stackTrace;
    debugPrint('[APP_BOOTSTRAP] prefs_init_failed error=$error');
    debugPrint('[APP_BOOTSTRAP] prefs_init_stack=$stackTrace');
  }

  runApp(ChangeNotifierProvider(
    create: (context) => appState,
    child: MyApp(
      bootstrapResult: AppBootstrapResult(
        appState: appState,
        firebaseInitialized: firebaseInitialized,
        bootstrapError: bootstrapError,
        bootstrapStackTrace: bootstrapStackTrace,
      ),
    ),
  ));

  unawaited(() async {
    if (!firebaseInitialized) {
      return;
    }
    try {
      final tickerSnapshot = await const GlobalTickerService().fetchOnce();
      if (tickerSnapshot == null) {
        return;
      }
      appState.update(() {
        appState.setGlobalTickerData(
          totalPlayers: tickerSnapshot.totalPlayers,
          totalGamesPlayed: tickerSnapshot.totalGamesPlayed,
          totalMerchants: tickerSnapshot.totalMerchants,
          messages: tickerSnapshot.messages,
          updatedAt: tickerSnapshot.updatedAt,
        );
      });
    } catch (error) {
      debugPrint('[GlobalTicker] startup_load_failed error=$error');
    }
  }());

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  unawaited(actions.lockOrientationScreen());
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.bootstrapResult,
  });

  final AppBootstrapResult bootstrapResult;

  // This widget is the root of your application.
  @override
  State<MyApp> createState() => MyAppState();

  static MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<MyAppState>()!;
}

class MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _fallbackNavigatorKey =
      GlobalKey<NavigatorState>();

  Locale? _locale;
  ThemeMode _themeMode = ThemeMode.system;

  late AppStateNotifier _appStateNotifier;
  late GoRouter _router;

  bool _isLoadingConfig = true;
  bool _isMaintenance = false;
  bool _hasBlockingConfigError = false;
  Object? _lastConfigError;

  StreamSubscription<BaseAuthUser>? _userStreamSub;
  StreamSubscription<dynamic>? _authUserSub;
  StreamSubscription<dynamic>? _fcmTokenSub;
  VoidCallback? _routerReferralListener;
  String? _lastReferralLocation;

  String getRoute([RouteMatch? routeMatch]) {
    final RouteMatch lastMatch =
        routeMatch ?? _router.routerDelegate.currentConfiguration.last;
    final RouteMatchList matchList = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches
        : _router.routerDelegate.currentConfiguration;
    return matchList.uri.toString();
  }

  List<String> getRouteStack() =>
      _router.routerDelegate.currentConfiguration.matches
          .map((e) => getRoute(e))
          .toList();
  late Stream<BaseAuthUser> userStream;

  @override
  void initState() {
    super.initState();

    _appStateNotifier = AppStateNotifier.instance;
    _router = createRouter(_appStateNotifier);
    if (!widget.bootstrapResult.firebaseInitialized) {
      return;
    }
    _authUserSub = authenticatedUserStream.listen((_) {
      if (!mounted) {
        return;
      }
      _appStateNotifier.refreshRouting();
    });
    _fcmTokenSub = fcmTokenUserStream.listen((_) {});
    _routerReferralListener = () {
      _capturePendingReferralCodeFromRouter(source: 'warm_start');
    };
    _router.routerDelegate.addListener(_routerReferralListener!);
    userStream = proxiPlayFirebaseUserStream();
    _userStreamSub = userStream.listen((user) {
      _appStateNotifier.update(user);
    });
    jwtTokenStream.listen((_) {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _capturePendingReferralCodeFromRouter(source: 'cold_start');
    });

    // Vérification au démarrage (Fonctionne sur Web et Mobile)
    _checkRemoteConfig();

    // Request notification permission on Android 13+ at startup.
    Future.delayed(const Duration(milliseconds: 1500), () async {
      if (!kIsWeb && Platform.isAndroid) {
        final status = await notificationsPermission.status;
        if (status.isDenied || status.isRestricted) {
          await notificationsPermission.request();
        }
      }
    });

    // --- CORRECTION WEB ---
    // On n'active l'écouteur temps réel QUE si nous ne sommes PAS sur le Web.
    if (!kIsWeb) {
      FirebaseRemoteConfig.instance.onConfigUpdated.listen((event) async {
        await FirebaseRemoteConfig.instance.activate();

        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkRemoteConfig(showBlockingLoader: false);
          });
        }
      });
    }
    // -----------------------

    Future.delayed(
      const Duration(milliseconds: 2000),
      () => _appStateNotifier.stopShowingSplashImage(),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 800), () async {
        if (!mounted) {
          return;
        }
        try {
          await actions.appTracking();
        } catch (error, stackTrace) {
          debugPrint('[APP_BOOTSTRAP] app_tracking_failed error=$error');
          debugPrint('[APP_BOOTSTRAP] app_tracking_stack=$stackTrace');
        }
      });
    });
  }

  Future<void> _checkRemoteConfig({bool showBlockingLoader = true}) async {
    final remoteService = RemoteConfigService();
    final previousMaintenance = _isMaintenance;

    if (showBlockingLoader && mounted) {
      setState(() {
        _isLoadingConfig = true;
        _hasBlockingConfigError = false;
      });
    }

    final resolvedState = await resolveStartupConfigState(
      loader: () async {
        final initResult = await remoteService.initialize();
        return StartupConfigResult(
          maintenanceMode: remoteService.isMaintenanceMode,
          usedFallback: !initResult.loadedFromRemote,
          error: initResult.error,
          stackTrace: initResult.stackTrace,
        );
      },
      timeout: const Duration(seconds: 8),
      allowFallbackOnFailure: true,
    );

    final shouldPreserveCurrentConfig =
        !showBlockingLoader && resolvedState.result.usedFallback;
    final maintenance = shouldPreserveCurrentConfig
        ? previousMaintenance
        : resolvedState.result.maintenanceMode;

    if (resolvedState.result.error != null) {
      debugPrint(
        '[APP_BOOTSTRAP] remote_config_fallback '
        'timeout=${resolvedState.result.fromTimeout} '
        'error=${resolvedState.result.error}',
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isMaintenance = maintenance;
      _isLoadingConfig = false;
      _hasBlockingConfigError = resolvedState.hasError;
      _lastConfigError = resolvedState.result.error;
    });
  }

  void _capturePendingReferralCodeFromRouter({required String source}) {
    if (!mounted) {
      return;
    }
    if (currentUserUid.isNotEmpty && !isGuestOrAnonymous) {
      return;
    }

    final location = _router.getCurrentLocation();
    final isNewLocation = _lastReferralLocation != location;
    if (isNewLocation) {
      _lastReferralLocation = location;
    }
    final uri = Uri.tryParse(location);
    final referralCode = extractReferralCodeFromUri(uri);
    if (referralCode == null || referralCode.isEmpty) {
      return;
    }
    if (FFAppState().pendingReferralCode == referralCode) {
      return;
    }

    FFAppState().update(() {
      FFAppState().pendingReferralCode = referralCode;
    });
  }

  @override
  void dispose() {
    _authUserSub?.cancel();
    _fcmTokenSub?.cancel();
    _userStreamSub?.cancel();
    if (_routerReferralListener != null) {
      _router.routerDelegate.removeListener(_routerReferralListener!);
    }
    super.dispose();
  }

  void setLocale(String language) {
    safeSetState(() => _locale = createLocale(language));
  }

  void setThemeMode(ThemeMode mode) => safeSetState(() {
        _themeMode = mode;
      });

  @override
  Widget build(BuildContext context) {
    if (!widget.bootstrapResult.firebaseInitialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _StartupFailureScreen(
          error: widget.bootstrapResult.bootstrapError,
          stackTrace: widget.bootstrapResult.bootstrapStackTrace,
        ),
      );
    }

    // 1. Chargement
    if (_isLoadingConfig) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: _fallbackNavigatorKey,
        home: AppUpdateGate(
          navigatorKey: _fallbackNavigatorKey,
          child: const StartupConfigLoadingScreen(),
        ),
      );
    }

    if (_hasBlockingConfigError) {
      debugPrint(
        '[APP_BOOTSTRAP] startup_config_blocking_error error=$_lastConfigError',
      );
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: _fallbackNavigatorKey,
        home: AppUpdateGate(
          navigatorKey: _fallbackNavigatorKey,
          child: StartupConfigRetryScreen(
            onRetry: () {
              unawaited(_checkRemoteConfig());
            },
          ),
        ),
      );
    }

    // 2. Blocage Maintenance
    if (_isMaintenance) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: _fallbackNavigatorKey,
        home: AppUpdateGate(
          navigatorKey: _fallbackNavigatorKey,
          child: const MaintenanceScreen(),
        ),
      );
    }

    // 3. Blocage Mise à jour requise
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'ProxiPlay',
      localizationsDelegates: const [
        FFLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FallbackMaterialLocalizationDelegate(),
        FallbackCupertinoLocalizationDelegate(),
      ],
      // Force a safe fallback: this project only declares `fr` as supported.
      // Without this, Android devices/emulators set to en_US trigger a warning
      // and can break some generated localization lookups.
      locale: _locale ?? const Locale('fr'),
      supportedLocales: const [
        Locale('fr'),
      ],
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        // Always fallback to French if device locale isn't supported.
        if (deviceLocale == null) return const Locale('fr');
        final isSupported = supportedLocales.any(
          (l) =>
              l.languageCode.toLowerCase() ==
              deviceLocale.languageCode.toLowerCase(),
        );
        return isSupported ? deviceLocale : const Locale('fr');
      },
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: false,
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Colors.transparent,
          circularTrackColor: Colors.transparent,
          linearTrackColor: Colors.transparent,
          refreshBackgroundColor: Colors.transparent,
        ),
      ),
      themeMode: _themeMode,
      builder: (context, child) => AppUpdateGate(
        navigatorKey: _router.routerDelegate.navigatorKey,
        child: child ?? const SizedBox.shrink(),
      ),
      routerConfig: _router,
    );
  }
}

class _StartupFailureScreen extends StatelessWidget {
  const _StartupFailureScreen({
    required this.error,
    required this.stackTrace,
  });

  final Object? error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) {
    debugPrint('[APP_BOOTSTRAP] startup_screen_shown error=$error');
    if (stackTrace != null) {
      debugPrint('[APP_BOOTSTRAP] startup_screen_stack=$stackTrace');
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Center(
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
                  'L’application n’a pas pu démarrer correctement.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1F2937),
                      ),
                ),
                const SizedBox(height: 12.0),
                Text(
                  'Fermez puis relancez Proxiplay. Si le problème persiste, vérifiez votre connexion et réessayez.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF4B5563),
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
