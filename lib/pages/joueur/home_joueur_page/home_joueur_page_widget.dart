import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/components/app_bar_joueur_widget.dart';
import '/components/monthly_challenge_banner_widget.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/components/game_card_widget.dart';
import '/components/list_empty_component_widget.dart';
import '/components/share_promo_banner_widget.dart';
import '/flutter_flow/app_styles.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/models/share_promo_models.dart';
import '/models/monthly_challenge_models.dart';
import '/services/share_promo_service.dart';
import '/services/monthly_challenge_service.dart';
import '/services/global_ticker_service.dart';
import '/widgets/recent_winners_ticker.dart';
import '/widgets/proxiplay_loading_logo.dart';
import '/widgets/proxiplay_network_image.dart';
import '/widgets/referral_game_card.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/index.dart';
import '/utils/perf_trace.dart';
import '/utils/proxiplay_layout.dart';
import '/utils/share_links.dart';
import '/utils/winner_identity.dart';
import 'home_games_logic.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:text_search/text_search.dart';
import 'home_joueur_page_model.dart';
export 'home_joueur_page_model.dart';

/// mettre un jeu en favori
class HomeJoueurPageWidget extends StatefulWidget {
  const HomeJoueurPageWidget({super.key});

  static String routeName = 'HomeJoueurPage';
  static String routePath = 'homeJoueurPage';

  @override
  State<HomeJoueurPageWidget> createState() => _HomeJoueurPageWidgetState();
}

