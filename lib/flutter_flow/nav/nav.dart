import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:page_transition/page_transition.dart';
import 'package:provider/provider.dart';
import 'package:proxi_play/pages/admin/admin_push_notifications_page/admin_push_notifications_page_widget.dart';
import 'package:proxi_play/pages/admin/admin_push_notifications_history_page/admin_push_notifications_history_page_widget.dart';
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/backend/schema/enums/enums.dart';

import '/auth/base_auth_user_provider.dart';

import '/backend/push_notifications/push_notifications_handler.dart'
    show PushNotificationsHandler;
import '/auth/firebase_auth/auth_util.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'serialization_util.dart';

import '/index.dart';

export 'package:go_router/go_router.dart';
export 'serialization_util.dart';

const kTransitionInfoKey = '__transition_info__';

GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class AppStateNotifier extends ChangeNotifier {
  AppStateNotifier._();

  static AppStateNotifier? _instance;
  static AppStateNotifier get instance => _instance ??= AppStateNotifier._();

  BaseAuthUser? initialUser;
  BaseAuthUser? user;
  bool showSplashImage = true;
  String? _redirectLocation;

  /// Determines whether the app will refresh and build again when a sign
  /// in or sign out happens. This is useful when the app is launched or
  /// on an unexpected logout. However, this must be turned off when we
  /// intend to sign in/out and then navigate or perform any actions after.
  /// Otherwise, this will trigger a refresh and interrupt the action(s).
  bool notifyOnAuthChange = true;

  bool get loading => user == null || showSplashImage;
  bool get loggedIn => user?.loggedIn ?? false;
  bool get initiallyLoggedIn => initialUser?.loggedIn ?? false;
  bool get shouldRedirect => loggedIn && _redirectLocation != null;

  String getRedirectLocation() => _redirectLocation!;
  bool hasRedirect() => _redirectLocation != null;
  void setRedirectLocationIfUnset(String loc) => _redirectLocation ??= loc;
  void clearRedirectLocation() => _redirectLocation = null;

  /// Mark as not needing to notify on a sign in / out when we intend
  /// to perform subsequent actions (such as navigation) afterwards.
  void updateNotifyOnAuthChange(bool notify) => notifyOnAuthChange = notify;

  void update(BaseAuthUser newUser) {
    final shouldUpdate =
        user?.uid == null || newUser.uid == null || user?.uid != newUser.uid;
    initialUser ??= newUser;
    user = newUser;
    // Refresh the app on auth change unless explicitly marked otherwise.
    // No need to update unless the user has changed.
    if (notifyOnAuthChange && shouldUpdate) {
      notifyListeners();
    }
    // Once again mark the notifier as needing to update on auth change
    // (in order to catch sign in / out events).
    updateNotifyOnAuthChange(true);
  }

  void stopShowingSplashImage() {
    showSplashImage = false;
    notifyListeners();
  }
}

