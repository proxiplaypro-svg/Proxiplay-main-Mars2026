import '/custom_code/actions/index.dart' as actions;
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
// --- AJOUT : Import pour savoir si on est sur le Web (kIsWeb) ---
import 'package:flutter/foundation.dart' show kIsWeb; 
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
import 'flutter_flow/nav/nav.dart';

import 'services/remote_config_service.dart';
import 'pages/status_screens/maintenance_screen.dart';
import 'pages/status_screens/update_required_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await initFirebase();
  await FirebasePersistenceManager().initializePersistence();
  debugPrint('FCM: background message id=${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoRouter.optionURLReflectsImperativeAPIs = true;
  usePathUrlStrategy();

  await initFirebase();
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // Start initial custom actions code
  await actions.lockOrientationScreen();
  await actions.appTracking();
  // End initial custom actions code

  final appState = FFAppState(); // Initialize FFAppState
  await appState.initializePersistedState();

  runApp(ChangeNotifierProvider(
    create: (context) => appState,
    child: MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  // This widget is the root of your application.
  @override
  State<MyApp> createState() => _MyAppState();

  static _MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>()!;
}

class _MyAppState extends State<MyApp> {
  Locale? _locale;
  ThemeMode _themeMode = ThemeMode.system;

  late AppStateNotifier _appStateNotifier;
  late GoRouter _router;

  bool _isLoadingConfig = true;
  bool _isMaintenance = false;
  bool _isUpdateRequired = false;

  StreamSubscription<BaseAuthUser>? _userStreamSub;

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

  final authUserSub = authenticatedUserStream.listen((_) {});
  final fcmTokenSub = fcmTokenUserStream.listen((_) {});

  @override
  void initState() {
    super.initState();

    _appStateNotifier = AppStateNotifier.instance;
    _router = createRouter(_appStateNotifier);
    userStream = proxiPlayFirebaseUserStream();
    _userStreamSub = userStream.listen((user) {
      _appStateNotifier.update(user);
    });
    jwtTokenStream.listen((_) {});

    // Vérification au démarrage (Fonctionne sur Web et Mobile)
    _checkRemoteConfig();

    // --- CORRECTION WEB ---
    // On n'active l'écouteur temps réel QUE si nous ne sommes PAS sur le Web.
    if (!kIsWeb) {
      FirebaseRemoteConfig.instance.onConfigUpdated.listen((event) async {
        await FirebaseRemoteConfig.instance.activate();
        
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkRemoteConfig(); 
          });
        }
        debugPrint("Mise à jour Remote Config appliquée en temps réel.");
      });
    }
    // -----------------------

    Future.delayed(
      const Duration(milliseconds: 2000),
      () => _appStateNotifier.stopShowingSplashImage(),
    );
  }

  Future<void> _checkRemoteConfig() async {
    final remoteService = RemoteConfigService();
    
    // Initialisation
    await remoteService.initialize();

    bool maintenance = remoteService.isMaintenanceMode;
    bool updateNeeded = false;

    if (!maintenance) {
      updateNeeded = remoteService.isUpdateRequired();
    }

    if (mounted) {
      setState(() {
        _isMaintenance = maintenance;
        _isUpdateRequired = updateNeeded;
        _isLoadingConfig = false;
      });
    }
  }

  @override
  void dispose() {
    authUserSub.cancel();
    fcmTokenSub.cancel();
    _userStreamSub?.cancel();
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
    // 1. Chargement
    if (_isLoadingConfig) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          backgroundColor: Colors.white, 
          body: const Center(child: CircularProgressIndicator())
        )
      );
    }

    // 2. Blocage Maintenance
    if (_isMaintenance) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MaintenanceScreen(),
      );
    }

    // 3. Blocage Mise à jour requise
    if (_isUpdateRequired) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: UpdateRequiredScreen(),
      );
    }

    // 4. Application Normale
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
          (l) => l.languageCode.toLowerCase() == deviceLocale.languageCode.toLowerCase(),
        );
        return isSupported ? deviceLocale : const Locale('fr');
      },
      theme: ThemeData(
        brightness: Brightness.light,
      ),
      themeMode: _themeMode,
      routerConfig: _router,
    );
  }
}