class _HomeJoueurPageWidgetState extends State<HomeJoueurPageWidget>
    with WidgetsBindingObserver {
  static final Random _random = Random();
  static final Map<String, String> _cityFormatCache = {};
  static const double _homeSectionTitleLeftInset = 4.0;
  static const double _homeHorizontalCardGap = 10.0;
  static const double _homePageHorizontalPadding = 20.0;

  late HomeJoueurPageModel _model;
  final _sharePromoService = SharePromoService();

  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool _homeDataReady = false;
  bool _isRefreshingOnResume = false;
  DateTime? _lastResumeRefresh;
  late Future<SharePromoStateViewModel?> _sharePromoFuture;
  SharePromoStateViewModel? _latestSharePromoState;
  late Future<MonthlyChallengeStateViewModel?> _monthlyChallengeFuture;
  MonthlyChallengeStateViewModel? _latestMonthlyChallengeState;
  final _monthlyChallengeService = MonthlyChallengeService();
  final Map<String, Future<EnseignesRecord>> _enseigneFutureCache = {};
  final Map<String, Future<Map<String, EnseignesRecord>>>
      _featuredEnseignesSectionCache = {};
  final Map<String, Future<Map<String, EnseignesRecord>>>
      _endingSoonEnseignesSectionCache = {};
  final Map<String, Future<Map<String, EnseignesRecord>>>
      _newGamesEnseignesSectionCache = {};

  Future<void> _ensureTickerLoaded() async {
    if (FFAppState().globalTickerMessages.isNotEmpty) {
      return;
    }

    final tickerSnapshot = await const GlobalTickerService().fetchOnce();
    if (!mounted || tickerSnapshot == null || tickerSnapshot.messages.isEmpty) {
      return;
    }

    FFAppState().update(() {
      FFAppState().setGlobalTickerData(
        totalPlayers: tickerSnapshot.totalPlayers,
        totalGamesPlayed: tickerSnapshot.totalGamesPlayed,
        totalMerchants: tickerSnapshot.totalMerchants,
        messages: tickerSnapshot.messages,
        updatedAt: tickerSnapshot.updatedAt,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _model = createModel(context, () => HomeJoueurPageModel());
    PerfTrace.log('HOME_INIT');
    PerfTrace.log('HOME_DATA_LOADING_START');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PerfTrace.log('HOME_FIRST_FRAME');
      if (mounted) {
        _markHomeDataReady();
      }
    });

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'HomeJoueurPage'});

    _model.textController ??= TextEditingController();
    _model.textFieldFocusNode ??= FocusNode();
    _sharePromoFuture = _loadSharePromoState();
    _monthlyChallengeFuture = _loadMonthlyChallengeState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureTickerLoaded();
    });
  }

  void _markHomeDataReady({int? itemCount}) {
    if (_homeDataReady) {
      return;
    }
    _homeDataReady = true;
    PerfTrace.log('HOME_DATA_LOADING_END', itemCount: itemCount);
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  bool _isGameVisibleForPlayer(GamesRecord game) {
    return isPlayerHomeGameVisible(
      now: getCurrentTimestamp,
      animationId: game.animationId,
      startDate: game.startDate,
      endDate: game.endDate,
    );
  }

  bool get _showsFullGameCatalog => true;

  void _logHomeGamesSection(
    String sectionName,
    List<GamesRecord> rawGames,
    List<GamesRecord> visibleGames,
  ) {
    debugPrint(
      '[DIAG] section=$sectionName rawIds=${rawGames.map((g) => g.reference.id).toList()} visibleIds=${visibleGames.map((g) => g.reference.id).toList()}',
    );
  }

  void _logHomeSectionSummary({
    required String sectionName,
    required int rawCount,
    required int filteredCount,
    required int sortedCount,
    required int widgetInputCount,
    required int renderItemCount,
  }) {
    debugPrint(
      '[DIAG] summary section=$sectionName raw=$rawCount filtered=$filteredCount sorted=$sortedCount widgetInput=$widgetInputCount renderItem=$renderItemCount',
    );
  }

  void _logHomeRenderItem({
    required String sectionName,
    required int index,
    required GamesRecord game,
  }) {
    debugPrint(
      '[DIAG] render section=$sectionName index=$index id=${game.reference.id} name=${game.name}',
    );
  }

  void _logHomeUserContext({
    required String branchName,
    required bool isMinor,
  }) {
    debugPrint('[DIAG] userContext branch=$branchName isMinor=$isMinor');
  }

  void _logHomeQueryBranch({
    required String sectionName,
    required String branchName,
    required List<String> clauses,
  }) {
    debugPrint(
      '[DIAG] query section=$sectionName branch=$branchName clauses=$clauses',
    );
  }

  Future<void> _runHomeBranchDiagnostics({
    required String branchName,
  }) async {}

  bool _hasVisibleMainPrizeForPlayer(GamesRecord game) {
    return game.hasMainPrize == true && game.prizeValue > 0;
  }

  Future<EnseignesRecord> _getCachedEnseigneFuture(
      DocumentReference enseigneRef) {
    return _enseigneFutureCache.putIfAbsent(
      enseigneRef.path,
      () => EnseignesRecord.getDocumentOnce(enseigneRef),
    );
  }

  Future<EnseignesRecord?> _loadEnseigneForGame(GamesRecord game) async {
    final enseigneRef = game.enseigneId;
    if (enseigneRef == null) {
      return null;
    }
    try {
      return await _getCachedEnseigneFuture(enseigneRef);
    } catch (_) {
      return null;
    }
  }

  String _getGameCardStoreName(GamesRecord game, EnseignesRecord? enseigne) {
    final enseigneName = (enseigne?.name ?? '').trim();
    if (enseigneName.isNotEmpty) {
      return enseigneName;
    }
    return game.enseigneName.trim();
  }

  // Display only city on home game cards.
  String _formatCityOnly(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    return _cityFormatCache.putIfAbsent(raw, () {
      final withoutZip = raw.replaceFirst(RegExp(r'^\d{5}\s*'), '').trim();
      final cityOnly = withoutZip.isEmpty ? raw : withoutZip;
      return cityOnly
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .map(
            (word) => word
                .split('-')
                .where((part) => part.isNotEmpty)
                .map(
                  (part) =>
                      part[0].toUpperCase() + part.substring(1).toLowerCase(),
                )
                .join('-'),
          )
          .join(' ');
    });
  }

  String _getGameCardLocation(EnseignesRecord? enseigne) {
    final city = (enseigne?.city ?? '').trim();
    final address = (enseigne?.address ?? '').trim();
    if (city.isNotEmpty) {
      return _formatCityOnly(city);
    }
    return _formatCityOnly(address);
  }

  Future<Map<String, EnseignesRecord>> _getFeaturedEnseignesForGames(
    List<GamesRecord> games,
  ) {
    final enseignePaths = games
        .map((game) => game.enseigneId?.path)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    final cacheKey = enseignePaths.join('|');

    return _featuredEnseignesSectionCache.putIfAbsent(cacheKey, () async {
      final futures = games
          .map((game) => game.enseigneId)
          .whereType<DocumentReference>()
          .toSet()
          .map((enseigneRef) async {
        final enseigne = await _getCachedEnseigneFuture(enseigneRef);
        return MapEntry(enseigneRef.path, enseigne);
      });

      final entries = await Future.wait(futures);
      return {
        for (final entry in entries) entry.key: entry.value,
      };
    });
  }

  Future<Map<String, EnseignesRecord>> _getEndingSoonEnseignesForGames(
    List<GamesRecord> games,
  ) {
    final enseignePaths = games
        .map((game) => game.enseigneId?.path)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    final cacheKey = enseignePaths.join('|');

    return _endingSoonEnseignesSectionCache.putIfAbsent(cacheKey, () async {
      final futures = games
          .map((game) => game.enseigneId)
          .whereType<DocumentReference>()
          .toSet()
          .map((enseigneRef) async {
        final enseigne = await _getCachedEnseigneFuture(enseigneRef);
        return MapEntry(enseigneRef.path, enseigne);
      });

      final entries = await Future.wait(futures);
      return {
        for (final entry in entries) entry.key: entry.value,
      };
    });
  }

  Future<Map<String, EnseignesRecord>> _getNewGamesEnseignesForGames(
    List<GamesRecord> games,
  ) {
    final enseignePaths = games
        .map((game) => game.enseigneId?.path)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    final cacheKey = enseignePaths.join('|');

    return _newGamesEnseignesSectionCache.putIfAbsent(cacheKey, () async {
      final futures = games
          .map((game) => game.enseigneId)
          .whereType<DocumentReference>()
          .toSet()
          .map((enseigneRef) async {
        final enseigne = await _getCachedEnseigneFuture(enseigneRef);
        return MapEntry(enseigneRef.path, enseigne);
      });

      final entries = await Future.wait(futures);
      return {
        for (final entry in entries) entry.key: entry.value,
      };
    });
  }

  Future<void> _openGameDetails(GamesRecord game) async {
    final enseigne = await _loadEnseigneForGame(game);
    if (!mounted) {
      return;
    }
    final enseigneParam = enseigne != null
        ? serializeParam(
            enseigne,
            ParamType.Document,
          )
        : serializeParam(
            game.enseigneId,
            ParamType.DocumentReference,
          );
    await context.pushNamed(
      JeuDetailJoueurPageWidget.routeName,
      queryParameters: {
        'gameDoc': serializeParam(
          game,
          ParamType.Document,
        ),
        'enseigneDoc': enseigneParam,
      }.withoutNulls,
      extra: <String, dynamic>{
        'gameDoc': game,
        if (enseigne != null) 'enseigneDoc': enseigne,
        'source': 'home',
        kTransitionInfoKey: const TransitionInfo(
          hasTransition: true,
          transitionType: PageTransitionType.rightToLeft,
        ),
      },
    );
    await refreshCurrentUserDocument();
    if (mounted) {
      safeSetState(() {});
    }
  }

  double _computeHomeCardWidth(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final availableWidth = screenWidth - (_homePageHorizontalPadding * 2);
    final twoColumnWidth =
        (availableWidth - _homeHorizontalCardGap) / 2;
    return twoColumnWidth.clamp(140.0, AppStyles.gameCardWidth);
  }

  Widget _buildFeaturedGamesCarousel(
    BuildContext context,
    List<GamesRecord> featuredGames,
    String sectionName, {
    bool showReferralGameCard = false,
  }) {
    if (featuredGames.isEmpty && !showReferralGameCard) {
      return const SizedBox(
        height: AppStyles.gameCardHeight,
        child: ListEmptyComponentWidget(
          title: 'Liste vide',
          description: 'Il n\'y a pas de jeux pour le moment',
        ),
      );
    }

    return FutureBuilder<Map<String, EnseignesRecord>>(
      future: _getFeaturedEnseignesForGames(featuredGames),
      builder: (context, enseignesSnapshot) {
        final enseignesByPath =
            enseignesSnapshot.data ?? const <String, EnseignesRecord>{};
        _logHomeSectionSummary(
          sectionName: sectionName,
          rawCount: featuredGames.length,
          filteredCount: featuredGames.length,
          sortedCount: featuredGames.length,
          widgetInputCount: featuredGames.length,
          renderItemCount: featuredGames.length,
        );

        Widget buildCarousel({required bool hasActiveReferralGame}) {
          final includeReferralCard =
              showReferralGameCard && hasActiveReferralGame;
          final itemCount =
              featuredGames.length + (includeReferralCard ? 1 : 0);

          return ListView.separated(
            padding: EdgeInsets.zero,
            primary: false,
            scrollDirection: Axis.horizontal,
            itemCount: itemCount,
            separatorBuilder: (_, __) =>
                const SizedBox(width: _homeHorizontalCardGap),
            itemBuilder: (context, rawIndex) {
              if (includeReferralCard && rawIndex == 0) {
                return ReferralGameCard(
                  width: _computeHomeCardWidth(context),
                );
              }
              final index = includeReferralCard ? rawIndex - 1 : rawIndex;
              final game = featuredGames[index];
              _logHomeRenderItem(
                sectionName: sectionName,
                index: index,
                game: game,
              );
              final enseigne = game.enseigneId != null
                  ? enseignesByPath[game.enseigneId!.path]
                  : null;

              return _buildHomeGameCard(
                game: game,
                enseigne: enseigne,
                prizeText: game.prizeValue == 0
                    ? 'Gains instantan\u00E9s'
                    : _formatEuroAmount(game.prizeValue),
                endDateText: game.endDate != null
                    ? "Jusqu'au : ${dateTimeFormat('d/M/y', game.endDate, locale: FFLocalizations.of(context).languageCode)}"
                    : "Jusqu'au : -",
                onTap: () async {
                  await _openGameDetails(game);
                },
              );
            },
          );
        }

        if (!showReferralGameCard) {
          return buildCarousel(hasActiveReferralGame: false);
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('referral_games')
              .where('status', isEqualTo: 'active')
              .limit(1)
              .snapshots(),
          builder: (context, referralSnapshot) {
            final hasActiveReferralGame =
                referralSnapshot.data?.docs.isNotEmpty ?? false;
            return buildCarousel(
              hasActiveReferralGame: hasActiveReferralGame,
            );
          },
        );
      },
    );
  }

  Widget _buildHomeGamesCarousel(
    BuildContext context,
    List<GamesRecord> games, {
    required String sectionName,
    required String emptyTitle,
    required String emptyDescription,
  }) {
    if (games.isEmpty) {
      return SizedBox(
        height: AppStyles.gameCardHeight,
        child: ListEmptyComponentWidget(
          title: emptyTitle,
          description: emptyDescription,
        ),
      );
    }

    _logHomeSectionSummary(
      sectionName: sectionName,
      rawCount: games.length,
      filteredCount: games.length,
      sortedCount: games.length,
      widgetInputCount: games.length,
      renderItemCount: games.length,
    );

    return ListView.separated(
      padding: EdgeInsets.zero,
      primary: false,
      scrollDirection: Axis.horizontal,
      itemCount: games.length,
      separatorBuilder: (_, __) =>
          const SizedBox(width: _homeHorizontalCardGap),
      itemBuilder: (context, index) {
        final game = games[index];
        _logHomeRenderItem(
          sectionName: sectionName,
          index: index,
          game: game,
        );
        return _buildHomeGameCard(
          game: game,
          prizeText: game.prizeValue == 0
              ? 'Gains instantan\u00E9s'
              : _formatEuroAmount(game.prizeValue),
          endDateText: game.endDate != null
              ? "Jusqu'au : ${dateTimeFormat('d/M/y', game.endDate, locale: FFLocalizations.of(context).languageCode)}"
              : "Jusqu'au : -",
          onTap: () async {
            await _openGameDetails(game);
          },
        );
      },
    );
  }

  String _describeHomeGamesError(Object? error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'La lecture des jeux a été refusée. Réessayez dans un instant.';
        case 'failed-precondition':
          return 'La configuration des jeux est incomplète. Réessayez bientôt.';
        case 'unavailable':
          return 'Le service est temporairement indisponible. Vérifiez votre connexion.';
        default:
          return 'Impossible de charger les jeux pour le moment.';
      }
    }
    return 'Impossible de charger les jeux pour le moment.';
  }

  Widget _buildHomeCarouselLoading({
    String message = 'Chargement des jeux...',
  }) {
    return SizedBox(
      height: AppStyles.gameCardHeight,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 26.0,
              height: 26.0,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: 12.0),
            Text(
              message,
              textAlign: TextAlign.center,
              style: FlutterFlowTheme.of(context).bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeCarouselError({
    required Object? error,
    required VoidCallback onRetry,
  }) {
    return SizedBox(
      height: AppStyles.gameCardHeight,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _describeHomeGamesError(error),
                textAlign: TextAlign.center,
                style: FlutterFlowTheme.of(context).bodyMedium,
              ),
              const SizedBox(height: 12.0),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18.0),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeGameCard({
    required GamesRecord game,
    EnseignesRecord? enseigne,
    required String prizeText,
    required String endDateText,
    required Future<void> Function() onTap,
    String? winnerText,
    String? badgeText,
    String finishedInfoText = 'Jeu termin\u00E9',
    int winnerMaxLines = 1,
    bool isFinished = false,
    bool fitContent = true,
    double? width,
    double? height,
    double? imageHeight,
  }) {
    Widget buildCard(EnseignesRecord? resolvedEnseigne) {
      return GameCardWidget(
        title: game.name,
        imageUrl: game.photo,
        storeName: _getGameCardStoreName(game, resolvedEnseigne),
        city: _getGameCardLocation(resolvedEnseigne),
        prizeText: prizeText,
        endDateText: endDateText,
        badgeText: badgeText,
        winnerText: winnerText,
        gameAccessType: game.type,
        accessMode: game.accessMode,
        finishedInfoText: finishedInfoText,
        winnerMaxLines: winnerMaxLines,
        isFinished: isFinished,
        fitContent: fitContent,
        width: width ?? _computeHomeCardWidth(context),
        height: height,
        imageHeight: imageHeight,
        onTap: () async {
          await onTap();
        },
      );
    }

    final location = _getGameCardLocation(enseigne);
    if (location.isNotEmpty || game.enseigneId == null) {
      return buildCard(enseigne);
    }

    return FutureBuilder<EnseignesRecord>(
      future: _getCachedEnseigneFuture(game.enseigneId!),
      builder: (context, snapshot) {
        return buildCard(snapshot.data ?? enseigne);
      },
    );
  }

  Future<SharePromoStateViewModel?> _loadSharePromoState() async {
    if (isGuestOrAnonymous || currentUserUid.isEmpty) {
      _latestSharePromoState = null;
      return null;
    }
    try {
      final state = await _sharePromoService.getSharePromoState();
      _latestSharePromoState = state;
      return state;
    } catch (_) {
      _latestSharePromoState = null;
      return null;
    }
  }

  Future<MonthlyChallengeStateViewModel?> _loadMonthlyChallengeState() async {
    if (isGuestOrAnonymous || currentUserUid.isEmpty) {
      _latestMonthlyChallengeState = null;
      return null;
    }
    try {
      final state = await _monthlyChallengeService.getMonthlyChallengeState();
      _latestMonthlyChallengeState = state;
      if (state.showCard) {
        logFirebaseEvent(
          'monthly_challenge_viewed',
          parameters: {
            'month': state.month,
            'qualified': state.qualified,
            'active_days': state.activeDaysCount,
            'target_days': state.targetDays,
          },
        );
        logFirebaseEvent(
          'monthly_challenge_progress',
          parameters: {
            'month': state.month,
            'active_days': state.activeDaysCount,
            'target_days': state.targetDays,
            'remaining_days': state.remainingDays,
          },
        );
        if (state.qualified) {
          logFirebaseEvent(
            'monthly_challenge_qualified',
            parameters: {
              'month': state.month,
              'active_days': state.activeDaysCount,
            },
          );
        }
      }
      return state;
    } catch (_) {
      _latestMonthlyChallengeState = null;
      return null;
    }
  }

  SharePromoData? _buildSharePromoData(SharePromoStateViewModel? state) {
    if (state == null || !state.showBanner || state.kind == null) {
      return null;
    }

    switch (state.kind) {
      case 'rewardAvailable':
        return SharePromoData(
          kind: SharePromoKind.rewardAvailable,
          title: _normalizeVisibleText(
            state.title,
            fallback: 'R\u00E9compense disponible',
          ),
          subtitle: _normalizeVisibleText(
            state.message,
            fallback: 'Votre bonus de parrainage est disponible.',
          ),
          ctaLabel: _normalizeVisibleText(
            state.ctaText,
            fallback: 'Mes lots',
          ),
          icon: Icons.card_giftcard_rounded,
          primaryColor: const Color(0xFF2C296A),
          secondaryColor: const Color(0xFF5A56A8),
        );
      case 'friendPending':
        return SharePromoData(
          kind: SharePromoKind.friendPending,
          title: _normalizeVisibleText(
            state.title,
            fallback: 'Invitation en attente',
          ),
          subtitle: _normalizeVisibleText(
            state.message,
            fallback: 'Un partage est en cours.',
          ),
          ctaLabel: _normalizeVisibleText(
            state.ctaText,
            fallback: 'Relancer',
          ),
          icon: Icons.schedule_rounded,
          primaryColor: const Color(0xFF5A4E8E),
          secondaryColor: const Color(0xFF7B6FB3),
        );
      case 'specialCampaign':
        return SharePromoData(
          kind: SharePromoKind.specialCampaign,
          title: _normalizeVisibleText(
            state.title,
            fallback: 'Inviter un ami',
          ),
          subtitle: _normalizeVisibleText(
            state.message,
            fallback:
                'Aide un ami \u00E0 d\u00E9bloquer ses lots bonus avant minuit.',
          ),
          ctaLabel: _normalizeVisibleText(
            state.ctaText,
            fallback: 'Inviter un ami',
          ),
          icon: Icons.auto_awesome_rounded,
          primaryColor: const Color(0xFF9F2A63),
          secondaryColor: const Color(0xFFD34687),
        );
      default:
        return null;
    }
  }

  bool _hasActiveReferralBonus() {
    final accessUntil = currentUserDocument?.allGamesAccessUntil;
    if (accessUntil == null) {
      return false;
    }
    return accessUntil.isAfter(getCurrentTimestamp);
  }

  String _formatEuroAmount(double value) {
    final hasDecimals = value != value.truncateToDouble();
    if (!hasDecimals) {
      return '${value.toStringAsFixed(0)} €';
    }
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  Widget _buildMonthlyChallengeZone() {
    return FutureBuilder<MonthlyChallengeStateViewModel?>(
      future: _monthlyChallengeFuture,
      builder: (context, snapshot) {
        final state = snapshot.data ?? _latestMonthlyChallengeState;
        if (state == null || !state.showCard) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: MonthlyChallengeBannerWidget(state: state),
        );
      },
    );
  }

  String _readAnimationText(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is String ? value.trim() : '';
  }

  DateTime? _readAnimationDate(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is DateTime) {
      return value;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }

  Future<void> _openAnimationDetails(String animationId) async {
    await context.pushNamed(
      'AnimationDetailPage',
      queryParameters: {
        'animationId': serializeParam(
          animationId,
          ParamType.String,
        ),
      }.withoutNulls,
      extra: <String, dynamic>{
        'animationId': animationId,
        kTransitionInfoKey: const TransitionInfo(
          hasTransition: true,
          transitionType: PageTransitionType.rightToLeft,
        ),
      },
    );
  }

  Widget _buildAnimationCard(
    BuildContext context, {
    required String animationId,
    required String name,
    required String coverImage,
    required DateTime? endDate,
    bool isEnded = false,
  }) {
    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: () async {
        await _openAnimationDetails(animationId);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18.0),
        child: SizedBox(
          width: 248.0,
          height: 160.0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              coverImage.isNotEmpty
                  ? ProxiplayNetworkImage(
                      imageUrl: coverImage,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: FlutterFlowTheme.of(context).fieldBg,
                    ),
              if (isEnded)
                Container(color: Colors.black.withValues(alpha: 0.45)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.04),
                      Colors.black.withValues(alpha: 0.72),
                    ],
                    stops: const [0.45, 1.0],
                  ),
                ),
              ),
              if (isEnded)
                Positioned(
                  top: 10.0,
                  right: 10.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8.0, vertical: 4.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFFA0134D),
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    child: const Text(
                      'Terminé',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 14.0,
                right: 14.0,
                bottom: 12.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FlutterFlowTheme.of(context).titleMedium.override(
                            font: GoogleFonts.interTight(
                              fontWeight: FontWeight.w700,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .titleMedium
                                  .fontStyle,
                            ),
                            color: Colors.white,
                            letterSpacing: 0.0,
                          ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      endDate != null
                          ? isEnded
                              ? "Terminée le ${dateTimeFormat('dd/MM', endDate, locale: FFLocalizations.of(context).languageCode)}"
                              : "Jusqu'au ${dateTimeFormat('dd/MM', endDate, locale: FFLocalizations.of(context).languageCode)}"
                          : isEnded
                              ? 'Terminée'
                              : "Jusqu'au -",
                      style: FlutterFlowTheme.of(context).bodySmall.override(
                            font: GoogleFonts.inter(
                              fontWeight: FontWeight.w500,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .bodySmall
                                  .fontStyle,
                            ),
                            color: Colors.white.withValues(alpha: 0.92),
                            letterSpacing: 0.0,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinishedAnimationHomeCard(
    BuildContext context, {
    required String animationId,
    required String name,
    required String coverImage,
    required DateTime? endDate,
    String? winnerText,
  }) {
    return SizedBox(
      width: _computeHomeCardWidth(context),
      child: GameCardWidget(
        title: name,
        imageUrl: coverImage,
        storeName: 'Animation',
        city: '',
        prizeText: '​',
        endDateText: endDate != null
            ? "Terminée le ${dateTimeFormat('d/M/y', endDate, locale: FFLocalizations.of(context).languageCode)}"
            : 'Terminée',
        badgeText: 'Terminé',
        winnerText: winnerText,
        winnerMaxLines: 2,
        isFinished: true,
        fitContent: true,
        finishedInfoText: 'Animation terminée',
        imageHeight: AppStyles.finishedGameImageHeight,
        width: _computeHomeCardWidth(context),
        onTap: () async {
          await _openAnimationDetails(animationId);
        },
      ),
    );
  }

  Widget _buildFinishedAnimationInfoRow(
    BuildContext context,
    IconData icon,
    String text, {
    FontWeight? fontWeight,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1.0),
          child: Icon(icon, size: 18.0, color: const Color(0xFF26235C)),
        ),
        const SizedBox(width: 8.0),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  font: GoogleFonts.inter(
                    fontWeight: fontWeight ??
                        FlutterFlowTheme.of(context).bodySmall.fontWeight,
                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                  ),
                  color: const Color(0xFF26235C),
                  fontSize: AppStyles.gameCardBodySize,
                  letterSpacing: 0.0,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveAnimationsSection(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('animations')
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 15.0),
            child: _buildHomeCarouselError(
              error: snapshot.error,
              onRetry: () => setState(() {}),
            ),
          );
        }

        if (!snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 15.0),
            child: _buildHomeCarouselLoading(
              message: 'Chargement des animations...',
            ),
          );
        }

        final now = getCurrentTimestamp;
        final allDocs = snapshot.data!.docs;

        final activeAnimations = allDocs.where((doc) {
          final data = doc.data();
          final endDate = _readAnimationDate(data, 'end_date');
          final startDate = _readAnimationDate(data, 'start_date');
          if (endDate != null && !endDate.isAfter(now)) return false;
          if (startDate != null && startDate.isAfter(now)) return false;
          return true;
        }).toList()
          ..sort((a, b) {
            final aDate = _readAnimationDate(a.data(), 'end_date') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = _readAnimationDate(b.data(), 'end_date') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return aDate.compareTo(bDate);
          });

        if (activeAnimations.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 15.0),
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: _homeSectionTitleLeftInset,
                    bottom: 16.0,
                  ),
                  child: Text(
                    'ANIMATIONS EN COURS',
                    style: FlutterFlowTheme.of(context).titleLarge.override(
                          font: GoogleFonts.interTight(
                            fontWeight: FlutterFlowTheme.of(context)
                                .titleLarge
                                .fontWeight,
                            fontStyle: FlutterFlowTheme.of(context)
                                .titleLarge
                                .fontStyle,
                          ),
                          fontSize: 20.0,
                          letterSpacing: 0.0,
                          fontWeight: FlutterFlowTheme.of(context)
                              .titleLarge
                              .fontWeight,
                          fontStyle:
                              FlutterFlowTheme.of(context).titleLarge.fontStyle,
                        ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 160.0,
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    primary: false,
                    scrollDirection: Axis.horizontal,
                    itemCount: activeAnimations.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10.0),
                    itemBuilder: (context, index) {
                      final doc = activeAnimations[index];
                      final data = doc.data();
                      return _buildAnimationCard(
                        context,
                        animationId: doc.id,
                        name: _readAnimationText(data, 'name').isNotEmpty
                            ? _readAnimationText(data, 'name')
                            : 'Animation',
                        coverImage: _readAnimationText(data, 'cover_image'),
                        endDate: _readAnimationDate(data, 'end_date'),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopDynamicZone(BuildContext context) {
    return AuthUserStreamWidget(
      builder: (context) {
        final remainingPart = getSafeRemainingPart(
          currentUserDocument,
          triggerRepair: true,
          source: 'home_joueur',
        );
        final hasRemainingPart = remainingPart > 0;
        final hasNoRemainingPart = remainingPart <= 0;

        if (hasRemainingPart) {
          return const SizedBox.shrink();
        }

        if (_hasActiveReferralBonus()) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 16.0),
            child: SharePromoBanner(
              data: SharePromoData(
                kind: SharePromoKind.specialCampaign,
                title: 'Bonus parrainage actif',
                subtitle: 'Tu peux jouer à tous les jeux jusqu\'à minuit.',
                icon: Icons.auto_awesome_rounded,
                primaryColor: Color(0xFFF5F6FB),
                secondaryColor: Color(0xFF2C2F5B),
                titleColor: Color(0xFF2C2F5B),
                subtitleColor: Color(0xFF2C2F5B),
                iconBackgroundColor: Color(0xFFEAEFFD),
                iconColor: Color(0xFF2C2F5B),
              ),
            ),
          );
        }

        if (hasNoRemainingPart) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: SharePromoBanner(
              data: SharePromoData(
                kind: SharePromoKind.lowRemainingPlaysInvite,
                title: '',
                subtitle:
                    'Aide un ami à découvrir Proxiplay et joue à tous les jeux jusqu\'à minuit.',
                ctaLabel: 'Inviter un ami',
                icon: Icons.volunteer_activism_rounded,
                primaryColor: const Color(0xFFF5F6FB),
                secondaryColor: const Color(0xFFA0134D),
                titleColor: const Color(0xFF2C2F5B),
                subtitleColor: const Color(0xFF2C2F5B),
                buttonColor: const Color(0xFF2C2F5B),
                buttonTextColor: Colors.white,
                iconBackgroundColor: const Color(0xFFF7E6EE),
                iconColor: const Color(0xFFA0134D),
                animateCta: true,
              ),
              onTap: () {
                _showSharePromoSheet();
              },
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildRecentWinnersZone() {
    context.watch<FFAppState>();
    final messages = FFAppState().globalTickerMessages;
    if (messages.isEmpty) {
      return const SizedBox.shrink();
    }
    return RecentWinnersTicker(messages: messages);
  }

  String _buildRandomShareMessage({
    required String shareLink,
    required String? referralCode,
    required int rewardValue,
  }) {
    final normalizedReferralCode = referralCode?.trim();
    final referralCodeText = normalizedReferralCode == null ||
            normalizedReferralCode.isEmpty
        ? ''
        : '\n\nCode parrainage : $normalizedReferralCode\n\n'
            'Si le code ne se remplit pas automatiquement apr\u00E8s installation, '
            'entre-le manuellement lors de ton inscription.';

    final templates = [
      '$shareLink'
          '$referralCodeText\n\n'
          'Ton inscription avec mon code me d\u00E9bloque '
          '$rewardValue lot${rewardValue > 1 ? 's' : ''} bonus \u00E0 minuit.',
      'Viens jouer avec moi sur ProxiPlay \uD83C\uDF81\n\n'
          '$shareLink'
          '$referralCodeText\n\n'
          'Cr\u00E9e ton compte et aide-moi \u00E0 d\u00E9bloquer '
          '$rewardValue lot${rewardValue > 1 ? 's' : ''} bonus.',
      'Je t\'invite sur ProxiPlay \u2728\n\n'
          '$shareLink'
          '$referralCodeText\n\n'
          'Ton inscription me permet d\'obtenir '
          '$rewardValue lot${rewardValue > 1 ? 's' : ''} bonus.',
    ];
    return templates[_random.nextInt(templates.length)];
  }

  String _normalizeVisibleText(String? value, {required String fallback}) {
    final source = (value == null || value.trim().isEmpty) ? fallback : value;
    return source
        .replaceAllMapped(
          RegExp(r'\\u([0-9A-Fa-f]{4})'),
          (match) => String.fromCharCode(
            int.parse(match.group(1)!, radix: 16),
          ),
        )
        .replaceAll('gagnÃƒ©', 'gagn\u00E9')
        .replaceAll('RÃƒ©', 'R\u00E9')
        .replaceAll('rÃƒ©', 'r\u00E9')
        .replaceAll('Ãƒ©', '\u00E9')
        .replaceAll('Ãƒ¨', '\u00E8')
        .replaceAll('Ãƒª', '\u00EA')
        .replaceAll('Ãƒ«', '\u00EB')
        .replaceAll('Ãƒ ', '\u00E0')
        .replaceAll('Ãƒ ', '\u00E0')
        .replaceAll('Ãƒ¢', '\u00E2')
        .replaceAll('Ãƒ®', '\u00EE')
        .replaceAll('Ãƒ´', '\u00F4')
        .replaceAll('Ãƒ¹', '\u00F9')
        .replaceAll('Ãƒ»', '\u00FB')
        .replaceAll('Ãƒ§', '\u00E7')
        .replaceAll('Ã¢â‚¬â„¢', "'")
        .replaceAll('Ã¢â‚¬Ëœ', "'")
        .replaceAll('Ã¢â‚¬Å“', '"')
        .replaceAll('Ã¢â‚¬Â', '"')
        .replaceAll('Ã¢â‚¬Â¦', '...')
        .replaceAll('Ã¢â‚¬â€œ', '-')
        .replaceAll('Ã¢â‚¬â€', '-')
        .replaceAll('Ã¢â€š¬', '\u20AC')
        .replaceAllMapped(
          RegExp(r'\\bdachat\\b', caseSensitive: false),
          (match) => match.group(0)!.startsWith('D') ? "D'achat" : "d'achat",
        )
        .replaceAll('\uFFFD', '')
        .trim();
  }

  String _resolveShareLink(Map<String, dynamic> response) {
    final inviteCode = (response['inviteCode'] as String?)?.trim();
    final responseShareLink = (response['shareLink'] as String?)?.trim();
    final responseReferralCode =
        extractReferralCodeFromUri(Uri.tryParse(responseShareLink ?? ''));
    return buildReferralShareLink(inviteCode ?? responseReferralCode);
  }

  Future<Map<String, String>> _buildSharePromoPayload(String channel) async {
    final response = await _sharePromoService.createReferral(
      shareChannel: channel,
    );
    final shareLink = _resolveShareLink(response);
    final referralCode = extractReferralCodeFromUri(Uri.tryParse(shareLink));
    final rewardValue = _latestSharePromoState?.rewardValue ?? 1;
    return {
      'shareLink': shareLink,
      'shareText': _buildRandomShareMessage(
        shareLink: shareLink,
        rewardValue: rewardValue,
        referralCode: referralCode,
      ),
    };
  }

  Future<void> _copyShareText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _showSharePromoSheet() async {
    final payload = await _buildSharePromoPayload('native_share');
    final shareText = payload['shareText'] ?? buildAppShareText();

    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            duration: Duration(milliseconds: 1200),
            content: Text('Ouverture du partage...'),
          ),
        );
    }

    try {
      final box = context.findRenderObject() as RenderBox?;
      await Share.share(
        shareText,
        subject: 'Inviter un ami sur ProxiPlay',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (_) {
      await _copyShareText(shareText);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Partage natif indisponible. Le message a \\u00E9t\\u00E9 copi\\u00E9 dans le presse-papiers.',
          ),
        ),
      );
    }
  }

  Future<void> _submitSearch() async {
    final query = _model.textController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _model.simpleSearchResults = [];
        _model.searchActive = false;
      });
      return;
    }

    await queryGamesRecordOnce()
        .then(
          (records) => _model.simpleSearchResults = TextSearch(
            records
                .map(
                  (record) => TextSearchItem.fromTerms(record, [
                    record.name,
                    record.enseigneName,
                    record.description,
                  ]),
                )
                .toList(),
          ).search(query).map((r) => r.object).take(20).toList(),
        )
        .onError((_, __) => _model.simpleSearchResults = []);

    if (!mounted) {
      return;
    }
    setState(() {
      _model.searchActive = true;
    });
  }

  Widget _buildSearchBar(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).fieldBg,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: FlutterFlowTheme.of(context).alternate,
          width: 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8.0, 8.0, 8.0, 8.0),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              color: FlutterFlowTheme.of(context).primaryText,
              size: 24.0,
            ),
            Expanded(
              child: TextFormField(
                controller: _model.textController,
                focusNode: _model.textFieldFocusNode,
                onFieldSubmitted: (_) async => _submitSearch(),
                autofocus: false,
                obscureText: false,
                decoration: const InputDecoration(
                  alignLabelWithHint: false,
                  hintText: 'Rechercher un jeu',
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                ),
                style: FlutterFlowTheme.of(context).bodyMedium.override(
                      font: GoogleFonts.inter(
                        fontWeight:
                            FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                      ),
                      color: FlutterFlowTheme.of(context).fieldText,
                      letterSpacing: 0.0,
                      fontWeight:
                          FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                    ),
                textAlign: TextAlign.start,
                validator: _model.textControllerValidator.asValidator(context),
              ),
            ),
            if (_model.searchActive ||
                _model.textController.text.trim().isNotEmpty)
              InkWell(
                onTap: () {
                  safeSetState(() {
                    _model.textController?.clear();
                    _model.simpleSearchResults = [];
                    _model.searchActive = false;
                  });
                },
                child: Icon(
                  Icons.cancel_outlined,
                  color: FlutterFlowTheme.of(context).primary,
                  size: 24.0,
                ),
              ),
          ].divide(const SizedBox(width: 8.0)),
        ),
      ),
    );
  }

  Future<void> _handleSharePromoTap(SharePromoData data) async {
    if (data.kind == SharePromoKind.rewardAvailable) {
      context.pushNamed(LotsJoueurPageWidget.routeName);
      return;
    }
    await _showSharePromoSheet();
  }

  Widget _buildHomeSkeletonLoader(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        20.0,
        30.0,
        20.0,
        ProxiPlayLayout.bottomNavHeight(context) + 20.0,
      ),
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(height: 12.0),
        itemBuilder: (context, index) {
          return Container(
            height: AppStyles.gameCardHeight,
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).fieldBg,
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Row(
              children: [
                Container(
                  width: 110.0,
                  margin: const EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                    color: FlutterFlowTheme.of(context).alternate,
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        0.0, 14.0, 14.0, 14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 16.0,
                          decoration: BoxDecoration(
                            color: FlutterFlowTheme.of(context).alternate,
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                        const SizedBox(height: 10.0),
                        Container(
                          width: 150.0,
                          height: 12.0,
                          decoration: BoxDecoration(
                            color: FlutterFlowTheme.of(context).alternate,
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _refreshHomeContent() async {
    await refreshCurrentUserDocument();
    _sharePromoFuture = _loadSharePromoState();
    // Vider les caches d'enseignes pour forcer le rechargement des données fraîches.
    _featuredEnseignesSectionCache.clear();
    _endingSoonEnseignesSectionCache.clear();
    _newGamesEnseignesSectionCache.clear();
    final controllers = <PagingController<DocumentSnapshot?, GamesRecord>?>[
      _model.listViewPagingController2,
      _model.listViewPagingController3,
      _model.listViewPagingController4,
      _model.listViewPagingController5,
      _model.listViewPagingController6,
      _model.listViewPagingController7,
      _model.listViewPagingController8,
      _model.listViewPagingController9,
      _model.listViewPagingController10,
    ];
    for (final controller in controllers) {
      controller?.refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    if (_isRefreshingOnResume) return;
    final now = DateTime.now();
    if (_lastResumeRefresh != null &&
        now.difference(_lastResumeRefresh!) < const Duration(minutes: 5)) {
      return;
    }
    _lastResumeRefresh = now;
    _isRefreshingOnResume = true;
    _refreshHomeContent().whenComplete(() {
      _isRefreshingOnResume = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_homeDataReady) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          top: true,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ProxiplayLoadingLogo(size: 110.0),
                const SizedBox(height: 16.0),
                Text(
                  'Recherche des jeux disponibles...',
                  textAlign: TextAlign.center,
                  style: FlutterFlowTheme.of(context).bodyMedium.override(
                        font: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          fontStyle:
                              FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                        ),
                        color: const Color(0xFF6F6A8E),
                        fontSize: 14.0,
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w500,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: PopScope(
        canPop: false,
        child: Scaffold(
          key: scaffoldKey,
          resizeToAvoidBottomInset: false,
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(100.0),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0.0,
              scrolledUnderElevation: 0.0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              automaticallyImplyLeading: false,
              actions: const [],
              flexibleSpace: FlexibleSpaceBar(
                title: Align(
                  alignment: const AlignmentDirectional(0.0, 1.0),
                  child: wrapWithModel(
                    model: _model.appBarJoueurModel,
                    updateCallback: () => safeSetState(() {}),
                    child: const AppBarJoueurWidget(),
                  ),
                ),
                background: const SizedBox.shrink(),
                centerTitle: true,
                expandedTitleScale: 1.0,
                titlePadding:
                    const EdgeInsetsDirectional.fromSTEB(20.0, 30.0, 20.0, 0.0),
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: Container(
              height: double.infinity,
              decoration: BoxDecoration(
                image: DecorationImage(
                  fit: BoxFit.cover,
                  image: Image.asset(
                    'assets/images/Background.png',
                  ).image,
                ),
              ),
              child: Stack(
                children: [
                  Container(
                    height: double.infinity,
                    decoration: const BoxDecoration(),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          20.0, 0.0, 20.0, 100.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          if (_model.searchActive)
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                decoration: const BoxDecoration(),
                                child: Builder(
                                  builder: (context) {
                                    final search = _model.simpleSearchResults
                                        .where(_isGameVisibleForPlayer)
                                        .toList();
                                    if (search.isEmpty) {
                                      return const ListEmptyComponentWidget(
                                        title: 'Liste vide',
                                        description:
                                            'Aucun jeux pour le moment',
                                      );
                                    }

                                    return ListView.separated(
                                      padding: EdgeInsets.zero,
                                      scrollDirection: Axis.vertical,
                                      itemCount: search.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 10.0),
                                      itemBuilder: (context, searchIndex) {
                                        final searchItem = search[searchIndex];
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: FlutterFlowTheme.of(context)
                                                .secondaryBackground,
                                            borderRadius:
                                                BorderRadius.circular(20.0),
                                          ),
                                          child: StreamBuilder<EnseignesRecord>(
                                            stream: EnseignesRecord.getDocument(
                                                searchItem.enseigneId!),
                                            builder: (context, snapshot) {
                                              // Customize what your widget looks like when it's loading.
                                              if (!snapshot.hasData) {
                                                return const SizedBox.shrink();
                                              }

                                              final rowEnseignesRecord =
                                                  snapshot.data!;

                                              return InkWell(
                                                splashColor: Colors.transparent,
                                                focusColor: Colors.transparent,
                                                hoverColor: Colors.transparent,
                                                highlightColor:
                                                    Colors.transparent,
                                                onTap: () async {
                                                  context.pushNamed(
                                                    JeuDetailJoueurPageWidget
                                                        .routeName,
                                                    queryParameters: {
                                                      'gameDoc': serializeParam(
                                                        searchItem,
                                                        ParamType.Document,
                                                      ),
                                                      'enseigneDoc':
                                                          serializeParam(
                                                        rowEnseignesRecord,
                                                        ParamType.Document,
                                                      ),
                                                    }.withoutNulls,
                                                    extra: <String, dynamic>{
                                                      'gameDoc': searchItem,
                                                      'enseigneDoc':
                                                          rowEnseignesRecord,
                                                      'source': 'home_search',
                                                      kTransitionInfoKey:
                                                          const TransitionInfo(
                                                        hasTransition: true,
                                                        transitionType:
                                                            PageTransitionType
                                                                .fade,
                                                      ),
                                                    },
                                                  );
                                                },
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    Expanded(
                                                      flex: 1,
                                                      child: Container(
                                                        height: 130.0,
                                                        decoration:
                                                            const BoxDecoration(),
                                                        child: ClipRRect(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      8.0),
                                                          child:
                                                              ProxiplayNetworkImage(
                                                            imageUrl: searchItem
                                                                .photo,
                                                            fit: BoxFit.cover,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 2,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsetsDirectional
                                                                .fromSTEB(10.0,
                                                                0.0, 0.0, 0.0),
                                                        child: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.max,
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .start,
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              searchItem.name,
                                                              style: FlutterFlowTheme
                                                                      .of(context)
                                                                  .bodyMedium
                                                                  .override(
                                                                    font: GoogleFonts
                                                                        .inter(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodyMedium
                                                                          .fontStyle,
                                                                    ),
                                                                    letterSpacing:
                                                                        0.0,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodyMedium
                                                                        .fontStyle,
                                                                  ),
                                                            ),
                                                            Column(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .max,
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .spaceEvenly,
                                                              children: [
                                                                Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .max,
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .store_sharp,
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primaryText,
                                                                      size:
                                                                          18.0,
                                                                    ),
                                                                    Text(
                                                                      rowEnseignesRecord
                                                                          .name,
                                                                      style: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodySmall
                                                                          .override(
                                                                            font:
                                                                                GoogleFonts.inter(
                                                                              fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                            ),
                                                                            letterSpacing:
                                                                                0.0,
                                                                            fontWeight:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                            fontStyle:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                          ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .max,
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .location_on_sharp,
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primaryText,
                                                                      size:
                                                                          18.0,
                                                                    ),
                                                                    Text(
                                                                      rowEnseignesRecord
                                                                          .city,
                                                                      style: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodySmall
                                                                          .override(
                                                                            font:
                                                                                GoogleFonts.inter(
                                                                              fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                            ),
                                                                            letterSpacing:
                                                                                0.0,
                                                                            fontWeight:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                            fontStyle:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                          ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .max,
                                                                  children: [
                                                                    FaIcon(
                                                                      FontAwesomeIcons
                                                                          .piggyBank,
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primaryText,
                                                                      size:
                                                                          18.0,
                                                                    ),
                                                                    Text(
                                                                      ' Valeur : ',
                                                                      style: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodySmall
                                                                          .override(
                                                                            font:
                                                                                GoogleFonts.inter(
                                                                              fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                            ),
                                                                            letterSpacing:
                                                                                0.0,
                                                                            fontWeight:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                            fontStyle:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                          ),
                                                                    ),
                                                                    Text(
                                                                      searchItem.prizeValue ==
                                                                              0
                                                                          ? 'Gains instantan\u00E9s'
                                                                          : '${searchItem.prizeValue.toString()} \u20AC',
                                                                      style: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodySmall
                                                                          .override(
                                                                            font:
                                                                                GoogleFonts.inter(
                                                                              fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                            ),
                                                                            letterSpacing:
                                                                                0.0,
                                                                            fontWeight:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                            fontStyle:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                          ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .max,
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .calendar_month,
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primaryText,
                                                                      size:
                                                                          18.0,
                                                                    ),
                                                                    Text(
                                                                      ' Valable jusqu\'au : ',
                                                                      style: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodySmall
                                                                          .override(
                                                                            font:
                                                                                GoogleFonts.inter(
                                                                              fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                            ),
                                                                            letterSpacing:
                                                                                0.0,
                                                                            fontWeight:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                            fontStyle:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                          ),
                                                                    ),
                                                                    Text(
                                                                      dateTimeFormat(
                                                                        "d/M/y",
                                                                        searchItem
                                                                            .endDate!,
                                                                        locale:
                                                                            FFLocalizations.of(context).languageCode,
                                                                      ),
                                                                      style: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodySmall
                                                                          .override(
                                                                            font:
                                                                                GoogleFonts.inter(
                                                                              fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                            ),
                                                                            letterSpacing:
                                                                                0.0,
                                                                            fontWeight:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                            fontStyle:
                                                                                FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                          ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ].divide(
                                                                  const SizedBox(
                                                                      height:
                                                                          5.0)),
                                                            ),
                                                          ].divide(
                                                              const SizedBox(
                                                                  height: 5.0)),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          if (!_model.searchActive)
                            Expanded(
                              child: Container(
                                decoration: const BoxDecoration(),
                                child: Builder(
                                  builder: (context) {
                                    if (currentUserUid != '' || isGuestUser) {
                                      return Builder(
                                        builder: (context) {
                                          if (_showsFullGameCatalog) {
                                            _logHomeUserContext(
                                              branchName: 'adult_standard',
                                              isMinor: false,
                                            );
                                            _runHomeBranchDiagnostics(
                                              branchName: 'adult_standard',
                                            );
                                            return RefreshIndicator(
                                              key: const Key(
                                                  'RefreshIndicator_967r95af'),
                                              onRefresh: _refreshHomeContent,
                                              child: SingleChildScrollView(
                                                physics:
                                                    const AlwaysScrollableScrollPhysics(),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
                                                  children: [
                                                    _buildTopDynamicZone(
                                                        context),
                                                    _buildMonthlyChallengeZone(),
                                                    _buildRecentWinnersZone(),
                                                    _buildActiveAnimationsSection(
                                                      context,
                                                    ),
                                                    Container(
                                                      width: double.infinity,
                                                      decoration:
                                                          const BoxDecoration(),
                                                      child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.max,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          Text(
                                                            'JEUX \u00C0 LA UNE',
                                                            style: FlutterFlowTheme
                                                                    .of(context)
                                                                .titleLarge
                                                                .override(
                                                                  font: GoogleFonts
                                                                      .interTight(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontStyle,
                                                                  ),
                                                                  fontSize:
                                                                      20.0,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontStyle,
                                                                ),
                                                          ),
                                                          Builder(
                                                            builder: (context) {
                                                              _logHomeQueryBranch(
                                                                sectionName:
                                                                    'featured',
                                                                branchName:
                                                                    'adult_standard',
                                                                clauses: const [
                                                                  'hasWinner == false',
                                                                  'orderBy prize_value desc',
                                                                ],
                                                              );
                                                              final featuredController =
                                                                  _model
                                                                      .setListViewController2(
                                                                GamesRecord
                                                                    .collection
                                                                    .where(
                                                                      'hasWinner',
                                                                      isEqualTo:
                                                                          false,
                                                                    )
                                                                    .orderBy(
                                                                        'prize_value',
                                                                        descending:
                                                                            true),
                                                              );
                                                              return ListenableBuilder(
                                                                listenable:
                                                                    featuredController,
                                                                builder:
                                                                    (context,
                                                                        _) {
                                                                  final featuredGames = (featuredController
                                                                              .itemList ??
                                                                          const <GamesRecord>[])
                                                                      .where(
                                                                          _isGameVisibleForPlayer)
                                                                      .toList();

                                                                  if (featuredController
                                                                          .itemList !=
                                                                      null) {
                                                                    return Container(
                                                                      width: double
                                                                          .infinity,
                                                                      height: AppStyles
                                                                          .gameCardHeight,
                                                                      decoration:
                                                                          const BoxDecoration(),
                                                                      child:
                                                                          _buildFeaturedGamesCarousel(
                                                                        context,
                                                                        featuredGames,
                                                                        'À la une',
                                                                        showReferralGameCard:
                                                                            true,
                                                                      ),
                                                                    );
                                                                  }

                                                                  return FutureBuilder<
                                                                      Map<String,
                                                                          EnseignesRecord>>(
                                                                    future:
                                                                        _getFeaturedEnseignesForGames(
                                                                      featuredGames,
                                                                    ),
                                                                    builder:
                                                                        (context,
                                                                            enseignesSnapshot) {
                                                                      final enseignesByPath = enseignesSnapshot
                                                                              .data ??
                                                                          const <String,
                                                                              EnseignesRecord>{};

                                                                      return Container(
                                                                        width: double
                                                                            .infinity,
                                                                        height: AppStyles.gameCardHeight +
                                                                            8.0,
                                                                        decoration:
                                                                            const BoxDecoration(),
                                                                        child: PagedListView<
                                                                            DocumentSnapshot<Object?>?,
                                                                            GamesRecord>.separated(
                                                                          pagingController:
                                                                              featuredController,
                                                                          padding:
                                                                              EdgeInsets.zero,
                                                                          primary:
                                                                              false,
                                                                          reverse:
                                                                              false,
                                                                          scrollDirection:
                                                                              Axis.horizontal,
                                                                          separatorBuilder:
                                                                              (context, separatorIndex) {
                                                                            final items =
                                                                                featuredController.itemList ?? const <GamesRecord>[];
                                                                            final currentItemVisible =
                                                                                separatorIndex < items.length && _isGameVisibleForPlayer(items[separatorIndex]);
                                                                            final nextItemVisible =
                                                                                separatorIndex + 1 < items.length && _isGameVisibleForPlayer(items[separatorIndex + 1]);

                                                                            if (!currentItemVisible ||
                                                                                !nextItemVisible) {
                                                                              return const SizedBox.shrink();
                                                                            }

                                                                            return const SizedBox(width: _homeHorizontalCardGap);
                                                                          },
                                                                          builderDelegate:
                                                                              PagedChildBuilderDelegate<GamesRecord>(
                                                                            // Customize what your widget looks like when it's loading the first page.
                                                                            firstPageProgressIndicatorBuilder: (_) =>
                                                                                _buildHomeCarouselLoading(),
                                                                            // Customize what your widget looks like when it's loading another page.
                                                                            newPageProgressIndicatorBuilder: (_) =>
                                                                                _buildHomeCarouselLoading(
                                                                              message: 'Chargement...',
                                                                            ),
                                                                            firstPageErrorIndicatorBuilder: (_) =>
                                                                                _buildHomeCarouselError(
                                                                              error: featuredController.error,
                                                                              onRetry: featuredController.refresh,
                                                                            ),
                                                                            newPageErrorIndicatorBuilder: (_) =>
                                                                                _buildHomeCarouselError(
                                                                              error: featuredController.error,
                                                                              onRetry: featuredController.refresh,
                                                                            ),
                                                                            noItemsFoundIndicatorBuilder: (_) =>
                                                                                const SizedBox(
                                                                              height: AppStyles.gameCardHeight,
                                                                              child: ListEmptyComponentWidget(
                                                                                title: 'Liste vide',
                                                                                description: 'Il n\'y a pas de jeux pour le moment',
                                                                              ),
                                                                            ),
                                                                            itemBuilder: (context,
                                                                                listViewGamesRecord,
                                                                                listViewIndex) {
                                                                              if (!_isGameVisibleForPlayer(listViewGamesRecord)) {
                                                                                return const SizedBox.shrink();
                                                                              }
                                                                              final enseigne = listViewGamesRecord.enseigneId != null ? enseignesByPath[listViewGamesRecord.enseigneId!.path] : null;
                                                                              return _buildHomeGameCard(
                                                                                game: listViewGamesRecord,
                                                                                enseigne: enseigne,
                                                                                prizeText: listViewGamesRecord.prizeValue == 0 ? 'Gains instantan\u00E9s' : _formatEuroAmount(listViewGamesRecord.prizeValue),
                                                                                endDateText: listViewGamesRecord.endDate != null ? "Jusqu'au : ${dateTimeFormat('d/M/y', listViewGamesRecord.endDate, locale: FFLocalizations.of(context).languageCode)}" : "Jusqu'au : -",
                                                                                onTap: () async {
                                                                                  await _openGameDetails(listViewGamesRecord);
                                                                                },
                                                                              );
                                                                            },
                                                                          ),
                                                                        ),
                                                                      );
                                                                    },
                                                                  );
                                                                },
                                                              );
                                                            },
                                                          ),
                                                        ].divide(const SizedBox(
                                                            height: 5.0)),
                                                      ),
                                                    ),
                                                    Container(
                                                      width: double.infinity,
                                                      decoration:
                                                          const BoxDecoration(),
                                                      child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.max,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          Text(
                                                            'BIENT\u00D4T FINIS',
                                                            style: FlutterFlowTheme
                                                                    .of(context)
                                                                .titleLarge
                                                                .override(
                                                                  font: GoogleFonts
                                                                      .interTight(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontStyle,
                                                                  ),
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontStyle,
                                                                ),
                                                          ),
                                                          Builder(
                                                            builder: (context) {
                                                              _logHomeQueryBranch(
                                                                sectionName:
                                                                    'endingSoon',
                                                                branchName:
                                                                    'adult_standard',
                                                                clauses: [
                                                                  'hasWinner == false',
                                                                  'end_date > ${getCurrentTimestamp.toIso8601String()}',
                                                                  'orderBy end_date asc',
                                                                ],
                                                              );
                                                              final endingSoonController =
                                                                  _model
                                                                      .setListViewController4(
                                                                GamesRecord
                                                                    .collection
                                                                    .where(
                                                                      'hasWinner',
                                                                      isEqualTo:
                                                                          false,
                                                                    )
                                                                    .where(
                                                                      'end_date',
                                                                      isGreaterThan:
                                                                          getCurrentTimestamp,
                                                                    )
                                                                    .orderBy(
                                                                        'end_date'),
                                                              );
                                                              return ListenableBuilder(
                                                                listenable:
                                                                    endingSoonController,
                                                                builder:
                                                                    (context,
                                                                        _) {
                                                                  final endingSoonGames = (endingSoonController
                                                                              .itemList ??
                                                                          const <GamesRecord>[])
                                                                      .where(
                                                                          _isGameVisibleForPlayer)
                                                                      .toList();
                                                                  _logHomeGamesSection(
                                                                    'bientôt finis',
                                                                    endingSoonController
                                                                            .itemList ??
                                                                        const <GamesRecord>[],
                                                                    endingSoonGames,
                                                                  );
                                                                  if (endingSoonController
                                                                          .itemList !=
                                                                      null) {
                                                                    return FutureBuilder<
                                                                        Map<String,
                                                                            EnseignesRecord>>(
                                                                      future:
                                                                          _getEndingSoonEnseignesForGames(
                                                                        endingSoonGames,
                                                                      ),
                                                                      builder:
                                                                          (context,
                                                                              enseignesSnapshot) {
                                                                        final enseignesByPath =
                                                                            enseignesSnapshot.data ??
                                                                                const <String, EnseignesRecord>{};
                                                                        if (endingSoonGames
                                                                            .isEmpty) {
                                                                          return const SizedBox
                                                                              .shrink();
                                                                        }
                                                                        return Container(
                                                                          width:
                                                                              double.infinity,
                                                                          height:
                                                                              AppStyles.gameCardHeight,
                                                                          decoration:
                                                                              const BoxDecoration(
                                                                            color:
                                                                                Colors.transparent,
                                                                          ),
                                                                          child:
                                                                              ListView.separated(
                                                                            padding:
                                                                                EdgeInsets.zero,
                                                                            primary:
                                                                                false,
                                                                            scrollDirection:
                                                                                Axis.horizontal,
                                                                            itemCount:
                                                                                endingSoonGames.length,
                                                                            separatorBuilder: (_, __) =>
                                                                                const SizedBox(width: _homeHorizontalCardGap),
                                                                            itemBuilder:
                                                                                (context, index) {
                                                                              final game = endingSoonGames[index];
                                                                              final enseigne = game.enseigneId != null ? enseignesByPath[game.enseigneId!.path] : null;
                                                                              return _buildHomeGameCard(
                                                                                game: game,
                                                                                enseigne: enseigne,
                                                                                prizeText: game.prizeValue == 0 ? 'Gains instantan\u00E9s' : _formatEuroAmount(game.prizeValue),
                                                                                endDateText: game.endDate != null ? "Jusqu'au : ${dateTimeFormat('d/M/y', game.endDate, locale: FFLocalizations.of(context).languageCode)}" : "Jusqu'au : -",
                                                                                onTap: () async {
                                                                                  await _openGameDetails(game);
                                                                                },
                                                                              );
                                                                            },
                                                                          ),
                                                                        );
                                                                      },
                                                                    );
                                                                  }
                                                                  return FutureBuilder<
                                                                      Map<String,
                                                                          EnseignesRecord>>(
                                                                    future:
                                                                        _getEndingSoonEnseignesForGames(
                                                                      endingSoonGames,
                                                                    ),
                                                                    builder:
                                                                        (context,
                                                                            enseignesSnapshot) {
                                                                      final enseignesByPath = enseignesSnapshot
                                                                              .data ??
                                                                          const <String,
                                                                              EnseignesRecord>{};

                                                                      return Container(
                                                                        width: double
                                                                            .infinity,
                                                                        height: AppStyles.gameCardHeight +
                                                                            8.0,
                                                                        decoration:
                                                                            const BoxDecoration(
                                                                          color:
                                                                              Colors.transparent,
                                                                        ),
                                                                        child: PagedListView<
                                                                            DocumentSnapshot<Object?>?,
                                                                            GamesRecord>.separated(
                                                                          pagingController:
                                                                              endingSoonController,
                                                                          padding:
                                                                              EdgeInsets.zero,
                                                                          primary:
                                                                              false,
                                                                          reverse:
                                                                              false,
                                                                          scrollDirection:
                                                                              Axis.horizontal,
                                                                          separatorBuilder: (_, __) =>
                                                                              const SizedBox(width: 10.0),
                                                                          builderDelegate:
                                                                              PagedChildBuilderDelegate<GamesRecord>(
                                                                            // Customize what your widget looks like when it's loading the first page.
                                                                            firstPageProgressIndicatorBuilder: (_) =>
                                                                                _buildHomeCarouselLoading(),
                                                                            // Customize what your widget looks like when it's loading another page.
                                                                            newPageProgressIndicatorBuilder: (_) =>
                                                                                _buildHomeCarouselLoading(
                                                                              message: 'Chargement...',
                                                                            ),
                                                                            firstPageErrorIndicatorBuilder: (_) =>
                                                                                _buildHomeCarouselError(
                                                                              error: endingSoonController.error,
                                                                              onRetry: endingSoonController.refresh,
                                                                            ),
                                                                            newPageErrorIndicatorBuilder: (_) =>
                                                                                _buildHomeCarouselError(
                                                                              error: endingSoonController.error,
                                                                              onRetry: endingSoonController.refresh,
                                                                            ),
                                                                            noItemsFoundIndicatorBuilder: (_) =>
                                                                                const ListEmptyComponentWidget(
                                                                              title: 'Aucun jeux',
                                                                              description: ' ',
                                                                            ),
                                                                            itemBuilder: (context,
                                                                                listViewGamesRecord,
                                                                                listViewIndex) {
                                                                              final enseigne = listViewGamesRecord.enseigneId != null ? enseignesByPath[listViewGamesRecord.enseigneId!.path] : null;
                                                                              return _buildHomeGameCard(
                                                                                game: listViewGamesRecord,
                                                                                enseigne: enseigne,
                                                                                prizeText: listViewGamesRecord.prizeValue == 0 ? 'Gains instantan\u00E9s' : _formatEuroAmount(listViewGamesRecord.prizeValue),
                                                                                endDateText: listViewGamesRecord.endDate != null ? "Jusqu'au : ${dateTimeFormat('d/M/y', listViewGamesRecord.endDate, locale: FFLocalizations.of(context).languageCode)}" : "Jusqu'au : -",
                                                                                onTap: () async {
                                                                                  await _openGameDetails(listViewGamesRecord);
                                                                                },
                                                                              );
                                                                            },
                                                                          ),
                                                                        ),
                                                                      );
                                                                    },
                                                                  );
                                                                },
                                                              );
                                                            },
                                                          ),
                                                        ].divide(const SizedBox(
                                                            height: 5.0)),
                                                      ),
                                                    ),
                                                    Container(
                                                      width: double.infinity,
                                                      decoration:
                                                          const BoxDecoration(),
                                                      child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.max,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          Padding(
                                                            padding:
                                                                const EdgeInsetsDirectional
                                                                    .only(
                                                              start:
                                                                  _homeSectionTitleLeftInset,
                                                            ),
                                                            child: Text(
                                                              'NOUVEAUT\u00C9S',
                                                              style: FlutterFlowTheme
                                                                      .of(context)
                                                                  .titleLarge
                                                                  .override(
                                                                    font: GoogleFonts
                                                                        .interTight(
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontStyle,
                                                                    ),
                                                                    letterSpacing:
                                                                        0.0,
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontStyle,
                                                                  ),
                                                            ),
                                                          ),
                                                          Builder(
                                                            builder: (context) {
                                                              _logHomeQueryBranch(
                                                                sectionName:
                                                                    'new',
                                                                branchName:
                                                                    'adult_standard',
                                                                clauses: const [
                                                                  'hasWinner == false',
                                                                  'orderBy created_time desc',
                                                                ],
                                                              );
                                                              final newGamesController =
                                                                  _model
                                                                      .setListViewController3(
                                                                GamesRecord
                                                                    .collection
                                                                    .where(
                                                                      'hasWinner',
                                                                      isEqualTo:
                                                                          false,
                                                                    )
                                                                    .orderBy(
                                                                        'created_time',
                                                                        descending:
                                                                            true),
                                                              );
                                                              return ListenableBuilder(
                                                                listenable:
                                                                    newGamesController,
                                                                builder:
                                                                    (context,
                                                                        _) {
                                                                  final newGames = (newGamesController
                                                                              .itemList ??
                                                                          const <GamesRecord>[])
                                                                      .where(
                                                                          _isGameVisibleForPlayer)
                                                                      .toList();
                                                                  _logHomeGamesSection(
                                                                    'nouveautés',
                                                                    newGamesController
                                                                            .itemList ??
                                                                        const <GamesRecord>[],
                                                                    newGames,
                                                                  );

                                                                  if (newGamesController
                                                                          .itemList !=
                                                                      null) {
                                                                    return FutureBuilder<
                                                                        Map<String,
                                                                            EnseignesRecord>>(
                                                                      future:
                                                                          _getNewGamesEnseignesForGames(
                                                                        newGames,
                                                                      ),
                                                                      builder:
                                                                          (context,
                                                                              enseignesSnapshot) {
                                                                        final enseignesByPath =
                                                                            enseignesSnapshot.data ??
                                                                                const <String, EnseignesRecord>{};
                                                                        return Container(
                                                                          width:
                                                                              double.infinity,
                                                                          height:
                                                                              AppStyles.gameCardHeight,
                                                                          decoration:
                                                                              const BoxDecoration(
                                                                            color:
                                                                                Colors.transparent,
                                                                          ),
                                                                          child:
                                                                              ListView.separated(
                                                                            padding:
                                                                                EdgeInsets.zero,
                                                                            primary:
                                                                                false,
                                                                            scrollDirection:
                                                                                Axis.horizontal,
                                                                            itemCount:
                                                                                newGames.length,
                                                                            separatorBuilder: (_, __) =>
                                                                                const SizedBox(width: _homeHorizontalCardGap),
                                                                            itemBuilder:
                                                                                (context, index) {
                                                                              final game = newGames[index];
                                                                              final enseigne = game.enseigneId != null ? enseignesByPath[game.enseigneId!.path] : null;
                                                                              return _buildHomeGameCard(
                                                                                game: game,
                                                                                enseigne: enseigne,
                                                                                prizeText: game.prizeValue == 0 ? 'Gains instantan\u00E9s' : _formatEuroAmount(game.prizeValue),
                                                                                endDateText: game.endDate != null ? "Jusqu'au : ${dateTimeFormat('d/M/y', game.endDate, locale: FFLocalizations.of(context).languageCode)}" : "Jusqu'au : -",
                                                                                onTap: () async {
                                                                                  await _openGameDetails(game);
                                                                                },
                                                                              );
                                                                            },
                                                                          ),
                                                                        );
                                                                      },
                                                                    );
                                                                  }

                                                                  return FutureBuilder<
                                                                      Map<String,
                                                                          EnseignesRecord>>(
                                                                    future:
                                                                        _getNewGamesEnseignesForGames(
                                                                      newGames,
                                                                    ),
                                                                    builder:
                                                                        (context,
                                                                            enseignesSnapshot) {
                                                                      final enseignesByPath = enseignesSnapshot
                                                                              .data ??
                                                                          const <String,
                                                                              EnseignesRecord>{};

                                                                      return Container(
                                                                        width: double
                                                                            .infinity,
                                                                        height: AppStyles.gameCardHeight +
                                                                            8.0,
                                                                        decoration:
                                                                            const BoxDecoration(
                                                                          color:
                                                                              Colors.transparent,
                                                                        ),
                                                                        child: PagedListView<
                                                                            DocumentSnapshot<Object?>?,
                                                                            GamesRecord>.separated(
                                                                          pagingController:
                                                                              newGamesController,
                                                                          padding:
                                                                              EdgeInsets.zero,
                                                                          primary:
                                                                              false,
                                                                          reverse:
                                                                              false,
                                                                          scrollDirection:
                                                                              Axis.horizontal,
                                                                          separatorBuilder:
                                                                              (context, separatorIndex) {
                                                                            final items =
                                                                                newGamesController.itemList ?? const <GamesRecord>[];
                                                                            final currentItemVisible =
                                                                                separatorIndex < items.length && _isGameVisibleForPlayer(items[separatorIndex]);
                                                                            final nextItemVisible =
                                                                                separatorIndex + 1 < items.length && _isGameVisibleForPlayer(items[separatorIndex + 1]);

                                                                            if (!currentItemVisible ||
                                                                                !nextItemVisible) {
                                                                              return const SizedBox.shrink();
                                                                            }

                                                                            return const SizedBox(width: _homeHorizontalCardGap);
                                                                          },
                                                                          builderDelegate:
                                                                              PagedChildBuilderDelegate<GamesRecord>(
                                                                            // Customize what your widget looks like when it's loading the first page.
                                                                            firstPageProgressIndicatorBuilder: (_) =>
                                                                                _buildHomeCarouselLoading(),
                                                                            // Customize what your widget looks like when it's loading another page.
                                                                            newPageProgressIndicatorBuilder: (_) =>
                                                                                _buildHomeCarouselLoading(
                                                                              message: 'Chargement...',
                                                                            ),
                                                                            firstPageErrorIndicatorBuilder: (_) =>
                                                                                _buildHomeCarouselError(
                                                                              error: newGamesController.error,
                                                                              onRetry: newGamesController.refresh,
                                                                            ),
                                                                            newPageErrorIndicatorBuilder: (_) =>
                                                                                _buildHomeCarouselError(
                                                                              error: newGamesController.error,
                                                                              onRetry: newGamesController.refresh,
                                                                            ),
                                                                            noItemsFoundIndicatorBuilder: (_) =>
                                                                                const ListEmptyComponentWidget(
                                                                              title: 'Aucune nouveaut\u00E9',
                                                                              description: 'Votre liste est actuellement vide',
                                                                            ),
                                                                            itemBuilder: (context,
                                                                                listViewGamesRecord,
                                                                                listViewIndex) {
                                                                              if (!_isGameVisibleForPlayer(listViewGamesRecord)) {
                                                                                return const SizedBox.shrink();
                                                                              }

                                                                              final enseigne = listViewGamesRecord.enseigneId != null ? enseignesByPath[listViewGamesRecord.enseigneId!.path] : null;

                                                                              return _buildHomeGameCard(
                                                                                game: listViewGamesRecord,
                                                                                enseigne: enseigne,
                                                                                prizeText: listViewGamesRecord.prizeValue == 0 ? 'Gains instantan\u00E9s' : _formatEuroAmount(listViewGamesRecord.prizeValue),
                                                                                endDateText: listViewGamesRecord.endDate != null ? "Jusqu'au : ${dateTimeFormat('d/M/y', listViewGamesRecord.endDate, locale: FFLocalizations.of(context).languageCode)}" : "Jusqu'au : -",
                                                                                onTap: () async {
                                                                                  await _openGameDetails(listViewGamesRecord);
                                                                                },
                                                                              );
                                                                            },
                                                                          ),
                                                                        ),
                                                                      );
                                                                    },
                                                                  );
                                                                },
                                                              );
                                                            },
                                                          ),
                                                          Padding(
                                                            padding:
                                                                const EdgeInsetsDirectional
                                                                    .only(
                                                              start:
                                                                  _homeSectionTitleLeftInset,
                                                            ),
                                                            child: Text(
                                                              'JEUX TERMIN\u00C9S',
                                                              style: FlutterFlowTheme
                                                                      .of(context)
                                                                  .titleLarge
                                                                  .override(
                                                                    font: GoogleFonts
                                                                        .interTight(
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontStyle,
                                                                    ),
                                                                    letterSpacing:
                                                                        0.0,
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontStyle,
                                                                  ),
                                                            ),
                                                          ),
                                                          StreamBuilder<
                                                              List<
                                                                  GamesRecord>>(
                                                            stream:
                                                                queryGamesRecord(
                                                              queryBuilder:
                                                                  (query) => query
                                                                      .orderBy(
                                                                'end_date',
                                                                descending:
                                                                    true,
                                                              ),
                                                              limit: 80,
                                                            ),
                                                            builder: (context,
                                                                snapshot) {
                                                              if (snapshot
                                                                  .hasError) {
                                                                return _buildHomeCarouselError(
                                                                  error: snapshot
                                                                      .error,
                                                                  onRetry: () =>
                                                                      safeSetState(
                                                                          () {}),
                                                                );
                                                              }
                                                              if (!snapshot
                                                                  .hasData) {
                                                                return _buildHomeCarouselLoading();
                                                              }
                                                              _markHomeDataReady(
                                                                itemCount: snapshot
                                                                        .data
                                                                        ?.length ??
                                                                    0,
                                                              );
                                                              final now =
                                                                  getCurrentTimestamp;
                                                              final recentlyEndedGames =
                                                                  snapshot.data!
                                                                      .where(
                                                                          (g) {
                                                                final end =
                                                                    g.endDate;
                                                                if (end ==
                                                                    null) {
                                                                  return false;
                                                                }
                                                                final endPlus30Days =
                                                                    end.add(const Duration(
                                                                        days:
                                                                            30));
                                                                return now.isAfter(
                                                                        end) &&
                                                                    now.isBefore(
                                                                        endPlus30Days);
                                                              }).toList();

                                                              return StreamBuilder<
                                                                  QuerySnapshot<
                                                                      Map<String,
                                                                          dynamic>>>(
                                                                stream: FirebaseFirestore
                                                                    .instance
                                                                    .collection(
                                                                        'animations')
                                                                    .where(
                                                                      'status',
                                                                      isEqualTo:
                                                                          'active',
                                                                    )
                                                                    .snapshots(),
                                                                builder: (context,
                                                                    animationsSnapshot) {
                                                                  if (animationsSnapshot
                                                                      .hasError) {
                                                                    return _buildHomeCarouselError(
                                                                      error: animationsSnapshot
                                                                          .error,
                                                                      onRetry: () =>
                                                                          safeSetState(
                                                                              () {}),
                                                                    );
                                                                  }
                                                                  if (!animationsSnapshot
                                                                      .hasData) {
                                                                    return _buildHomeCarouselLoading(
                                                                      message:
                                                                          'Chargement...',
                                                                    );
                                                                  }

                                                                  final thirtyDaysAgo =
                                                                      now.subtract(
                                                                    const Duration(
                                                                        days:
                                                                            30),
                                                                  );
                                                                  final recentEndedAnimations =
                                                                      animationsSnapshot
                                                                          .data!
                                                                          .docs
                                                                          .where(
                                                                              (doc) {
                                                                    final data =
                                                                        doc.data();
                                                                    final endDate =
                                                                        _readAnimationDate(
                                                                      data,
                                                                      'end_date',
                                                                    );
                                                                    if (endDate ==
                                                                        null) {
                                                                      return false;
                                                                    }
                                                                    return !endDate.isAfter(
                                                                            now) &&
                                                                        endDate.isAfter(
                                                                            thirtyDaysAgo);
                                                                  }).toList();

                                                                  final finishedItems =
                                                                      <Map<
                                                                          String,
                                                                          dynamic>>[
                                                                    ...recentlyEndedGames
                                                                        .map(
                                                                      (game) =>
                                                                          {
                                                                        'type':
                                                                            'game',
                                                                        'endDate':
                                                                            game.endDate,
                                                                        'game':
                                                                            game,
                                                                      },
                                                                    ),
                                                                    ...recentEndedAnimations
                                                                        .map(
                                                                      (animation) =>
                                                                          {
                                                                        'type':
                                                                            'animation',
                                                                        'endDate':
                                                                            _readAnimationDate(
                                                                          animation
                                                                              .data(),
                                                                          'end_date',
                                                                        ),
                                                                        'animation':
                                                                            animation,
                                                                      },
                                                                    ),
                                                                  ]..sort((a,
                                                                            b) {
                                                                          final aDate =
                                                                              a['endDate'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0);
                                                                          final bDate =
                                                                              b['endDate'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0);
                                                                          return bDate
                                                                              .compareTo(aDate);
                                                                        });

                                                                  if (finishedItems
                                                                      .isEmpty) {
                                                                    return const ListEmptyComponentWidget(
                                                                      title:
                                                                          'Aucun jeu termin\u00E9',
                                                                      description:
                                                                          ' ',
                                                                    );
                                                                  }

                                                                  return SizedBox(
                                                                    width: double
                                                                        .infinity,
                                                                    height: AppStyles
                                                                        .finishedGameListHeight,
                                                                    child: ListView
                                                                        .separated(
                                                                      padding:
                                                                          EdgeInsets
                                                                              .zero,
                                                                      primary:
                                                                          false,
                                                                      scrollDirection:
                                                                          Axis.horizontal,
                                                                      itemCount:
                                                                          finishedItems
                                                                              .length,
                                                                      separatorBuilder: (_,
                                                                              __) =>
                                                                          const SizedBox(
                                                                              width: 10.0),
                                                                      itemBuilder:
                                                                          (context,
                                                                              idx) {
                                                                        final item =
                                                                            finishedItems[idx];
                                                                        if (item['type'] ==
                                                                            'game') {
                                                                          final game =
                                                                              item['game'] as GamesRecord;
                                                                          return FutureBuilder<
                                                                              EnseignesRecord>(
                                                                            future:
                                                                                _getCachedEnseigneFuture(game.enseigneId!),
                                                                            builder:
                                                                                (context, enseigneSnapshot) {
                                                                              final enseigne = enseigneSnapshot.data;
                                                                              final hasVisibleMainPrize = _hasVisibleMainPrizeForPlayer(game);
                                                                              final finishedBadgeText = !hasVisibleMainPrize ? 'Lots attribu\u00E9s' : null;
                                                                              final finishedInfoText = !hasVisibleMainPrize ? 'Lots secondaires attribu\u00E9s' : 'Jeu termin\u00E9';
                                                                              if (game.mainPrizeWinner == null) {
                                                                                return _buildHomeGameCard(
                                                                                  game: game,
                                                                                  enseigne: enseigne,
                                                                                  prizeText: game.prizeValue == 0 ? 'Gains instantan\u00E9s' : _formatEuroAmount(game.prizeValue),
                                                                                  endDateText: game.endDate != null ? "Jusqu'au : ${dateTimeFormat('d/M/y', game.endDate, locale: FFLocalizations.of(context).languageCode)}" : "Jusqu'au : -",
                                                                                  badgeText: finishedBadgeText,
                                                                                  isFinished: true,
                                                                                  fitContent: true,
                                                                                  finishedInfoText: finishedInfoText,
                                                                                  imageHeight: AppStyles.finishedGameImageHeight,
                                                                                  onTap: () async {
                                                                                    await _openGameDetails(game);
                                                                                  },
                                                                                );
                                                                              }
                                                                              return FutureBuilder<UsersRecord?>(
                                                                                future: fetchWinnerUserIfNeeded(
                                                                                  gameData: game.snapshotData,
                                                                                  winnerRef: game.mainPrizeWinner,
                                                                                ),
                                                                                builder: (context, winnerSnapshot) {
                                                                                  final winner = winnerSnapshot.data;
                                                                                  final winnerLabel = buildWinnerLabelFromSources(
                                                                                    gameData: game.snapshotData,
                                                                                    user: winner,
                                                                                    fallback: 'Gagnant annonc\u00E9',
                                                                                  );
                                                                                  return _buildHomeGameCard(
                                                                                    game: game,
                                                                                    enseigne: enseigne,
                                                                                    prizeText: game.prizeValue == 0 ? 'Gains instantan\u00E9s' : _formatEuroAmount(game.prizeValue),
                                                                                    endDateText: game.endDate != null ? "Jusqu'au : ${dateTimeFormat('d/M/y', game.endDate, locale: FFLocalizations.of(context).languageCode)}" : "Jusqu'au : -",
                                                                                    badgeText: finishedBadgeText,
                                                                                    winnerText: winnerLabel,
                                                                                    winnerMaxLines: 1,
                                                                                    isFinished: true,
                                                                                    fitContent: true,
                                                                                    finishedInfoText: finishedInfoText,
                                                                                    imageHeight: AppStyles.finishedGameImageHeight,
                                                                                    onTap: () async {
                                                                                      await _openGameDetails(game);
                                                                                    },
                                                                                  );
                                                                                },
                                                                              );
                                                                            },
                                                                          );
                                                                        }

                                                                        final animation =
                                                                            item['animation']
                                                                                as QueryDocumentSnapshot<Map<String, dynamic>>;
                                                                        final animationData =
                                                                            animation.data();
                                                                        return StreamBuilder<
                                                                            DocumentSnapshot<Map<String, dynamic>>>(
                                                                          stream: FirebaseFirestore
                                                                              .instance
                                                                              .doc('animations/${animation.id}/winner/current')
                                                                              .snapshots(),
                                                                          builder:
                                                                              (context, winnerSnapshot) {
                                                                            final winnerData =
                                                                                winnerSnapshot.data?.data() ?? const <String, dynamic>{};
                                                                            final winnerLabel =
                                                                                (winnerData['label'] as String? ?? '').trim();
                                                                            return _buildFinishedAnimationHomeCard(
                                                                              context,
                                                                              animationId: animation.id,
                                                                              name: _readAnimationText(animationData, 'name').isNotEmpty ? _readAnimationText(animationData, 'name') : 'Animation',
                                                                              coverImage: _readAnimationText(animationData, 'cover_image'),
                                                                              endDate: _readAnimationDate(animationData, 'end_date'),
                                                                              winnerText: winnerLabel,
                                                                            );
                                                                          },
                                                                        );
                                                                      },
                                                                    ),
                                                                  );
                                                                },
                                                              );
                                                            },
                                                          ),
                                                        ].divide(const SizedBox(
                                                            height: 5.0)),
                                                      ),
                                                    ),
                                                  ].divide(const SizedBox(
                                                      height: 3.0)),
                                                ),
                                              ),
                                            );
                                          } else {
                                            _logHomeUserContext(
                                              branchName: 'minor_filtered',
                                              isMinor: true,
                                            );
                                            _runHomeBranchDiagnostics(
                                              branchName: 'minor_filtered',
                                            );
                                            return SingleChildScrollView(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.max,
                                                children: [
                                                  _buildActiveAnimationsSection(
                                                    context,
                                                  ),
                                                  Container(
                                                    width: double.infinity,
                                                    decoration:
                                                        const BoxDecoration(),
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.max,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        Padding(
                                                          padding:
                                                              const EdgeInsetsDirectional
                                                                  .fromSTEB(
                                                                  _homeSectionTitleLeftInset,
                                                                  0.0,
                                                                  0.0,
                                                                  16.0),
                                                          child: Text(
                                                            'JEUX \u00C0 LA UNE',
                                                            style: FlutterFlowTheme
                                                                    .of(context)
                                                                .titleLarge
                                                                .override(
                                                                  font: GoogleFonts
                                                                      .interTight(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontStyle,
                                                                  ),
                                                                  fontSize:
                                                                      20.0,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontStyle,
                                                                ),
                                                          ),
                                                        ),
                                                        Container(
                                                          width:
                                                              double.infinity,
                                                          height: AppStyles
                                                              .gameCardHeight,
                                                          decoration:
                                                              const BoxDecoration(),
                                                          child: PagedListView<
                                                              DocumentSnapshot<
                                                                  Object?>?,
                                                              GamesRecord>.separated(
                                                            // Branch réelle mineur: Firestore exclut les jeux
                                                            // `prohibited_for_minors != false` et les champs absents.
                                                            pagingController: _model
                                                                .setListViewController5(
                                                              GamesRecord
                                                                  .collection
                                                                  .where(
                                                                    'hasWinner',
                                                                    isEqualTo:
                                                                        false,
                                                                  )
                                                                  .where(
                                                                    'prohibited_for_minors',
                                                                    isEqualTo:
                                                                        false,
                                                                  )
                                                                  .orderBy(
                                                                      'prize_value',
                                                                      descending:
                                                                          true),
                                                            ),
                                                            padding:
                                                                EdgeInsets.zero,
                                                            primary: false,
                                                            reverse: false,
                                                            scrollDirection:
                                                                Axis.horizontal,
                                                            separatorBuilder:
                                                                (context,
                                                                    separatorIndex) {
                                                              final items = _model
                                                                      .listViewPagingController5
                                                                      ?.itemList ??
                                                                  const <GamesRecord>[];
                                                              final currentItemVisible =
                                                                  separatorIndex <
                                                                          items
                                                                              .length &&
                                                                      _isGameVisibleForPlayer(
                                                                          items[
                                                                              separatorIndex]);
                                                              final nextItemVisible = separatorIndex +
                                                                          1 <
                                                                      items
                                                                          .length &&
                                                                  _isGameVisibleForPlayer(items[
                                                                      separatorIndex +
                                                                          1]);

                                                              if (!currentItemVisible ||
                                                                  !nextItemVisible) {
                                                                return const SizedBox
                                                                    .shrink();
                                                              }

                                                              return const SizedBox(
                                                                  width:
                                                                      _homeHorizontalCardGap);
                                                            },
                                                            builderDelegate:
                                                                PagedChildBuilderDelegate<
                                                                    GamesRecord>(
                                                              // Customize what your widget looks like when it's loading the first page.
                                                              firstPageProgressIndicatorBuilder:
                                                                  (_) =>
                                                                      _buildHomeCarouselLoading(),
                                                              // Customize what your widget looks like when it's loading another page.
                                                              newPageProgressIndicatorBuilder:
                                                                  (_) =>
                                                                      _buildHomeCarouselLoading(
                                                                message:
                                                                    'Chargement...',
                                                              ),
                                                              firstPageErrorIndicatorBuilder:
                                                                  (_) =>
                                                                      _buildHomeCarouselError(
                                                                error: _model
                                                                    .listViewPagingController5
                                                                    ?.error,
                                                                onRetry: () => _model
                                                                    .listViewPagingController5
                                                                    ?.refresh(),
                                                              ),
                                                              newPageErrorIndicatorBuilder:
                                                                  (_) =>
                                                                      _buildHomeCarouselError(
                                                                error: _model
                                                                    .listViewPagingController5
                                                                    ?.error,
                                                                onRetry: () => _model
                                                                    .listViewPagingController5
                                                                    ?.refresh(),
                                                              ),
                                                              noItemsFoundIndicatorBuilder:
                                                                  (_) =>
                                                                      const SizedBox(
                                                                height: AppStyles
                                                                    .gameCardHeight,
                                                                child:
                                                                    ListEmptyComponentWidget(
                                                                  title:
                                                                      'Liste vide',
                                                                  description:
                                                                      'Il n\'y a pas de jeux pour le moment',
                                                                ),
                                                              ),
                                                              itemBuilder: (context,
                                                                  _,
                                                                  listViewIndex) {
                                                                final listViewGamesRecord = _model
                                                                        .listViewPagingController5!
                                                                        .itemList![
                                                                    listViewIndex];
                                                                if (!_isGameVisibleForPlayer(
                                                                    listViewGamesRecord)) {
                                                                  return const SizedBox
                                                                      .shrink();
                                                                }
                                                                return FutureBuilder<
                                                                    EnseignesRecord>(
                                                                  future: _getCachedEnseigneFuture(
                                                                      listViewGamesRecord
                                                                          .enseigneId!),
                                                                  builder: (context,
                                                                      enseigneSnapshot) {
                                                                    final enseigne =
                                                                        enseigneSnapshot
                                                                            .data;
                                                                    return _buildHomeGameCard(
                                                                      game:
                                                                          listViewGamesRecord,
                                                                      enseigne:
                                                                          enseigne,
                                                                      prizeText: listViewGamesRecord.prizeValue ==
                                                                              0
                                                                          ? 'Gains instantan\u00E9s'
                                                                          : _formatEuroAmount(
                                                                              listViewGamesRecord.prizeValue),
                                                                      endDateText: listViewGamesRecord.endDate !=
                                                                              null
                                                                          ? "Jusqu'au : ${dateTimeFormat('d/M/y', listViewGamesRecord.endDate, locale: FFLocalizations.of(context).languageCode)}"
                                                                          : "Jusqu'au : -",
                                                                      onTap:
                                                                          () async {
                                                                        await _openGameDetails(
                                                                            listViewGamesRecord);
                                                                      },
                                                                    );
                                                                  },
                                                                );
                                                              },
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Container(
                                                    width: double.infinity,
                                                    decoration:
                                                        const BoxDecoration(),
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.max,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        Padding(
                                                          padding:
                                                              const EdgeInsetsDirectional
                                                                  .fromSTEB(
                                                                  _homeSectionTitleLeftInset,
                                                                  0.0,
                                                                  0.0,
                                                                  16.0),
                                                          child: Text(
                                                            'NOUVEAUT\u00C9S',
                                                            style: FlutterFlowTheme
                                                                    .of(context)
                                                                .titleLarge
                                                                .override(
                                                                  font: GoogleFonts
                                                                      .interTight(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontStyle,
                                                                  ),
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontStyle,
                                                                ),
                                                          ),
                                                        ),
                                                        Container(
                                                          width:
                                                              double.infinity,
                                                          height: AppStyles
                                                              .gameCardHeight,
                                                          decoration:
                                                              const BoxDecoration(
                                                            color: Colors
                                                                .transparent,
                                                          ),
                                                          child: Builder(
                                                            builder: (context) {
                                                              _logHomeQueryBranch(
                                                                sectionName:
                                                                    'new',
                                                                branchName:
                                                                    'minor_filtered',
                                                                clauses: const [
                                                                  'hasWinner == false',
                                                                  'prohibited_for_minors == false',
                                                                  'orderBy created_time desc',
                                                                ],
                                                              );
                                                              final newController =
                                                                  _model
                                                                      .setListViewController6(
                                                                GamesRecord
                                                                    .collection
                                                                    .where(
                                                                      'hasWinner',
                                                                      isEqualTo:
                                                                          false,
                                                                    )
                                                                    .where(
                                                                      'prohibited_for_minors',
                                                                      isEqualTo:
                                                                          false,
                                                                    )
                                                                    .orderBy(
                                                                        'created_time',
                                                                        descending:
                                                                            true),
                                                              );
                                                              final visibleGames =
                                                                  (newController
                                                                              .itemList ??
                                                                          const <GamesRecord>[])
                                                                      .where(
                                                                          _isGameVisibleForPlayer)
                                                                      .toList();
                                                              _logHomeGamesSection(
                                                                'nouveautés',
                                                                newController
                                                                        .itemList ??
                                                                    const <GamesRecord>[],
                                                                visibleGames,
                                                              );

                                                              if (newController
                                                                      .itemList !=
                                                                  null) {
                                                                return _buildHomeGamesCarousel(
                                                                  context,
                                                                  visibleGames,
                                                                  sectionName:
                                                                      'Nouveautés',
                                                                  emptyTitle:
                                                                      'Aucune nouveaut\u00E9',
                                                                  emptyDescription:
                                                                      'Votre liste est actuellement vide',
                                                                );
                                                              }

                                                              return const SizedBox
                                                                  .shrink();
                                                            },
                                                          ),
                                                        ),
                                                        if (_model
                                                                .listViewPagingController6
                                                                ?.itemList ==
                                                            null)
                                                          Container(
                                                            width:
                                                                double.infinity,
                                                            height: AppStyles
                                                                    .gameCardHeight +
                                                                8.0,
                                                            decoration:
                                                                const BoxDecoration(
                                                              color: Colors
                                                                  .transparent,
                                                            ),
                                                            child: PagedListView<
                                                                DocumentSnapshot<
                                                                    Object?>?,
                                                                GamesRecord>.separated(
                                                              pagingController:
                                                                  _model
                                                                      .setListViewController6(
                                                                GamesRecord
                                                                    .collection
                                                                    .where(
                                                                      'hasWinner',
                                                                      isEqualTo:
                                                                          false,
                                                                    )
                                                                    .where(
                                                                      'prohibited_for_minors',
                                                                      isEqualTo:
                                                                          false,
                                                                    )
                                                                    .orderBy(
                                                                        'created_time',
                                                                        descending:
                                                                            true),
                                                              ),
                                                              padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                              primary: false,
                                                              reverse: false,
                                                              scrollDirection:
                                                                  Axis.horizontal,
                                                              separatorBuilder:
                                                                  (context,
                                                                      separatorIndex) {
                                                                final items = _model
                                                                        .listViewPagingController6
                                                                        ?.itemList ??
                                                                    const <GamesRecord>[];
                                                                final currentItemVisible = separatorIndex <
                                                                        items
                                                                            .length &&
                                                                    _isGameVisibleForPlayer(
                                                                        items[
                                                                            separatorIndex]);
                                                                final nextItemVisible = separatorIndex +
                                                                            1 <
                                                                        items
                                                                            .length &&
                                                                    _isGameVisibleForPlayer(items[
                                                                        separatorIndex +
                                                                            1]);

                                                                if (!currentItemVisible ||
                                                                    !nextItemVisible) {
                                                                  return const SizedBox
                                                                      .shrink();
                                                                }

                                                                return const SizedBox(
                                                                    width:
                                                                        _homeHorizontalCardGap);
                                                              },
                                                              builderDelegate:
                                                                  PagedChildBuilderDelegate<
                                                                      GamesRecord>(
                                                                // Customize what your widget looks like when it's loading the first page.
                                                                firstPageProgressIndicatorBuilder:
                                                                    (_) =>
                                                                        _buildHomeCarouselLoading(),
                                                                // Customize what your widget looks like when it's loading another page.
                                                                newPageProgressIndicatorBuilder:
                                                                    (_) =>
                                                                        _buildHomeCarouselLoading(
                                                                  message:
                                                                      'Chargement...',
                                                                ),
                                                                firstPageErrorIndicatorBuilder:
                                                                    (_) =>
                                                                        _buildHomeCarouselError(
                                                                  error: _model
                                                                      .listViewPagingController6
                                                                      ?.error,
                                                                  onRetry: () => _model
                                                                      .listViewPagingController6
                                                                      ?.refresh(),
                                                                ),
                                                                newPageErrorIndicatorBuilder:
                                                                    (_) =>
                                                                        _buildHomeCarouselError(
                                                                  error: _model
                                                                      .listViewPagingController6
                                                                      ?.error,
                                                                  onRetry: () => _model
                                                                      .listViewPagingController6
                                                                      ?.refresh(),
                                                                ),
                                                                noItemsFoundIndicatorBuilder:
                                                                    (_) =>
                                                                        const ListEmptyComponentWidget(
                                                                  title:
                                                                      'Aucune nouveaut\u00E9',
                                                                  description:
                                                                      'Votre liste est actuellement vide',
                                                                ),
                                                                itemBuilder:
                                                                    (context, _,
                                                                        listViewIndex) {
                                                                  final listViewGamesRecord = _model
                                                                          .listViewPagingController6!
                                                                          .itemList![
                                                                      listViewIndex];
                                                                  if (!_isGameVisibleForPlayer(
                                                                      listViewGamesRecord)) {
                                                                    return const SizedBox
                                                                        .shrink();
                                                                  }
                                                                  return FutureBuilder<
                                                                      EnseignesRecord>(
                                                                    future: _getCachedEnseigneFuture(
                                                                        listViewGamesRecord
                                                                            .enseigneId!),
                                                                    builder:
                                                                        (context,
                                                                            enseigneSnapshot) {
                                                                      final enseigne =
                                                                          enseigneSnapshot
                                                                              .data;
                                                                      return _buildHomeGameCard(
                                                                        game:
                                                                            listViewGamesRecord,
                                                                        enseigne:
                                                                            enseigne,
                                                                        prizeText: listViewGamesRecord.prizeValue ==
                                                                                0
                                                                            ? 'Gains instantan\u00E9s'
                                                                            : _formatEuroAmount(listViewGamesRecord.prizeValue),
                                                                        endDateText: listViewGamesRecord.endDate !=
                                                                                null
                                                                            ? "Jusqu'au : ${dateTimeFormat('d/M/y', listViewGamesRecord.endDate, locale: FFLocalizations.of(context).languageCode)}"
                                                                            : "Jusqu'au : -",
                                                                        onTap:
                                                                            () async {
                                                                          await _openGameDetails(
                                                                              listViewGamesRecord);
                                                                        },
                                                                      );
                                                                    },
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  Container(
                                                    decoration:
                                                        const BoxDecoration(),
                                                    child: Builder(
                                                      builder: (context) {
                                                        _logHomeQueryBranch(
                                                          sectionName:
                                                              'endingSoon',
                                                          branchName:
                                                              'minor_filtered',
                                                          clauses: [
                                                            'hasWinner == false',
                                                            'prohibited_for_minors == false',
                                                            'end_date > ${getCurrentTimestamp.toIso8601String()}',
                                                            'orderBy end_date asc',
                                                          ],
                                                        );
                                                        final endingController =
                                                            _model
                                                                .setListViewController7(
                                                          GamesRecord.collection
                                                              .where(
                                                                'hasWinner',
                                                                isEqualTo:
                                                                    false,
                                                              )
                                                              .where(
                                                                'prohibited_for_minors',
                                                                isEqualTo:
                                                                    false,
                                                              )
                                                              .where(
                                                                'end_date',
                                                                isGreaterThan:
                                                                    getCurrentTimestamp,
                                                              )
                                                              .orderBy(
                                                                  'end_date'),
                                                        );
                                                        final visibleGames =
                                                            (endingController
                                                                        .itemList ??
                                                                    const <GamesRecord>[])
                                                                .where(
                                                                    _isGameVisibleForPlayer)
                                                                .toList();

                                                        if (endingController
                                                                .itemList !=
                                                            null) {
                                                          return Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .max,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .stretch,
                                                            children: [
                                                              Text(
                                                                'BIENT\u00D4T FINIS',
                                                                style: FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleLarge
                                                                    .override(
                                                                      font: GoogleFonts
                                                                          .interTight(
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .titleLarge
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .titleLarge
                                                                            .fontStyle,
                                                                      ),
                                                                      letterSpacing:
                                                                          0.0,
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontStyle,
                                                                    ),
                                                              ),
                                                              Container(
                                                                width: double
                                                                    .infinity,
                                                                height: AppStyles
                                                                    .gameCardHeight,
                                                                decoration:
                                                                    const BoxDecoration(
                                                                  color: Colors
                                                                      .transparent,
                                                                ),
                                                                child:
                                                                    _buildHomeGamesCarousel(
                                                                  context,
                                                                  visibleGames,
                                                                  sectionName:
                                                                      'Bientôt finis',
                                                                  emptyTitle:
                                                                      'Aucun jeux',
                                                                  emptyDescription:
                                                                      ' ',
                                                                ),
                                                              ),
                                                            ].divide(
                                                                const SizedBox(
                                                                    height:
                                                                        5.0)),
                                                          );
                                                        }

                                                        return const SizedBox
                                                            .shrink();
                                                      },
                                                    ),
                                                  ),
                                                  if (_model
                                                          .listViewPagingController7
                                                          ?.itemList ==
                                                      null)
                                                    Container(
                                                      decoration:
                                                          const BoxDecoration(),
                                                      child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.max,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          Padding(
                                                            padding:
                                                                const EdgeInsetsDirectional
                                                                    .fromSTEB(
                                                                    0.0,
                                                                    0.0,
                                                                    0.0,
                                                                    16.0),
                                                            child: Text(
                                                              'BIENT\u00D4T FINIS',
                                                              style: FlutterFlowTheme
                                                                      .of(context)
                                                                  .titleLarge
                                                                  .override(
                                                                    font: GoogleFonts
                                                                        .interTight(
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontStyle,
                                                                    ),
                                                                    letterSpacing:
                                                                        0.0,
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontStyle,
                                                                  ),
                                                            ),
                                                          ),
                                                          Container(
                                                            width:
                                                                double.infinity,
                                                            height: AppStyles
                                                                    .gameCardHeight +
                                                                8.0,
                                                            decoration:
                                                                const BoxDecoration(
                                                              color: Colors
                                                                  .transparent,
                                                            ),
                                                            child: PagedListView<
                                                                DocumentSnapshot<
                                                                    Object?>?,
                                                                GamesRecord>.separated(
                                                              pagingController:
                                                                  _model
                                                                      .setListViewController7(
                                                                GamesRecord
                                                                    .collection
                                                                    .where(
                                                                      'hasWinner',
                                                                      isEqualTo:
                                                                          false,
                                                                    )
                                                                    .where(
                                                                      'prohibited_for_minors',
                                                                      isEqualTo:
                                                                          false,
                                                                    )
                                                                    .where(
                                                                      'end_date',
                                                                      isGreaterThan:
                                                                          getCurrentTimestamp,
                                                                    )
                                                                    .orderBy(
                                                                        'end_date'),
                                                              ),
                                                              padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                              primary: false,
                                                              reverse: false,
                                                              scrollDirection:
                                                                  Axis.horizontal,
                                                              separatorBuilder:
                                                                  (context,
                                                                      separatorIndex) {
                                                                final items = _model
                                                                        .listViewPagingController7
                                                                        ?.itemList ??
                                                                    const <GamesRecord>[];
                                                                final currentItemVisible = separatorIndex <
                                                                        items
                                                                            .length &&
                                                                    _isGameVisibleForPlayer(
                                                                        items[
                                                                            separatorIndex]);
                                                                final nextItemVisible = separatorIndex +
                                                                            1 <
                                                                        items
                                                                            .length &&
                                                                    _isGameVisibleForPlayer(items[
                                                                        separatorIndex +
                                                                            1]);

                                                                if (!currentItemVisible ||
                                                                    !nextItemVisible) {
                                                                  return const SizedBox
                                                                      .shrink();
                                                                }

                                                                return const SizedBox(
                                                                    width:
                                                                        _homeHorizontalCardGap);
                                                              },
                                                              builderDelegate:
                                                                  PagedChildBuilderDelegate<
                                                                      GamesRecord>(
                                                                // Customize what your widget looks like when it's loading the first page.
                                                                firstPageProgressIndicatorBuilder:
                                                                    (_) =>
                                                                        _buildHomeCarouselLoading(),
                                                                // Customize what your widget looks like when it's loading another page.
                                                                newPageProgressIndicatorBuilder:
                                                                    (_) =>
                                                                        _buildHomeCarouselLoading(
                                                                  message:
                                                                      'Chargement...',
                                                                ),
                                                                firstPageErrorIndicatorBuilder:
                                                                    (_) =>
                                                                        _buildHomeCarouselError(
                                                                  error: _model
                                                                      .listViewPagingController7
                                                                      ?.error,
                                                                  onRetry: () => _model
                                                                      .listViewPagingController7
                                                                      ?.refresh(),
                                                                ),
                                                                newPageErrorIndicatorBuilder:
                                                                    (_) =>
                                                                        _buildHomeCarouselError(
                                                                  error: _model
                                                                      .listViewPagingController7
                                                                      ?.error,
                                                                  onRetry: () => _model
                                                                      .listViewPagingController7
                                                                      ?.refresh(),
                                                                ),
                                                                noItemsFoundIndicatorBuilder:
                                                                    (_) =>
                                                                        const ListEmptyComponentWidget(
                                                                  title:
                                                                      'Aucun jeux',
                                                                  description:
                                                                      ' ',
                                                                ),
                                                                itemBuilder:
                                                                    (context, _,
                                                                        listViewIndex) {
                                                                  final listViewGamesRecord = _model
                                                                          .listViewPagingController7!
                                                                          .itemList![
                                                                      listViewIndex];
                                                                  if (!_isGameVisibleForPlayer(
                                                                      listViewGamesRecord)) {
                                                                    return const SizedBox
                                                                        .shrink();
                                                                  }
                                                                  return FutureBuilder<
                                                                      EnseignesRecord>(
                                                                    future: _getCachedEnseigneFuture(
                                                                        listViewGamesRecord
                                                                            .enseigneId!),
                                                                    builder:
                                                                        (context,
                                                                            enseigneSnapshot) {
                                                                      final enseigne =
                                                                          enseigneSnapshot
                                                                              .data;
                                                                      return _buildHomeGameCard(
                                                                        game:
                                                                            listViewGamesRecord,
                                                                        enseigne:
                                                                            enseigne,
                                                                        prizeText: listViewGamesRecord.prizeValue ==
                                                                                0
                                                                            ? 'Gains instantan\u00E9s'
                                                                            : _formatEuroAmount(listViewGamesRecord.prizeValue),
                                                                        endDateText: listViewGamesRecord.endDate !=
                                                                                null
                                                                            ? "Jusqu'au : ${dateTimeFormat('d/M/y', listViewGamesRecord.endDate, locale: FFLocalizations.of(context).languageCode)}"
                                                                            : "Jusqu'au : -",
                                                                        onTap:
                                                                            () async {
                                                                          await _openGameDetails(
                                                                              listViewGamesRecord);
                                                                        },
                                                                      );
                                                                    },
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                ].divide(const SizedBox(
                                                    height: 3.0)),
                                              ),
                                            );
                                          }
                                        },
                                      );
                                    } else {
                                      _logHomeUserContext(
                                        branchName: 'prize_value_filtered',
                                        isMinor: false,
                                      );
                                      _runHomeBranchDiagnostics(
                                        branchName: 'prize_value_filtered',
                                      );
                                      return RefreshIndicator(
                                        key: const Key(
                                            'RefreshIndicator_jug9m9tx'),
                                        onRefresh: _refreshHomeContent,
                                        child: SingleChildScrollView(
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.max,
                                            children: [
                                              _buildActiveAnimationsSection(
                                                context,
                                              ),
                                              Container(
                                                width: double.infinity,
                                                decoration:
                                                    const BoxDecoration(),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    Text(
                                                      'JEUX \u00C0 LA UNE',
                                                      style:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .titleLarge
                                                              .override(
                                                                font: GoogleFonts
                                                                    .interTight(
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontStyle,
                                                                ),
                                                                fontSize: 20.0,
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight: FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleLarge
                                                                    .fontWeight,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleLarge
                                                                    .fontStyle,
                                                              ),
                                                    ),
                                                    Builder(
                                                      builder: (context) {
                                                        _logHomeQueryBranch(
                                                          sectionName:
                                                              'featured',
                                                          branchName:
                                                              'prize_value_filtered',
                                                          clauses: const [
                                                            'hasWinner == false',
                                                            'prize_value > 0',
                                                            'orderBy prize_value desc',
                                                          ],
                                                        );
                                                        final featuredController =
                                                            _model
                                                                .setListViewController8(
                                                          GamesRecord.collection
                                                              .where(
                                                                'hasWinner',
                                                                isEqualTo:
                                                                    false,
                                                              )
                                                              .where(
                                                                'prize_value',
                                                                isGreaterThan:
                                                                    0,
                                                              )
                                                              .orderBy(
                                                                  'prize_value',
                                                                  descending:
                                                                      true),
                                                        );
                                                        final featuredGames =
                                                            (featuredController
                                                                        .itemList ??
                                                                    const <GamesRecord>[])
                                                                .where(
                                                                    _isGameVisibleForPlayer)
                                                                .toList();

                                                        if (featuredController
                                                                .itemList !=
                                                            null) {
                                                          return Container(
                                                            width:
                                                                double.infinity,
                                                            height: AppStyles
                                                                .gameCardHeight,
                                                            decoration:
                                                                const BoxDecoration(),
                                                            child:
                                                                _buildFeaturedGamesCarousel(
                                                              context,
                                                              featuredGames,
                                                              'À la une',
                                                              showReferralGameCard:
                                                                  true,
                                                            ),
                                                          );
                                                        }

                                                        return const SizedBox
                                                            .shrink();
                                                      },
                                                    ),
                                                    if (_model
                                                            .listViewPagingController8
                                                            ?.itemList ==
                                                        null)
                                                      Container(
                                                        width: double.infinity,
                                                        height: AppStyles
                                                                .gameCardHeight +
                                                            8.0,
                                                        decoration:
                                                            const BoxDecoration(),
                                                        child: PagedListView<
                                                            DocumentSnapshot<
                                                                Object?>?,
                                                            GamesRecord>.separated(
                                                          pagingController: _model
                                                              .setListViewController8(
                                                            GamesRecord
                                                                .collection
                                                                .where(
                                                                  'hasWinner',
                                                                  isEqualTo:
                                                                      false,
                                                                )
                                                                .where(
                                                                  'prize_value',
                                                                  isGreaterThan:
                                                                      0,
                                                                )
                                                                .orderBy(
                                                                    'prize_value',
                                                                    descending:
                                                                        true),
                                                          ),
                                                          padding:
                                                              EdgeInsets.zero,
                                                          primary: false,
                                                          reverse: false,
                                                          scrollDirection:
                                                              Axis.horizontal,
                                                          separatorBuilder:
                                                              (context,
                                                                  separatorIndex) {
                                                            final items = _model
                                                                    .listViewPagingController8
                                                                    ?.itemList ??
                                                                const <GamesRecord>[];
                                                            final currentItemVisible =
                                                                separatorIndex <
                                                                        items
                                                                            .length &&
                                                                    _isGameVisibleForPlayer(
                                                                        items[
                                                                            separatorIndex]);
                                                            final nextItemVisible =
                                                                separatorIndex +
                                                                            1 <
                                                                        items
                                                                            .length &&
                                                                    _isGameVisibleForPlayer(items[
                                                                        separatorIndex +
                                                                            1]);

                                                            if (!currentItemVisible ||
                                                                !nextItemVisible) {
                                                              return const SizedBox
                                                                  .shrink();
                                                            }

                                                            return const SizedBox(
                                                              width:
                                                                  _homeHorizontalCardGap,
                                                            );
                                                          },
                                                          builderDelegate:
                                                              PagedChildBuilderDelegate<
                                                                  GamesRecord>(
                                                            // Customize what your widget looks like when it's loading the first page.
                                                            firstPageProgressIndicatorBuilder:
                                                                (_) =>
                                                                    _buildHomeCarouselLoading(),
                                                            // Customize what your widget looks like when it's loading another page.
                                                            newPageProgressIndicatorBuilder:
                                                                (_) =>
                                                                    _buildHomeCarouselLoading(
                                                              message:
                                                                  'Chargement...',
                                                            ),
                                                            firstPageErrorIndicatorBuilder:
                                                                (_) =>
                                                                    _buildHomeCarouselError(
                                                              error: _model
                                                                  .listViewPagingController8
                                                                  ?.error,
                                                              onRetry: () => _model
                                                                  .listViewPagingController8
                                                                  ?.refresh(),
                                                            ),
                                                            newPageErrorIndicatorBuilder:
                                                                (_) =>
                                                                    _buildHomeCarouselError(
                                                              error: _model
                                                                  .listViewPagingController8
                                                                  ?.error,
                                                              onRetry: () => _model
                                                                  .listViewPagingController8
                                                                  ?.refresh(),
                                                            ),
                                                            noItemsFoundIndicatorBuilder:
                                                                (_) =>
                                                                    const SizedBox(
                                                              height: AppStyles
                                                                  .gameCardHeight,
                                                              child:
                                                                  ListEmptyComponentWidget(
                                                                title:
                                                                    'Liste vide',
                                                                description:
                                                                    'Il n\'y a pas de jeux pour le moment',
                                                              ),
                                                            ),
                                                            itemBuilder: (context,
                                                                _,
                                                                listViewIndex) {
                                                              final listViewGamesRecord = _model
                                                                      .listViewPagingController8!
                                                                      .itemList![
                                                                  listViewIndex];
                                                              if (!_isGameVisibleForPlayer(
                                                                  listViewGamesRecord)) {
                                                                return const SizedBox
                                                                    .shrink();
                                                              }
                                                              return FutureBuilder<
                                                                  EnseignesRecord>(
                                                                future: _getCachedEnseigneFuture(
                                                                    listViewGamesRecord
                                                                        .enseigneId!),
                                                                builder: (context,
                                                                    enseigneSnapshot) {
                                                                  final enseigne =
                                                                      enseigneSnapshot
                                                                          .data;
                                                                  return _buildHomeGameCard(
                                                                    game:
                                                                        listViewGamesRecord,
                                                                    enseigne:
                                                                        enseigne,
                                                                    prizeText: listViewGamesRecord.prizeValue ==
                                                                            0
                                                                        ? 'Gains instantan\u00E9s'
                                                                        : _formatEuroAmount(
                                                                            listViewGamesRecord.prizeValue),
                                                                    endDateText: listViewGamesRecord.endDate !=
                                                                            null
                                                                        ? 'Jusqu\'au : ${dateTimeFormat('d/M/y', listViewGamesRecord.endDate, locale: FFLocalizations.of(context).languageCode)}'
                                                                        : 'Jusqu\'au : -',
                                                                    onTap:
                                                                        () async {
                                                                      await _openGameDetails(
                                                                          listViewGamesRecord);
                                                                    },
                                                                  );
                                                                },
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                                  ].divide(const SizedBox(
                                                      height: 5.0)),
                                                ),
                                              ),
                                              Container(
                                                width: double.infinity,
                                                decoration:
                                                    const BoxDecoration(),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    Padding(
                                                      padding:
                                                          const EdgeInsetsDirectional
                                                              .only(
                                                        start:
                                                            _homeSectionTitleLeftInset,
                                                      ),
                                                      child: Text(
                                                        'NOUVEAUT\u00C9S',
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .titleLarge
                                                                .override(
                                                                  font: GoogleFonts
                                                                      .interTight(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontStyle,
                                                                  ),
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontStyle,
                                                                ),
                                                      ),
                                                    ),
                                                    Container(
                                                      width: double.infinity,
                                                      height: AppStyles
                                                              .gameCardHeight +
                                                          8.0,
                                                      decoration:
                                                          const BoxDecoration(
                                                        color:
                                                            Colors.transparent,
                                                      ),
                                                      child: Builder(
                                                        builder: (context) {
                                                          final newController =
                                                              _model
                                                                  .setListViewController9(
                                                            GamesRecord
                                                                .collection
                                                                .where(
                                                                  'hasWinner',
                                                                  isEqualTo:
                                                                      false,
                                                                )
                                                                .orderBy(
                                                                    'created_time',
                                                                    descending:
                                                                        true),
                                                          );
                                                          final visibleGames =
                                                              (newController
                                                                          .itemList ??
                                                                      const <GamesRecord>[])
                                                                  .where(
                                                                      _isGameVisibleForPlayer)
                                                                  .toList();
                                                          _logHomeGamesSection(
                                                            'nouveautés',
                                                            newController
                                                                    .itemList ??
                                                                const <GamesRecord>[],
                                                            visibleGames,
                                                          );

                                                          if (newController
                                                                  .itemList !=
                                                              null) {
                                                            return _buildHomeGamesCarousel(
                                                              context,
                                                              visibleGames,
                                                              sectionName:
                                                                  'Nouveautés',
                                                              emptyTitle:
                                                                  'Aucune nouveaut\u00E9',
                                                              emptyDescription:
                                                                  'Votre liste est actuellement vide',
                                                            );
                                                          }

                                                          return const SizedBox
                                                              .shrink();
                                                        },
                                                      ),
                                                    ),
                                                    if (_model
                                                            .listViewPagingController9
                                                            ?.itemList ==
                                                        null)
                                                      Container(
                                                        width: double.infinity,
                                                        height: AppStyles
                                                            .gameCardHeight,
                                                        decoration:
                                                            const BoxDecoration(
                                                          color: Colors
                                                              .transparent,
                                                        ),
                                                        child: PagedListView<
                                                            DocumentSnapshot<
                                                                Object?>?,
                                                            GamesRecord>.separated(
                                                          pagingController: _model
                                                              .setListViewController9(
                                                            GamesRecord
                                                                .collection
                                                                .where(
                                                                  'hasWinner',
                                                                  isEqualTo:
                                                                      false,
                                                                )
                                                                .orderBy(
                                                                    'created_time',
                                                                    descending:
                                                                        true),
                                                          ),
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  right: 20.0),
                                                          primary: false,
                                                          reverse: false,
                                                          scrollDirection:
                                                              Axis.horizontal,
                                                          separatorBuilder:
                                                              (context,
                                                                  separatorIndex) {
                                                            final items = _model
                                                                    .listViewPagingController9
                                                                    ?.itemList ??
                                                                const <GamesRecord>[];
                                                            final currentItemVisible =
                                                                separatorIndex <
                                                                        items
                                                                            .length &&
                                                                    _isGameVisibleForPlayer(
                                                                        items[
                                                                            separatorIndex]);
                                                            final nextItemVisible =
                                                                separatorIndex +
                                                                            1 <
                                                                        items
                                                                            .length &&
                                                                    _isGameVisibleForPlayer(items[
                                                                        separatorIndex +
                                                                            1]);

                                                            if (!currentItemVisible ||
                                                                !nextItemVisible) {
                                                              return const SizedBox
                                                                  .shrink();
                                                            }

                                                            return const SizedBox(
                                                              width:
                                                                  _homeHorizontalCardGap,
                                                            );
                                                          },
                                                          builderDelegate:
                                                              PagedChildBuilderDelegate<
                                                                  GamesRecord>(
                                                            // Customize what your widget looks like when it's loading the first page.
                                                            firstPageProgressIndicatorBuilder:
                                                                (_) =>
                                                                    _buildHomeCarouselLoading(),
                                                            // Customize what your widget looks like when it's loading another page.
                                                            newPageProgressIndicatorBuilder:
                                                                (_) =>
                                                                    _buildHomeCarouselLoading(
                                                              message:
                                                                  'Chargement...',
                                                            ),
                                                            firstPageErrorIndicatorBuilder:
                                                                (_) =>
                                                                    _buildHomeCarouselError(
                                                              error: _model
                                                                  .listViewPagingController9
                                                                  ?.error,
                                                              onRetry: () => _model
                                                                  .listViewPagingController9
                                                                  ?.refresh(),
                                                            ),
                                                            newPageErrorIndicatorBuilder:
                                                                (_) =>
                                                                    _buildHomeCarouselError(
                                                              error: _model
                                                                  .listViewPagingController9
                                                                  ?.error,
                                                              onRetry: () => _model
                                                                  .listViewPagingController9
                                                                  ?.refresh(),
                                                            ),
                                                            noItemsFoundIndicatorBuilder:
                                                                (_) =>
                                                                    const ListEmptyComponentWidget(
                                                              title:
                                                                  'Aucune nouveaut\u00E9',
                                                              description:
                                                                  'Votre liste est actuellement vide',
                                                            ),
                                                            itemBuilder: (context,
                                                                _,
                                                                listViewIndex) {
                                                              final listViewGamesRecord = _model
                                                                      .listViewPagingController9!
                                                                      .itemList![
                                                                  listViewIndex];
                                                              if (!_isGameVisibleForPlayer(
                                                                  listViewGamesRecord)) {
                                                                return const SizedBox
                                                                    .shrink();
                                                              }
                                                              return FutureBuilder<
                                                                  EnseignesRecord>(
                                                                future: _getCachedEnseigneFuture(
                                                                    listViewGamesRecord
                                                                        .enseigneId!),
                                                                builder: (context,
                                                                    enseigneSnapshot) {
                                                                  final enseigne =
                                                                      enseigneSnapshot
                                                                          .data;
                                                                  return _buildHomeGameCard(
                                                                    game:
                                                                        listViewGamesRecord,
                                                                    enseigne:
                                                                        enseigne,
                                                                    prizeText: listViewGamesRecord.prizeValue ==
                                                                            0
                                                                        ? 'Gains instantan\u00E9s'
                                                                        : _formatEuroAmount(
                                                                            listViewGamesRecord.prizeValue),
                                                                    endDateText: listViewGamesRecord.endDate !=
                                                                            null
                                                                        ? 'Jusqu\'au : ${dateTimeFormat('d/M/y', listViewGamesRecord.endDate, locale: FFLocalizations.of(context).languageCode)}'
                                                                        : 'Jusqu\'au : -',
                                                                    onTap:
                                                                        () async {
                                                                      await _openGameDetails(
                                                                          listViewGamesRecord);
                                                                    },
                                                                  );
                                                                },
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                                  ].divide(const SizedBox(
                                                      height: 5.0)),
                                                ),
                                              ),
                                              Container(
                                                decoration:
                                                    const BoxDecoration(),
                                                child: Builder(
                                                  builder: (context) {
                                                    final endingController = _model
                                                        .setListViewController10(
                                                      GamesRecord.collection
                                                          .where(
                                                            'hasWinner',
                                                            isEqualTo: false,
                                                          )
                                                          .orderBy('end_date'),
                                                    );
                                                    final visibleGames =
                                                        (endingController
                                                                    .itemList ??
                                                                const <GamesRecord>[])
                                                            .where(
                                                                _isGameVisibleForPlayer)
                                                            .toList();
                                                    _logHomeGamesSection(
                                                      'bientôt finis',
                                                      endingController
                                                              .itemList ??
                                                          const <GamesRecord>[],
                                                      visibleGames,
                                                    );

                                                    if (endingController
                                                            .itemList !=
                                                        null) {
                                                      return Column(
                                                        mainAxisSize:
                                                            MainAxisSize.max,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          Text(
                                                            'BIENT\u00D4T FINIS',
                                                            style: FlutterFlowTheme
                                                                    .of(context)
                                                                .titleLarge
                                                                .override(
                                                                  font: GoogleFonts
                                                                      .interTight(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontStyle,
                                                                  ),
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontStyle,
                                                                ),
                                                          ),
                                                          Container(
                                                            width:
                                                                double.infinity,
                                                            height: AppStyles
                                                                .gameCardHeight,
                                                            decoration:
                                                                const BoxDecoration(
                                                              color: Colors
                                                                  .transparent,
                                                            ),
                                                            child:
                                                                _buildHomeGamesCarousel(
                                                              context,
                                                              visibleGames,
                                                              sectionName:
                                                                  'Bientôt finis',
                                                              emptyTitle:
                                                                  'Aucun jeux',
                                                              emptyDescription:
                                                                  ' ',
                                                            ),
                                                          ),
                                                        ].divide(const SizedBox(
                                                            height: 5.0)),
                                                      );
                                                    }

                                                    return const SizedBox
                                                        .shrink();
                                                  },
                                                ),
                                              ),
                                              if (_model
                                                      .listViewPagingController10
                                                      ?.itemList ==
                                                  null)
                                                Container(
                                                  decoration:
                                                      const BoxDecoration(),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      Text(
                                                        'BIENT\u00D4T FINIS',
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .titleLarge
                                                                .override(
                                                                  font: GoogleFonts
                                                                      .interTight(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontStyle,
                                                                  ),
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleLarge
                                                                      .fontStyle,
                                                                ),
                                                      ),
                                                      Container(
                                                        width: double.infinity,
                                                        height: AppStyles
                                                                .gameCardHeight +
                                                            8.0,
                                                        decoration:
                                                            const BoxDecoration(
                                                          color: Colors
                                                              .transparent,
                                                        ),
                                                        child: PagedListView<
                                                            DocumentSnapshot<
                                                                Object?>?,
                                                            GamesRecord>.separated(
                                                          pagingController: _model
                                                              .setListViewController10(
                                                            GamesRecord
                                                                .collection
                                                                .where(
                                                                  'hasWinner',
                                                                  isEqualTo:
                                                                      false,
                                                                )
                                                                .orderBy(
                                                                    'end_date'),
                                                          ),
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  right: 20.0),
                                                          primary: false,
                                                          reverse: false,
                                                          scrollDirection:
                                                              Axis.horizontal,
                                                          separatorBuilder:
                                                              (context,
                                                                  separatorIndex) {
                                                            final items = _model
                                                                    .listViewPagingController10
                                                                    ?.itemList ??
                                                                const <GamesRecord>[];
                                                            final currentItemVisible =
                                                                separatorIndex <
                                                                        items
                                                                            .length &&
                                                                    _isGameVisibleForPlayer(
                                                                        items[
                                                                            separatorIndex]);
                                                            final nextItemVisible =
                                                                separatorIndex +
                                                                            1 <
                                                                        items
                                                                            .length &&
                                                                    _isGameVisibleForPlayer(items[
                                                                        separatorIndex +
                                                                            1]);

                                                            if (!currentItemVisible ||
                                                                !nextItemVisible) {
                                                              return const SizedBox
                                                                  .shrink();
                                                            }

                                                            return const SizedBox(
                                                              width:
                                                                  _homeHorizontalCardGap,
                                                            );
                                                          },
                                                          builderDelegate:
                                                              PagedChildBuilderDelegate<
                                                                  GamesRecord>(
                                                            // Customize what your widget looks like when it's loading the first page.
                                                            firstPageProgressIndicatorBuilder:
                                                                (_) =>
                                                                    _buildHomeCarouselLoading(),
                                                            // Customize what your widget looks like when it's loading another page.
                                                            newPageProgressIndicatorBuilder:
                                                                (_) =>
                                                                    _buildHomeCarouselLoading(
                                                              message:
                                                                  'Chargement...',
                                                            ),
                                                            firstPageErrorIndicatorBuilder:
                                                                (_) =>
                                                                    _buildHomeCarouselError(
                                                              error: _model
                                                                  .listViewPagingController10
                                                                  ?.error,
                                                              onRetry: () => _model
                                                                  .listViewPagingController10
                                                                  ?.refresh(),
                                                            ),
                                                            newPageErrorIndicatorBuilder:
                                                                (_) =>
                                                                    _buildHomeCarouselError(
                                                              error: _model
                                                                  .listViewPagingController10
                                                                  ?.error,
                                                              onRetry: () => _model
                                                                  .listViewPagingController10
                                                                  ?.refresh(),
                                                            ),
                                                            noItemsFoundIndicatorBuilder:
                                                                (_) =>
                                                                    const ListEmptyComponentWidget(
                                                              title:
                                                                  'Aucun jeux',
                                                              description: ' ',
                                                            ),
                                                            itemBuilder: (context,
                                                                _,
                                                                listViewIndex) {
                                                              final listViewGamesRecord = _model
                                                                      .listViewPagingController10!
                                                                      .itemList![
                                                                  listViewIndex];
                                                              if (!_isGameVisibleForPlayer(
                                                                  listViewGamesRecord)) {
                                                                return const SizedBox
                                                                    .shrink();
                                                              }
                                                              return FutureBuilder<
                                                                  EnseignesRecord>(
                                                                future: _getCachedEnseigneFuture(
                                                                    listViewGamesRecord
                                                                        .enseigneId!),
                                                                builder: (context,
                                                                    enseigneSnapshot) {
                                                                  final enseigne =
                                                                      enseigneSnapshot
                                                                          .data;
                                                                  return _buildHomeGameCard(
                                                                    game:
                                                                        listViewGamesRecord,
                                                                    enseigne:
                                                                        enseigne,
                                                                    prizeText: listViewGamesRecord.prizeValue ==
                                                                            0
                                                                        ? 'Gains instantan\u00E9s'
                                                                        : _formatEuroAmount(
                                                                            listViewGamesRecord.prizeValue),
                                                                    endDateText: listViewGamesRecord.endDate !=
                                                                            null
                                                                        ? 'Jusqu\'au : ${dateTimeFormat('d/M/y', listViewGamesRecord.endDate, locale: FFLocalizations.of(context).languageCode)}'
                                                                        : 'Jusqu\'au : -',
                                                                    onTap:
                                                                        () async {
                                                                      await _openGameDetails(
                                                                          listViewGamesRecord);
                                                                    },
                                                                  );
                                                                },
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                                    ].divide(const SizedBox(
                                                        height: 5.0)),
                                                  ),
                                                ),
                                            ].divide(
                                                const SizedBox(height: 3.0)),
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                        ].divide(const SizedBox(height: 20.0)),
                      ),
                    ),
                  ),
                  Align(
                    alignment: const AlignmentDirectional(0.0, 1.0),
                    child: wrapWithModel(
                      model: _model.customNavBarJoueurModel,
                      updateCallback: () => safeSetState(() {}),
                      child: const CustomNavBarJoueurWidget(
                        indexActive: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