GoRouter createRouter(AppStateNotifier appStateNotifier) => GoRouter(
      initialLocation: '/',
      debugLogDiagnostics: true,
      refreshListenable: appStateNotifier,
      navigatorKey: appNavigatorKey,
      errorBuilder: (context, state) =>
          appStateNotifier.loggedIn ? LoginPageWidget() : LoginPageWidget(),
      routes: [
        FFRoute(
          name: '_initialize',
          path: '/',
          builder: (context, _) =>
              appStateNotifier.loggedIn ? LoginPageWidget() : LoginPageWidget(),
          routes: [
            FFRoute(
              name: HomeJoueurPageWidget.routeName,
              path: HomeJoueurPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => HomeJoueurPageWidget(),
            ),
            FFRoute(
              name: LoginPageWidget.routeName,
              path: LoginPageWidget.routePath,
              builder: (context, params) => LoginPageWidget(),
            ),
            FFRoute(
              name: InscriptionPageWidget.routeName,
              path: InscriptionPageWidget.routePath,
              builder: (context, params) => InscriptionPageWidget(),
            ),
            FFRoute(
              name: InscriptionInformationsPageWidget.routeName,
              path: InscriptionInformationsPageWidget.routePath,
              // This page writes to the current user's Firestore doc; it should
              // only be reachable when authenticated.
              requireAuth: true,
              builder: (context, params) => InscriptionInformationsPageWidget(),
            ),
            FFRoute(
              name: ResetPasswordWidget.routeName,
              path: ResetPasswordWidget.routePath,
              builder: (context, params) => ResetPasswordWidget(),
            ),
            FFRoute(
              name: HomeCommercantPageWidget.routeName,
              path: HomeCommercantPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => HomeCommercantPageWidget(),
            ),
            FFRoute(
              name: JeuxCommercantPageWidget.routeName,
              path: JeuxCommercantPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => JeuxCommercantPageWidget(),
            ),
            FFRoute(
              name: StatCommercantPageWidget.routeName,
              path: StatCommercantPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => StatCommercantPageWidget(),
            ),
            FFRoute(
              name: ProfilCommercantPageWidget.routeName,
              path: ProfilCommercantPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => ProfilCommercantPageWidget(),
            ),
            FFRoute(
              name: ProfilJoueurPageWidget.routeName,
              path: ProfilJoueurPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => ProfilJoueurPageWidget(),
            ),
            FFRoute(
              name: HomeAdminPageWidget.routeName,
              path: HomeAdminPageWidget.routePath,
              requireAuth: true,
              requireAdmin: true,
              builder: (context, params) => HomeAdminPageWidget(),
            ),
            FFRoute(
              name: AdminPushNotificationsPageWidget.routeName,
              path: AdminPushNotificationsPageWidget.routePath,
              requireAuth: true,
              requireAdmin: true,
              builder: (context, params) => AdminPushNotificationsPageWidget(),
            ),
            FFRoute(
              name: AdminPushNotificationsHistoryPageWidget.routeName,
              path: AdminPushNotificationsHistoryPageWidget.routePath,
              requireAuth: true,
              requireAdmin: true,
              builder: (context, params) =>
                  AdminPushNotificationsHistoryPageWidget(),
            ),
            FFRoute(
              name: JeuDetailCommercantPageWidget.routeName,
              path: JeuDetailCommercantPageWidget.routePath,
              requireAuth: true,
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
              builder: (context, params) => MesEnseignesCommercantPageWidget(),
            ),
            FFRoute(
              name: FavorisJoueurPageWidget.routeName,
              path: FavorisJoueurPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => FavorisJoueurPageWidget(),
            ),
            FFRoute(
              name: EnseigneJoueurPageWidget.routeName,
              path: EnseigneJoueurPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => EnseigneJoueurPageWidget(),
            ),
            FFRoute(
              name: InscriptionIdentityCardPageWidget.routeName,
              path: InscriptionIdentityCardPageWidget.routePath,
              builder: (context, params) => InscriptionIdentityCardPageWidget(),
            ),
            FFRoute(
              name: InscriptionIdentityPhotoPageWidget.routeName,
              path: InscriptionIdentityPhotoPageWidget.routePath,
              builder: (context, params) =>
                  InscriptionIdentityPhotoPageWidget(),
            ),
            FFRoute(
              name: WaitingValidationPageWidget.routeName,
              path: WaitingValidationPageWidget.routePath,
              builder: (context, params) => WaitingValidationPageWidget(),
            ),
            FFRoute(
              name: EditCommercantPageWidget.routeName,
              path: EditCommercantPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => EditCommercantPageWidget(),
            ),
            FFRoute(
              name: EditJoueurPageWidget.routeName,
              path: EditJoueurPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => EditJoueurPageWidget(),
            ),
            FFRoute(
              name: AddEnseigneCommercantPageWidget.routeName,
              path: AddEnseigneCommercantPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => AddEnseigneCommercantPageWidget(),
            ),
            FFRoute(
              name: AddHoraireCommercantPageWidget.routeName,
              path: AddHoraireCommercantPageWidget.routePath,
              requireAuth: true,
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
              ),
            ),
            FFRoute(
              name: SelectedEnseignesForAddGameCommercantPageWidget.routeName,
              path: SelectedEnseignesForAddGameCommercantPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) =>
                  SelectedEnseignesForAddGameCommercantPageWidget(),
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
              builder: (context, params) => RejetInscriptionPageWidget(),
            ),
            FFRoute(
              name: LotsJoueurPageWidget.routeName,
              path: LotsJoueurPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => LotsJoueurPageWidget(),
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
              ),
            ),
            FFRoute(
              name: AboCommercantPageWidget.routeName,
              path: AboCommercantPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => AboCommercantPageWidget(),
            ),
            FFRoute(
              name:
                  SelectedAutoEnseignesForAddGameCommercantPageWidget.routeName,
              path:
                  SelectedAutoEnseignesForAddGameCommercantPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) =>
                  SelectedAutoEnseignesForAddGameCommercantPageWidget(),
            ),
            FFRoute(
              name: ContactPageWidget.routeName,
              path: ContactPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => ContactPageWidget(),
            ),
            FFRoute(
              name: DeleteCommAdminPageWidget.routeName,
              path: DeleteCommAdminPageWidget.routePath,
              requireAuth: true,
              builder: (context, params) => DeleteCommAdminPageWidget(),
            ),
            FFRoute(
              name: LegalPageWidget.routeName,
              path: LegalPageWidget.routePath,
              builder: (context, params) => LegalPageWidget(),
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
      go('/');
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
      appState.updateNotifyOnAuthChange(false);
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
    this.asyncParams = const {},
    this.routes = const [],
  });

  final String name;
  final String path;
  final bool requireAuth;
  final bool requireAdmin;
  final Map<String, Future<dynamic> Function(String)> asyncParams;
  final Widget Function(BuildContext, FFParameters) builder;
  final List<GoRoute> routes;

  GoRoute toRoute(AppStateNotifier appStateNotifier) => GoRoute(
        name: name,
        path: path,
        redirect: (context, state) {
          // Global auth guard: after logout, always send the user to login
          // (except for the public auth/legal pages).
          if (!appStateNotifier.loggedIn) {
            final p = state.uri.path;
            const publicPaths = <String>{
              '/',
              '/loginPage',
              '/inscriptionPage',
              '/resetPassword',
              '/legalPage',
            };
            if (!publicPaths.contains(p)) {
              return '/loginPage';
            }
          }

          if (appStateNotifier.shouldRedirect) {
            final redirectLocation = appStateNotifier.getRedirectLocation();
            appStateNotifier.clearRedirectLocation();
            return redirectLocation;
          }

          if (requireAuth && !appStateNotifier.loggedIn) {
            appStateNotifier.setRedirectLocationIfUnset(state.uri.toString());
            return '/loginPage';
          }
          if (requireAdmin) {
            // If the user doc hasn't loaded yet, don't redirect; wait for data.
            if (appStateNotifier.loggedIn && currentUserDocument == null) {
              return null;
            }
            if (currentUserDocument?.userRole != Roles.admin) {
              // If user isn't an admin, keep them out of admin-only pages.
              return '/loginPage';
            }
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
              : MaterialPage(key: state.pageKey, child: child);
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

  static TransitionInfo appDefault() => TransitionInfo(hasTransition: false);
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
    final RouteMatch lastMatch = routerDelegate.currentConfiguration.last;
    final RouteMatchList matchList = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches
        : routerDelegate.currentConfiguration;
    return matchList.uri.toString();
  }
}
