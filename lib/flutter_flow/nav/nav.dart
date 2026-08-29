import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';

import '/backend/push_notifications/push_notifications_handler.dart'
    show PushNotificationsHandler;
import '/auth/firebase_auth/auth_util.dart';
import '/auth/firebase_auth/account_routing.dart';
import '/auth/firebase_auth/account_routing_logic.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/utils/share_links.dart';

import '/index.dart';

export 'package:go_router/go_router.dart';
export 'serialization_util.dart';

const kTransitionInfoKey = '__transition_info__';

GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

String describeRouteForLog(Route<dynamic>? route) {
  if (route == null) {
    return 'null';
  }
  final settings = route.settings;
  final name = settings.name;
  final args = settings.arguments;
  return 'name=${name ?? 'null'} runtimeType=${route.runtimeType} '
      'isCurrent=${route.isCurrent} isActive=${route.isActive} '
      'args=${args ?? 'null'}';
}

String describeContextRouteForLog(BuildContext context) {
  final modalRoute = ModalRoute.of(context);
  if (modalRoute == null) {
    return 'null';
  }
  return describeRouteForLog(modalRoute);
}

void logGlobalNavigation({
  required String action,
  required BuildContext context,
  required String destination,
}) {}

class GlobalNavObserver extends NavigatorObserver {
  void _logEvent(
    String event, {
    Route<dynamic>? route,
    Route<dynamic>? previousRoute,
    Route<dynamic>? oldRoute,
    Route<dynamic>? newRoute,
  }) {}

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _logEvent('didPush', route: route, previousRoute: previousRoute);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _logEvent('didPop', route: route, previousRoute: previousRoute);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _logEvent('didRemove', route: route, previousRoute: previousRoute);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _logEvent('didReplace', newRoute: newRoute, oldRoute: oldRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

String? _extractDeepLinkGameId(Uri uri) =>
    extractDeepLinkGameId(uri, customScheme: proxiplayCustomScheme);

class AppStateNotifier extends ChangeNotifier {
  static const Duration _authResolutionTimeout = Duration(seconds: 3);

  AppStateNotifier._();

  static AppStateNotifier? _instance;
  static AppStateNotifier get instance => _instance ??= AppStateNotifier._();

  BaseAuthUser? initialUser;
  BaseAuthUser? user;
  bool showSplashImage = true;
  String? _redirectLocation;
  bool _hasResolvedAuthState = false;
  int _criticalImperativeNavigationDepth = 0;
  bool _hasDeferredRouterRefresh = false;
  Timer? _authResolutionTimer;
  StreamSubscription<User?>? _authResolutionSub;

  /// Determines whether the app will refresh and build again when a sign
  /// in or sign out happens. This is useful when the app is launched or
  /// on an unexpected logout. However, this must be turned off when we
  /// intend to sign in/out and then navigate or perform any actions after.
  /// Otherwise, this will trigger a refresh and interrupt the action(s).
  bool notifyOnAuthChange = true;

  bool get loading => !_hasResolvedAuthState || showSplashImage;
  bool get hasResolvedAuthState => _hasResolvedAuthState;
  bool get loggedIn => (user?.loggedIn ?? false) || FFAppState().isGuest;
  bool get initiallyLoggedIn =>
      (initialUser?.loggedIn ?? false) || FFAppState().isGuest;
  bool get shouldRedirect => loggedIn && _redirectLocation != null;

  String getRedirectLocation() => _redirectLocation!;
  String? get debugRedirectLocation => _redirectLocation;
  bool hasRedirect() => _redirectLocation != null;
  void setRedirectLocationIfUnset(String loc) {
    _redirectLocation ??= loc;
  }

  void clearRedirectLocation() {
    _redirectLocation = null;
  }

  /// Mark as not needing to notify on a sign in / out when we intend
  /// to perform subsequent actions (such as navigation) afterwards.
  void updateNotifyOnAuthChange(bool notify) => notifyOnAuthChange = notify;

  void _notifyRouterListeners() {
    if (_criticalImperativeNavigationDepth > 0) {
      _hasDeferredRouterRefresh = true;
      return;
    }
    notifyListeners();
  }

  void beginCriticalImperativeNavigation() {
    _criticalImperativeNavigationDepth += 1;
  }

  void endCriticalImperativeNavigation() {
    if (_criticalImperativeNavigationDepth <= 0) {
      _criticalImperativeNavigationDepth = 0;
      return;
    }

    _criticalImperativeNavigationDepth -= 1;
    if (_criticalImperativeNavigationDepth == 0 && _hasDeferredRouterRefresh) {
      _hasDeferredRouterRefresh = false;
      notifyListeners();
    }
  }

  Future<T> runWithCriticalImperativeNavigation<T>(
    Future<T> Function() action,
  ) async {
    beginCriticalImperativeNavigation();
    try {
      return await action();
    } finally {
      endCriticalImperativeNavigation();
    }
  }

  void _cancelAuthResolutionWatch() {
    _authResolutionTimer?.cancel();
    _authResolutionTimer = null;
    _authResolutionSub?.cancel();
    _authResolutionSub = null;
  }

  void _resolveAuthState() {
    _cancelAuthResolutionWatch();
    _hasResolvedAuthState = true;
  }

  void _startAuthResolutionWatch() {
    if (_hasResolvedAuthState ||
        _authResolutionTimer != null ||
        _authResolutionSub != null) {
      return;
    }

    _authResolutionSub = FirebaseAuth.instance.idTokenChanges().listen((user) {
      if (user == null || _hasResolvedAuthState) {
        return;
      }
      _resolveAuthState();
      if (notifyOnAuthChange) {
        _notifyRouterListeners();
      }
    });

    _authResolutionTimer = Timer(_authResolutionTimeout, () {
      _authResolutionTimer = null;
      if (_hasResolvedAuthState) {
        return;
      }
      _resolveAuthState();
      if (notifyOnAuthChange) {
        _notifyRouterListeners();
      }
    });
  }

  void update(BaseAuthUser newUser) {
    final shouldUpdate =
        user?.uid == null || newUser.uid == null || user?.uid != newUser.uid;
    final previousResolvedState = _hasResolvedAuthState;
    initialUser ??= newUser;
    user = newUser;

    if (newUser.loggedIn || FirebaseAuth.instance.currentUser != null) {
      _resolveAuthState();
    } else if (!_hasResolvedAuthState) {
      _startAuthResolutionWatch();
    }

    // Refresh the app on auth change unless explicitly marked otherwise.
    // No need to update unless the user has changed.
    if (notifyOnAuthChange &&
        (shouldUpdate || previousResolvedState != _hasResolvedAuthState)) {
      _notifyRouterListeners();
    }
    // Once again mark the notifier as needing to update on auth change
    // (in order to catch sign in / out events).
    updateNotifyOnAuthChange(true);
  }

  void refreshRouting() {
    _notifyRouterListeners();
  }

  void stopShowingSplashImage() {
    showSplashImage = false;
    _notifyRouterListeners();
  }
}

GoRouter createRouter(AppStateNotifier appStateNotifier) => GoRouter(
      initialLocation: '/',
      debugLogDiagnostics: false,
      refreshListenable: appStateNotifier,
      navigatorKey: appNavigatorKey,
      observers: [
        GlobalNavObserver(),
      ],
      errorBuilder: (context, state) => appStateNotifier.loggedIn
          ? const LoginPageWidget()
          : const LoginPageWidget(),
      routes: [
        FFRoute(
          name: '_initialize',
          path: '/',
          builder: (context, _) => appStateNotifier.loggedIn
              ? const LoginPageWidget()
              : const LoginPageWidget(),
          routes: [
            FFRoute(
              name: GameLaunchPageWidget.routeName,
              path: GameLaunchPageWidget.routePath,
              builder: (context, params) => GameLaunchPageWidget(
                gameId: params.getParam(
                  'gameId',
                  ParamType.String,
                ),
              ),
            ),
            FFRoute(
              name: GameLaunchSchemePageWidget.routeName,
              path: GameLaunchSchemePageWidget.routePath,
              builder: (context, params) => GameLaunchSchemePageWidget(
                gameId: params.getParam(
                  'gameId',
                  ParamType.String,
                ),
              ),
            ),
            FFRoute(
              name: HomeJoueurPageWidget.routeName,
              path: HomeJoueurPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => const HomeJoueurPageWidget(),
            ),
            FFRoute(
              name: AnimationDetailPage.routeName,
              path: AnimationDetailPage.routePath,
              requireAuth: true,
              builder: (context, params) => AnimationDetailPage(
                animationId: params.getParam(
                      'animationId',
                      ParamType.String,
                    ) ??
                    '',
              ),
            ),
            FFRoute(
              name: LoginPageWidget.routeName,
              path: LoginPageWidget.routePath,
              builder: (context, params) => const LoginPageWidget(),
            ),
            FFRoute(
              name: InscriptionPageWidget.routeName,
              path: InscriptionPageWidget.routePath,
              builder: (context, params) => const InscriptionPageWidget(),
            ),
            FFRoute(
              name: InscriptionInformationsPageWidget.routeName,
              path: InscriptionInformationsPageWidget.routePath,
              // This page writes to the current user's Firestore doc; it should
              // only be reachable when authenticated.
              requireAuth: true,
              builder: (context, params) =>
                  const InscriptionInformationsPageWidget(),
            ),
            FFRoute(
              name: ResetPasswordWidget.routeName,
              path: ResetPasswordWidget.routePath,
              builder: (context, params) => const ResetPasswordWidget(),
            ),
            FFRoute(
              name: HomeCommercantPageWidget.routeName,
              path: HomeCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              builder: (context, params) => const HomeCommercantPageWidget(),
            ),
            FFRoute(
              name: JeuxCommercantPageWidget.routeName,
              path: JeuxCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              builder: (context, params) => const JeuxCommercantPageWidget(),
            ),
            FFRoute(
              name: StatCommercantPageWidget.routeName,
              path: StatCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              builder: (context, params) => const StatCommercantPageWidget(),
            ),
            FFRoute(
              name: ProfilCommercantPageWidget.routeName,
              path: ProfilCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              builder: (context, params) => const ProfilCommercantPageWidget(),
            ),
            FFRoute(
              name: ProfilJoueurPageWidget.routeName,
              path: ProfilJoueurPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => const ProfilJoueurPageWidget(),
            ),
            FFRoute(
              name: HomeAdminPageWidget.routeName,
              path: HomeAdminPageWidget.routePath,
              requireAuth: true,
              requireAdmin: true,
              builder: (context, params) => const HomeAdminPageWidget(),
            ),
            FFRoute(
              name: AdminNotificationsCenterPageWidget.routeName,
              path: AdminNotificationsCenterPageWidget.routePath,
              requireAuth: true,
              requireAdmin: true,
              builder: (context, params) =>
                  const AdminNotificationsCenterPageWidget(),
            ),
            FFRoute(
              name: ValidationCommercantsAdminPageWidget.routeName,
              path: ValidationCommercantsAdminPageWidget.routePath,
              requireAuth: true,
              requireAdmin: true,
              builder: (context, params) =>
                  const ValidationCommercantsAdminPageWidget(),
            ),
            FFRoute(
              name: AnimationsPromotionsAdminPageWidget.routeName,
              path: AnimationsPromotionsAdminPageWidget.routePath,
              requireAuth: true,
              requireAdmin: true,
              builder: (context, params) =>
                  const AnimationsPromotionsAdminPageWidget(),
            ),
            FFRoute(
              name: AdminPushNotificationsPageWidget.routeName,
              path: AdminPushNotificationsPageWidget.routePath,
              requireAuth: true,
              requireAdmin: true,
              builder: (context, params) =>
                  const AdminPushNotificationsPageWidget(),
            ),
            FFRoute(
              name: AdminAutomaticNotificationsPageWidget.routeName,
              path: AdminAutomaticNotificationsPageWidget.routePath,
              requireAuth: true,
              requireAdmin: true,
              builder: (context, params) =>
                  const AdminAutomaticNotificationsPageWidget(),
            ),
            FFRoute(
              name: AdminAutomaticNotificationConfigPageWidget.routeName,
              path: AdminAutomaticNotificationConfigPageWidget.routePath,
              requireAuth: true,
              requireAdmin: true,
              builder: (context, params) =>
                  AdminAutomaticNotificationConfigPageWidget(
                scenarioId: params.getParam(
                  'scenarioId',
                  ParamType.String,
                ),
                isNew: params.getParam(
                      'isNew',
                      ParamType.bool,
                    ) ??
                    false,
              ),
            ),
            FFRoute(
              name: AdminScheduledNotificationsPageWidget.routeName,
              path: AdminScheduledNotificationsPageWidget.routePath,
              requireAuth: true,
              requireAdmin: true,
              builder: (context, params) =>
                  const AdminScheduledNotificationsPageWidget(),
            ),
            FFRoute(
              name: AdminPushNotificationsHistoryPageWidget.routeName,
              path: AdminPushNotificationsHistoryPageWidget.routePath,
              requireAuth: true,
              requireAdmin: true,
              builder: (context, params) =>
                  const AdminPushNotificationsHistoryPageWidget(),
            ),
            FFRoute(
              name: JeuDetailCommercantPageWidget.routeName,
              path: JeuDetailCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              asyncParams: {
                'gameDoc': getDoc(['games'], GamesRecord.fromSnapshot),
                'enseigneDoc':
                    getDoc(['enseignes'], EnseignesRecord.fromSnapshot),
              },
              builder: (context, params) => JeuDetailCommercantPageWidget(
                gameDoc: params.getParam(
                  'gameDoc',
                  ParamType.Document,
                ),
                enseigneDoc: params.getParam(
                  'enseigneDoc',
                  ParamType.Document,
                ),
              ),
            ),
            FFRoute(
              name: MesEnseignesCommercantPageWidget.routeName,
              path: MesEnseignesCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              builder: (context, params) =>
                  const MesEnseignesCommercantPageWidget(),
            ),
            FFRoute(
              name: FavorisJoueurPageWidget.routeName,
              path: FavorisJoueurPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => const FavorisJoueurPageWidget(),
            ),
            FFRoute(
              name: EnseigneJoueurPageWidget.routeName,
              path: EnseigneJoueurPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => const EnseigneJoueurPageWidget(),
            ),
            FFRoute(
              name: WaitingValidationPageWidget.routeName,
              path: WaitingValidationPageWidget.routePath,
              builder: (context, params) => const WaitingValidationPageWidget(),
            ),
            FFRoute(
              name: EditCommercantPageWidget.routeName,
              path: EditCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              builder: (context, params) => const EditCommercantPageWidget(),
            ),
            FFRoute(
              name: EditJoueurPageWidget.routeName,
              path: EditJoueurPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => const EditJoueurPageWidget(),
            ),
            FFRoute(
              name: AddEnseigneCommercantPageWidget.routeName,
              path: AddEnseigneCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              builder: (context, params) =>
                  const AddEnseigneCommercantPageWidget(),
            ),
            FFRoute(
              name: AddHoraireCommercantPageWidget.routeName,
              path: AddHoraireCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              builder: (context, params) => AddHoraireCommercantPageWidget(
                enseigneRef: params.getParam(
                  'enseigneRef',
                  ParamType.DocumentReference,
                  isList: false,
                  collectionNamePath: ['enseignes'],
                ),
                created: params.getParam(
                  'created',
                  ParamType.bool,
                ),
              ),
            ),
            FFRoute(
              name: UpdateEnseigneCommercantPageWidget.routeName,
              path: UpdateEnseigneCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              asyncParams: {
                'enseigneDocument':
                    getDoc(['enseignes'], EnseignesRecord.fromSnapshot),
              },
              builder: (context, params) => UpdateEnseigneCommercantPageWidget(
                enseigneDocument: params.getParam(
                  'enseigneDocument',
                  ParamType.Document,
                ),
              ),
            ),
            FFRoute(
              name: PhotoEnseigneCommercantPageWidget.routeName,
              path: PhotoEnseigneCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              builder: (context, params) => PhotoEnseigneCommercantPageWidget(
                enseigneRef: params.getParam(
                  'enseigneRef',
                  ParamType.DocumentReference,
                  isList: false,
                  collectionNamePath: ['enseignes'],
                ),
              ),
            ),
            FFRoute(
              name: AddGameCommercantPageWidget.routeName,
              path: AddGameCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              builder: (context, params) => AddGameCommercantPageWidget(
                enseigneRef: params.getParam(
                  'enseigneRef',
                  ParamType.DocumentReference,
                  isList: false,
                  collectionNamePath: ['enseignes'],
                ),
                enseigne: params.getParam(
                  'enseigne',
                  ParamType.String,
                ),
                templateGame: params.getParam(
                  'templateGame',
                  ParamType.Document,
                ),
              ),
            ),
            FFRoute(
              name: JeuShareCommercantPageWidget.routeName,
              path: JeuShareCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              builder: (context, params) => JeuShareCommercantPageWidget(
                gameId: params.getParam(
                  'gameId',
                  ParamType.String,
                ),
                initialGame: params.getParam(
                  'initialGame',
                  ParamType.Document,
                ),
              ),
            ),
            FFRoute(
              name: SelectedEnseignesForAddGameCommercantPageWidget.routeName,
              path: SelectedEnseignesForAddGameCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              builder: (context, params) =>
                  const SelectedEnseignesForAddGameCommercantPageWidget(),
            ),
            FFRoute(
              name: JeuDetailJoueurPageWidget.routeName,
              path: JeuDetailJoueurPageWidget.routePath,
              requireAuth: true,
              asyncParams: {
                'gameDoc': getDoc(['games'], GamesRecord.fromSnapshot),
                'enseigneDoc':
                    getDoc(['enseignes'], EnseignesRecord.fromSnapshot),
              },
              builder: (context, params) => JeuDetailJoueurPageWidget(
                gameDoc: params.getParam(
                  'gameDoc',
                  ParamType.Document,
                ),
                enseigneDoc: params.getParam(
                  'enseigneDoc',
                  ParamType.Document,
                ),
                source: params.getParam(
                  'source',
                  ParamType.String,
                ),
                fromQr: params.getParam(
                      'fromQr',
                      ParamType.bool,
                    ) ??
                    false,
              ),
            ),
            FFRoute(
              name: EnseigneDetailJoueurPageWidget.routeName,
              path: EnseigneDetailJoueurPageWidget.routePath,
              requireAuth: true,
              asyncParams: {
                'enseigneDoc':
                    getDoc(['enseignes'], EnseignesRecord.fromSnapshot),
              },
              builder: (context, params) => EnseigneDetailJoueurPageWidget(
                enseigneDoc: params.getParam(
                  'enseigneDoc',
                  ParamType.Document,
                ),
              ),
            ),
            FFRoute(
              name: RejetInscriptionPageWidget.routeName,
              path: RejetInscriptionPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => const RejetInscriptionPageWidget(),
            ),
            FFRoute(
              name: LotsJoueurPageWidget.routeName,
              path: LotsJoueurPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => const LotsJoueurPageWidget(),
            ),
            FFRoute(
              name: ParrainageJoueurPageWidget.routeName,
              path: ParrainageJoueurPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => const ParrainageJoueurPageWidget(),
            ),
            FFRoute(
              name: ReferralGameDetailJoueurPageWidget.routeName,
              path: ReferralGameDetailJoueurPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => ReferralGameDetailJoueurPageWidget(
                gameId: params.getParam(
                      'gameId',
                      ParamType.String,
                    ) ??
                    '',
              ),
            ),
            FFRoute(
              name: LotDetailJoueurPageWidget.routeName,
              path: LotDetailJoueurPageWidget.routePath,
              requireAuth: true,
              asyncParams: {
                'lot': getDoc(['prizes'], PrizesRecord.fromSnapshot),
              },
              builder: (context, params) => LotDetailJoueurPageWidget(
                lot: params.getParam(
                  'lot',
                  ParamType.Document,
                ),
              ),
            ),
            FFRoute(
              name: ValidationLotCommercantPageWidget.routeName,
              path: ValidationLotCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              asyncParams: {
                'prize': getDoc(['prizes'], PrizesRecord.fromSnapshot),
              },
              builder: (context, params) => ValidationLotCommercantPageWidget(
                prize: params.getParam(
                  'prize',
                  ParamType.Document,
                ),
              ),
            ),
            FFRoute(
              name: PlayJoueurPageWidget.routeName,
              path: PlayJoueurPageWidget.routePath,
              requireAuth: true,
              asyncParams: {
                'game': getDoc(['games'], GamesRecord.fromSnapshot),
              },
              builder: (context, params) => PlayJoueurPageWidget(
                game: params.getParam(
                  'game',
                  ParamType.Document,
                ),
                resultParticipation: params.getParam(
                  'resultParticipation',
                  ParamType.DataStruct,
                  isList: false,
                  structBuilder:
                      ResultParticipationGameStruct.fromSerializableMap,
                ),
                source: params.getParam(
                  'source',
                  ParamType.String,
                ),
              ),
            ),
            FFRoute(
              name: PartageJeuJoueurPageWidget.routeName,
              path: PartageJeuJoueurPageWidget.routePath,
              requireAuth: true,
              asyncParams: {
                'gameDoc': getDoc(['games'], GamesRecord.fromSnapshot),
                'enseigneDoc':
                    getDoc(['enseignes'], EnseignesRecord.fromSnapshot),
              },
              builder: (context, params) => PartageJeuJoueurPageWidget(
                gameDoc: params.getParam(
                  'gameDoc',
                  ParamType.Document,
                ),
                enseigneDoc: params.getParam(
                  'enseigneDoc',
                  ParamType.Document,
                ),
                source: params.getParam(
                  'source',
                  ParamType.String,
                ),
              ),
            ),
            FFRoute(
              name: ShareJeuPageWidget.routeName,
              path: ShareJeuPageWidget.routePath,
              requireAuth: true,
              asyncParams: {
                'gameDoc': getDoc(['games'], GamesRecord.fromSnapshot),
                'enseigneDoc':
                    getDoc(['enseignes'], EnseignesRecord.fromSnapshot),
              },
              builder: (context, params) => ShareJeuPageWidget(
                gameDoc: params.getParam(
                  'gameDoc',
                  ParamType.Document,
                ),
                enseigneDoc: params.getParam(
                  'enseigneDoc',
                  ParamType.Document,
                ),
                source: params.getParam(
                  'source',
                  ParamType.String,
                ),
              ),
            ),
            FFRoute(
              name: AboCommercantPageWidget.routeName,
              path: AboCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              builder: (context, params) => const AboCommercantPageWidget(),
            ),
            FFRoute(
              name:
                  SelectedAutoEnseignesForAddGameCommercantPageWidget.routeName,
              path:
                  SelectedAutoEnseignesForAddGameCommercantPageWidget.routePath,
              requireAuth: true,
              requireMerchant: true,
              builder: (context, params) =>
                  const SelectedAutoEnseignesForAddGameCommercantPageWidget(),
            ),
            FFRoute(
              name: ContactPageWidget.routeName,
              path: ContactPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => const ContactPageWidget(),
            ),
            FFRoute(
              name: DeleteCommAdminPageWidget.routeName,
              path: DeleteCommAdminPageWidget.routePath,
              requireAuth: true,
              requireAdmin: true,
              builder: (context, params) => const DeleteCommAdminPageWidget(),
            ),
            FFRoute(
              name: LegalPageWidget.routeName,
              path: LegalPageWidget.routePath,
              builder: (context, params) => const LegalPageWidget(),
            )
          ].map((r) => r.toRoute(appStateNotifier)).toList(),
        ),
      ].map((r) => r.toRoute(appStateNotifier)).toList(),
    );

extension NavParamExtensions on Map<String, String?> {
  Map<String, String> get withoutNulls => Map.fromEntries(
        entries
            .where((e) => e.value != null)
            .map((e) => MapEntry(e.key, e.value!)),
      );
}

extension NavigationExtensions on BuildContext {
  void goNamedAuth(
    String name,
    bool mounted, {
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, String> queryParameters = const <String, String>{},
    Object? extra,
    bool ignoreRedirect = false,
  }) =>
      !mounted || GoRouter.of(this).shouldRedirect(ignoreRedirect)
          ? null
          : goNamed(
              name,
              pathParameters: pathParameters,
              queryParameters: queryParameters,
              extra: extra,
            );

  void pushNamedAuth(
    String name,
    bool mounted, {
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, String> queryParameters = const <String, String>{},
    Object? extra,
    bool ignoreRedirect = false,
  }) =>
      !mounted || GoRouter.of(this).shouldRedirect(ignoreRedirect)
          ? null
          : pushNamed(
              name,
              pathParameters: pathParameters,
              queryParameters: queryParameters,
              extra: extra,
            );

  void safePop() {
    // If there is only one route on the stack, navigate to the initial
    // page instead of popping.
    if (canPop()) {
      pop();
    } else {
      final isLoggedIn =
          AppStateNotifier.instance.loggedIn && currentUserUid.isNotEmpty;
      if (!isLoggedIn) {
        go(LoginPageWidget.routePath);
        return;
      }
      switch (resolveSafePopFallbackHome(currentUserDocument?.userRole)) {
        case SafePopFallbackHome.commercant:
          go(HomeCommercantPageWidget.routePath);
        case SafePopFallbackHome.admin:
          go(HomeAdminPageWidget.routePath);
        case SafePopFallbackHome.joueur:
          go(HomeJoueurPageWidget.routePath);
      }
    }
  }
}

extension GoRouterExtensions on GoRouter {
  AppStateNotifier get appState => AppStateNotifier.instance;
  void prepareAuthEvent([bool ignoreRedirect = false]) =>
      appState.hasRedirect() && !ignoreRedirect
          ? null
          : appState.updateNotifyOnAuthChange(false);
  bool shouldRedirect(bool ignoreRedirect) =>
      !ignoreRedirect && appState.hasRedirect();
  void clearRedirectLocation() => appState.clearRedirectLocation();
  void setRedirectLocationIfUnset(String location) =>
      appState.setRedirectLocationIfUnset(location);
}

extension _GoRouterStateExtensions on GoRouterState {
  Map<String, dynamic> get extraMap =>
      extra != null ? extra as Map<String, dynamic> : {};
  Map<String, dynamic> get allParams => <String, dynamic>{}
    ..addAll(pathParameters)
    ..addAll(uri.queryParameters)
    ..addAll(extraMap);
  TransitionInfo get transitionInfo => extraMap.containsKey(kTransitionInfoKey)
      ? extraMap[kTransitionInfoKey] as TransitionInfo
      : TransitionInfo.appDefault();
}

class FFParameters {
  FFParameters(this.state, [this.asyncParams = const {}]);

  final GoRouterState state;
  final Map<String, Future<dynamic> Function(String)> asyncParams;

  Map<String, dynamic> futureParamValues = {};

  // Parameters are empty if the params map is empty or if the only parameter
  // present is the special extra parameter reserved for the transition info.
  bool get isEmpty =>
      state.allParams.isEmpty ||
      (state.allParams.length == 1 &&
          state.extraMap.containsKey(kTransitionInfoKey));
  bool isAsyncParam(MapEntry<String, dynamic> param) =>
      asyncParams.containsKey(param.key) && param.value is String;
  bool get hasFutures => state.allParams.entries.any(isAsyncParam);
  Future<bool> completeFutures() => Future.wait(
        state.allParams.entries.where(isAsyncParam).map(
          (param) async {
            final doc = await asyncParams[param.key]!(param.value)
                .onError((_, __) => null);
            if (doc != null) {
              futureParamValues[param.key] = doc;
              return true;
            }
            return false;
          },
        ),
      ).onError((_, __) => [false]).then((v) => v.every((e) => e));

  dynamic getParam<T>(
    String paramName,
    ParamType type, {
    bool isList = false,
    List<String>? collectionNamePath,
    StructBuilder<T>? structBuilder,
  }) {
    if (futureParamValues.containsKey(paramName)) {
      return futureParamValues[paramName];
    }
    if (!state.allParams.containsKey(paramName)) {
      return null;
    }
    final param = state.allParams[paramName];
    // Got parameter from `extras`, so just directly return it.
    if (param is! String) {
      return param;
    }
    // Return serialized value.
    return deserializeParam<T>(
      param,
      type,
      isList,
      collectionNamePath: collectionNamePath,
      structBuilder: structBuilder,
    );
  }
}

class FFRoute {
  const FFRoute({
    required this.name,
    required this.path,
    required this.builder,
    this.requireAuth = false,
    this.requireAdmin = false,
    this.requireMerchant = false,
    this.asyncParams = const {},
    this.routes = const [],
  });

  final String name;
  final String path;
  final bool requireAuth;
  final bool requireAdmin;
  final bool requireMerchant;
  final Map<String, Future<dynamic> Function(String)> asyncParams;
  final Widget Function(BuildContext, FFParameters) builder;
  final List<GoRoute> routes;

  GoRoute toRoute(AppStateNotifier appStateNotifier) => GoRoute(
        name: name,
        path: path,
        redirect: (context, state) {
          final deepLinkGameId = _extractDeepLinkGameId(state.uri);
          final isDeepLinkRoute = deepLinkGameId != null;
          if (isDeepLinkRoute) {
            debugPrint(
                '[DEEPLINK_RECEIVED] gameId=$deepLinkGameId uri=${state.uri.toString()}');
            debugPrint(
              '[QR_DEEPLINK_RECEIVED] gameId=$deepLinkGameId uri=${state.uri.toString()}',
            );
            debugPrint(
              '[QR_AUTH_STATE_ON_DEEPLINK] isLoggedIn=${appStateNotifier.loggedIn} authResolved=${appStateNotifier.hasResolvedAuthState}',
            );
            final shouldStorePendingDeepLink = !appStateNotifier.loggedIn ||
                currentUserUid.isEmpty ||
                isGuestOrAnonymous;
            if (shouldStorePendingDeepLink &&
                FFAppState().pendingDeepLinkGameId != deepLinkGameId) {
              FFAppState().pendingDeepLinkGameId = deepLinkGameId;
              debugPrint('[DEEPLINK_PENDING_STORED] gameId=$deepLinkGameId');
            }
          }

          if (!appStateNotifier.hasResolvedAuthState) {
            return null;
          }

          if (appStateNotifier.shouldRedirect) {
            final redirectLocation = appStateNotifier.getRedirectLocation();
            appStateNotifier.clearRedirectLocation();
            return redirectLocation;
          }

          final protectedRedirectPath = resolveProtectedRouteGuardRedirectPath(
            hasResolvedAuthState: appStateNotifier.hasResolvedAuthState,
            loggedIn: appStateNotifier.loggedIn,
            requireAuth: requireAuth,
            requireAdmin: requireAdmin,
            requireMerchant: requireMerchant,
            hasUserDocument: currentUserDocument != null,
            role: currentUserDocument?.userRole,
            hasMerchantConflict:
                hasCachedMerchantRoutingConflict(currentUserDocument),
            isDeepLinkRoute: isDeepLinkRoute,
            currentPath: state.uri.path,
          );
          if (protectedRedirectPath != null) {
            if (protectedRedirectPath == loginRoutePath && requireAuth) {
              appStateNotifier.setRedirectLocationIfUnset(state.uri.toString());
            }
            return protectedRedirectPath;
          }
          return null;
        },
        pageBuilder: (context, state) {
          fixStatusBarOniOS16AndBelow(context);
          final ffParams = FFParameters(state, asyncParams);
          final page = ffParams.hasFutures
              ? FutureBuilder(
                  future: ffParams.completeFutures(),
                  builder: (context, _) => builder(context, ffParams),
                )
              : builder(context, ffParams);
          final child = appStateNotifier.loading
              ? Container(
                  color: FlutterFlowTheme.of(context).secondaryBackground,
                  child: Center(
                    child: Image.asset(
                      'assets/images/logo_D_secondaire.png',
                      width: MediaQuery.sizeOf(context).width * 0.8,
                      height: double.infinity,
                      fit: BoxFit.scaleDown,
                    ),
                  ),
                )
              : PushNotificationsHandler(child: page);

          final transitionInfo = state.transitionInfo;
          return transitionInfo.hasTransition
              ? CustomTransitionPage(
                  key: state.pageKey,
                  name: state.name,
                  child: child,
                  transitionDuration: transitionInfo.duration,
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) =>
                          PageTransition(
                    type: transitionInfo.transitionType,
                    duration: transitionInfo.duration,
                    reverseDuration: transitionInfo.duration,
                    alignment: transitionInfo.alignment,
                    child: child,
                  ).buildTransitions(
                    context,
                    animation,
                    secondaryAnimation,
                    child,
                  ),
                )
              : MaterialPage(
                  key: state.pageKey,
                  name: state.name,
                  child: child,
                );
        },
        routes: routes,
      );
}

class TransitionInfo {
  const TransitionInfo({
    required this.hasTransition,
    this.transitionType = PageTransitionType.fade,
    this.duration = const Duration(milliseconds: 300),
    this.alignment,
  });

  final bool hasTransition;
  final PageTransitionType transitionType;
  final Duration duration;
  final Alignment? alignment;

  static TransitionInfo appDefault() =>
      const TransitionInfo(hasTransition: false);
}

class RootPageContext {
  const RootPageContext(this.isRootPage, [this.errorRoute]);
  final bool isRootPage;
  final String? errorRoute;

  static bool isInactiveRootPage(BuildContext context) {
    final rootPageContext = context.read<RootPageContext?>();
    final isRootPage = rootPageContext?.isRootPage ?? false;
    final location = GoRouterState.of(context).uri.toString();
    return isRootPage &&
        location != '/' &&
        location != rootPageContext?.errorRoute;
  }

  static Widget wrap(Widget child, {String? errorRoute}) => Provider.value(
        value: RootPageContext(true, errorRoute),
        child: child,
      );
}

extension GoRouterLocationExtension on GoRouter {
  String getCurrentLocation() {
    final currentConfiguration = routerDelegate.currentConfiguration;
    if (currentConfiguration.isEmpty) {
      return currentConfiguration.uri.toString();
    }

    final RouteMatch lastMatch = currentConfiguration.last;
    final RouteMatchList matchList = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches
        : currentConfiguration;
    return matchList.uri.toString();
  }
}
