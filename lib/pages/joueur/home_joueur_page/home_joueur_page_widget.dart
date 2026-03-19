import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/components/app_bar_joueur_widget.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/components/list_empty_component_widget.dart';
import '/components/share_promo_banner_widget.dart';
import '/flutter_flow/app_styles.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/models/share_promo_models.dart';
import '/services/referral/referral_service.dart';
import '/widgets/recent_winners_ticker.dart';
import '/widgets/home/home_async_game_card_widget.dart';
import '/widgets/home/home_finished_game_card_widget.dart';
import '/widgets/home/home_loading_state_widget.dart';
import '/widgets/home/home_search_result_card_widget.dart';
import '/widgets/home/home_search_results_list_widget.dart';
import '/widgets/proxiplay_loading_logo.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/index.dart';
import '/utils/player_bonus_state.dart';
import '/utils/perf_trace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
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
  late HomeJoueurPageModel _model;
  final _referralService = ReferralService();

  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool _homeDataReady = false;
  bool _isRefreshingOnResume = false;
  late Future<SharePromoStateViewModel?> _sharePromoFuture;
  late Future<List<String>> _recentWinnerMessagesFuture;
  SharePromoStateViewModel? _latestSharePromoState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _model = createModel(context, () => HomeJoueurPageModel());
    PerfTrace.log('HOME_INIT');
    PerfTrace.log('HOME_DATA_LOADING_START');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PerfTrace.log('HOME_FIRST_FRAME');
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) {
          _markHomeDataReady();
        }
      });
    });

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'HomeJoueurPage'});

    _model.textController ??= TextEditingController();
    _model.textFieldFocusNode ??= FocusNode();
    _sharePromoFuture = _loadSharePromoState();
    _recentWinnerMessagesFuture = _loadRecentWinnerMessages();
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
    final now = getCurrentTimestamp;
    final startDate = game.startDate;
    if (startDate != null && now.isBefore(startDate)) {
      return false;
    }
    final endDate = game.endDate;
    if (endDate != null && now.isAfter(endDate)) {
      return false;
    }
    return true;
  }

  bool _hasSecondaryRewards(GamesRecord game) {
    return game.secondaryPrizes.isNotEmpty ||
        game.secondaryPrizeDescription.trim().isNotEmpty;
  }

  bool _shouldShowInFinishedGames(GamesRecord game) {
    final now = getCurrentTimestamp;
    final end = game.endDate;
    if (end == null) {
      return false;
    }

    final endedRecently = now.isAfter(end) &&
        now.isBefore(end.add(const Duration(days: 30)));
    if (!endedRecently) {
      return false;
    }

    if (game.hasWinner || game.hasMainPrizeWinner()) {
      return true;
    }

    if (_hasSecondaryRewards(game)) {
      return true;
    }

    // Keep recently ended games visible for 30 days even without a main winner.
    return true;
  }

  Future<EnseignesRecord?> _loadEnseigneForGame(GamesRecord game) async {
    final enseigneRef = game.enseigneId;
    if (enseigneRef == null) {
      return null;
    }
    try {
      return await EnseignesRecord.getDocumentOnce(enseigneRef);
    } catch (_) {
      return null;
    }
  }

  void _incrementGameViews(GamesRecord game) {
    game.reference
        .update({
          ...mapToFirestore(
            {
              'views': FieldValue.increment(1),
            },
          ),
        })
        .catchError((_) {});
  }

  Future<void> _openGameDetails(GamesRecord game) async {
    final enseigne = await _loadEnseigneForGame(game);
    _incrementGameViews(game);
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
    context.pushNamed(
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
        kTransitionInfoKey: const TransitionInfo(
          hasTransition: true,
          transitionType: PageTransitionType.rightToLeft,
        ),
      },
    );
  }

  Future<SharePromoStateViewModel?> _loadSharePromoState() async {
    if (isGuestOrAnonymous || currentUserUid.isEmpty) {
      _latestSharePromoState = null;
      return null;
    }
    try {
      final state = await _referralService.getSharePromoState();
      _latestSharePromoState = state;
      return state;
    } catch (_) {
      _latestSharePromoState = null;
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
          title: state.title ?? 'Recompense disponible',
          subtitle: state.message ?? 'Votre bonus de parrainage est disponible.',
          ctaLabel: state.ctaText ?? 'Mes lots',
          icon: Icons.card_giftcard_rounded,
          primaryColor: const Color(0xFF2C296A),
          secondaryColor: const Color(0xFF5A56A8),
        );
      case 'friendPending':
        return SharePromoData(
          kind: SharePromoKind.friendPending,
          title: state.title ?? 'Invitation en attente',
          subtitle: state.message ?? 'Un partage est en cours.',
          ctaLabel: state.ctaText ?? 'Relancer',
          icon: Icons.schedule_rounded,
          primaryColor: const Color(0xFF5A4E8E),
          secondaryColor: const Color(0xFF7B6FB3),
        );
      case 'specialCampaign':
        return SharePromoData(
          kind: SharePromoKind.specialCampaign,
          title: state.title ?? 'Inviter un ami',
          subtitle: state.message ??
              'Invite un ami et joue a tous les jeux jusqu a minuit.',
          ctaLabel: state.ctaText ?? 'Inviter un ami',
          icon: Icons.local_fire_department_rounded,
          primaryColor: const Color(0xFFA0134D),
          secondaryColor: const Color(0xFFDD7A54),
        );
      case 'lowRemainingPlaysInvite':
        return SharePromoData(
          kind: SharePromoKind.lowRemainingPlaysInvite,
          title: state.title ?? 'Inviter un ami',
          subtitle: state.message ??
              'Invite un ami et joue a tous les jeux jusqu a minuit.',
          ctaLabel: state.ctaText ?? 'Inviter un ami',
          icon: Icons.volunteer_activism_rounded,
          primaryColor: const Color(0xFF6E3B86),
          secondaryColor: const Color(0xFF9A5FAE),
        );
      case 'defaultInvite':
      default:
        return SharePromoData(
          kind: SharePromoKind.defaultInvite,
          title: state.title ?? 'Inviter un ami',
          subtitle: state.message ??
              'Invite un ami et joue a tous les jeux jusqu a minuit.',
          ctaLabel: state.ctaText ?? 'Inviter un ami',
          icon: Icons.share_rounded,
          primaryColor: const Color(0xFF2B2A66),
          secondaryColor: const Color(0xFF4E5FB1),
        );
    }
  }

  bool _hasActiveReferralBonus() {
    return hasActiveReferralBonus(
      currentUserDocument,
      now: getCurrentTimestamp,
    );
  }

  String _extractWinnerFirstName(UsersRecord? user) {
    final candidates = <String>[
      user?.firstName ?? '',
      user?.displayName ?? '',
      user?.pseudo ?? '',
    ];
    for (final candidate in candidates) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      return trimmed.split(RegExp(r'\s+')).first;
    }
    return '';
  }

  String _buildRecentWinnerMessage(PrizesRecord prize, UsersRecord user) {
    final firstName = _extractWinnerFirstName(user);
    final prizeName = prize.name.trim();
    final enseigneName = prize.enseigneName.trim();
    return '$firstName a gagné $prizeName chez $enseigneName';
  }

  Future<List<String>> _loadRecentWinnerMessages() async {
    try {
      final prizes = await queryPrizesRecordOnce(
        queryBuilder: (query) => query.orderBy('win_date', descending: true),
        limit: 12,
      );

      final recentPrizes = prizes
          .where(
            (prize) =>
                prize.hasWinDate() &&
                prize.hasWinnerId() &&
                prize.name.trim().isNotEmpty &&
                prize.enseigneName.trim().isNotEmpty,
          )
          .take(8)
          .toList();

      if (recentPrizes.isEmpty) {
        return const <String>[];
      }

      final winnerRefs = recentPrizes
          .map((prize) => prize.winnerId)
          .whereType<DocumentReference>()
          .toSet()
          .toList();

      final winnerRecords = await Future.wait(
        winnerRefs.map(UsersRecord.getDocumentOnce),
      );

      final winnersByPath = <String, UsersRecord>{
        for (final winner in winnerRecords) winner.reference.path: winner,
      };

      return recentPrizes
          .map((prize) {
            final winner = prize.winnerId != null
                ? winnersByPath[prize.winnerId!.path]
                : null;
            if (winner == null) {
              return null;
            }
            final firstName = _extractWinnerFirstName(winner);
            if (firstName.isEmpty) {
              return null;
            }
            return _buildRecentWinnerMessage(prize, winner);
          })
          .whereType<String>()
          .toList();
    } catch (_) {
      return const <String>[];
    }
  }

  Widget _buildTopDynamicZone(BuildContext context) {
    return AuthUserStreamWidget(
      builder: (context) {
        final playerAccessState = resolvePlayerAccessState(
          currentUserDocument,
          now: getCurrentTimestamp,
        );
        if (playerAccessState == PlayerAccessState.bonusActive) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 16.0),
            child: SharePromoBanner(
              data: SharePromoData(
                kind: SharePromoKind.specialCampaign,
                title: 'Bonus parrainage actif',
                subtitle: 'Tu peux jouer à tous les jeux jusqu’à minuit.',
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

        if (playerAccessState == PlayerAccessState.noParts) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: SharePromoBanner(
              data: const SharePromoData(
                kind: SharePromoKind.lowRemainingPlaysInvite,
                title: 'Plus de chances disponibles',
                subtitle:
                    'Invite un ami pour récupérer l’accès à tous les jeux jusqu’à minuit.',
                ctaLabel: 'Inviter un ami',
                icon: Icons.volunteer_activism_rounded,
                primaryColor: Color(0xFFF5F6FB),
                secondaryColor: Color(0xFFA0134D),
                titleColor: Color(0xFF2C2F5B),
                subtitleColor: Color(0xFF2C2F5B),
                buttonColor: Color(0xFF2C2F5B),
                buttonTextColor: Colors.white,
                iconBackgroundColor: Color(0xFFF7E6EE),
                iconColor: Color(0xFFA0134D),
              ),
              onTap: () {
                _showSharePromoSheet();
              },
            ),
          );
        }

        if (playerAccessState == PlayerAccessState.lowParts) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: SharePromoBanner(
              data: const SharePromoData(
                kind: SharePromoKind.lowRemainingPlaysInvite,
                title: 'Plus qu’une partie',
                subtitle:
                    'Invite un ami et joue à tous les jeux jusqu’à minuit.',
                ctaLabel: 'Inviter un ami',
                icon: Icons.volunteer_activism_rounded,
                primaryColor: Color(0xFFF5F6FB),
                secondaryColor: Color(0xFFA0134D),
                titleColor: Color(0xFF2C2F5B),
                subtitleColor: Color(0xFF2C2F5B),
                buttonColor: Color(0xFF2C2F5B),
                buttonTextColor: Colors.white,
                iconBackgroundColor: Color(0xFFF7E6EE),
                iconColor: Color(0xFFA0134D),
              ),
              onTap: () {
                _showSharePromoSheet();
              },
            ),
          );
        }

        return FutureBuilder<List<String>>(
          future: _recentWinnerMessagesFuture,
          builder: (context, snapshot) {
            final messages = snapshot.data ?? const <String>[];
            if (messages.isEmpty) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: RecentWinnersTicker(messages: messages),
            );
          },
        );
      },
    );
  }

  Future<Map<String, String>> _buildSharePromoPayload(String channel) async {
    final rewardValue = _latestSharePromoState?.rewardValue ?? 1;
    return _referralService.buildSharePromoPayload(
      channel: channel,
      rewardValue: rewardValue,
    );
  }

  Future<void> _copyShareText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<T> _runWithShareLoader<T>(Future<T> Function() action) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0.0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 22.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 24.0,
                    offset: const Offset(0.0, 10.0),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ProxiplayLoadingLogo(size: 52.0),
                  const SizedBox(height: 16.0),
                  Text(
                    'Ouverture du partage...',
                    textAlign: TextAlign.center,
                    style: FlutterFlowTheme.of(dialogContext)
                        .titleMedium
                        .override(
                          font: GoogleFonts.interTight(
                            fontWeight: FontWeight.w700,
                            fontStyle: FlutterFlowTheme.of(dialogContext)
                                .titleMedium
                                .fontStyle,
                          ),
                          color: const Color(0xFF2C2F5B),
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w700,
                          fontStyle: FlutterFlowTheme.of(dialogContext)
                              .titleMedium
                              .fontStyle,
                        ),
                  ),
                  const SizedBox(height: 6.0),
                  Text(
                    'Préparation de votre invitation ProxiPlay...',
                    textAlign: TextAlign.center,
                    style: FlutterFlowTheme.of(dialogContext).bodyMedium.override(
                          font: GoogleFonts.inter(
                            fontWeight: FontWeight.w500,
                            fontStyle: FlutterFlowTheme.of(dialogContext)
                                .bodyMedium
                                .fontStyle,
                          ),
                          color: const Color(0xFF5A607C),
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w500,
                          fontStyle: FlutterFlowTheme.of(dialogContext)
                              .bodyMedium
                              .fontStyle,
                        ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      return await action();
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _launchSharePromoAction() async {
    await _runWithShareLoader(() async {
      final payload = await _buildSharePromoPayload('native_share');
      final shareText =
          payload['shareText'] ?? _referralService.buildAppShareText();
      final shareLink =
          payload['shareLink'] ?? _referralService.buildReferralShareLink();

      try {
        debugPrint('[SHARE_DEBUG] link=$shareLink');
        debugPrint('[SHARE_DEBUG] text=$shareText');
        final box = context.findRenderObject() as RenderBox?;
        await Share.share(
          shareText,
          subject: 'Invitation ProxiPlay',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        );
      } catch (_) {
        await _copyShareText(shareText);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Le partage natif est indisponible. Le message a été copié dans le presse-papiers.',
            ),
          ),
        );
      }
    });
  }

  Future<void> _showSharePromoSheet() async {
    await showDialog<void>(
      context: context,
      builder: (sheetContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0.0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24.0,
                  offset: const Offset(0.0, 8.0),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20.0, 18.0, 20.0, 20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42.0,
                      height: 4.0,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBDDEA),
                        borderRadius: BorderRadius.circular(999.0),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18.0),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52.0,
                        height: 52.0,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7E6EE),
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                        child: const Icon(
                          Icons.volunteer_activism_rounded,
                          color: Color(0xFFA0134D),
                          size: 24.0,
                        ),
                      ),
                      const SizedBox(width: 14.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Inviter un ami',
                              style: FlutterFlowTheme.of(sheetContext)
                                  .headlineSmall
                                  .override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FontWeight.w700,
                                      fontStyle: FlutterFlowTheme.of(sheetContext)
                                          .headlineSmall
                                          .fontStyle,
                                    ),
                                    color: const Color(0xFF2C2F5B),
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.w700,
                                    fontStyle: FlutterFlowTheme.of(sheetContext)
                                        .headlineSmall
                                        .fontStyle,
                                  ),
                            ),
                            const SizedBox(height: 10.0),
                            Text(
                              'Partage ton lien ProxiPlay pour récupérer l’accès à tous les jeux jusqu’à minuit.',
                              style: FlutterFlowTheme.of(sheetContext)
                                  .bodyMedium
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FontWeight.w500,
                                      fontStyle: FlutterFlowTheme.of(sheetContext)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                    color: const Color(0xFF2C2F5B),
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.w500,
                                    fontStyle: FlutterFlowTheme.of(sheetContext)
                                        .bodyMedium
                                        .fontStyle,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20.0),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2C2F5B),
                        foregroundColor: Colors.white,
                        elevation: 0.0,
                        padding: const EdgeInsets.symmetric(vertical: 14.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.0),
                        ),
                      ),
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _launchSharePromoAction();
                      },
                      child: Text(
                        'Inviter un ami',
                        style: FlutterFlowTheme.of(sheetContext)
                            .titleSmall
                            .override(
                              font: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontStyle: FlutterFlowTheme.of(sheetContext)
                                    .titleSmall
                                    .fontStyle,
                              ),
                              color: Colors.white,
                              letterSpacing: 0.0,
                              fontWeight: FontWeight.w700,
                              fontStyle: FlutterFlowTheme.of(sheetContext)
                                  .titleSmall
                                  .fontStyle,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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

    await queryGamesRecordOnce().then(
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
    ).onError((_, __) => _model.simpleSearchResults = []);

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
            if (_model.searchActive || _model.textController.text.trim().isNotEmpty)
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
      padding: const EdgeInsetsDirectional.fromSTEB(20.0, 30.0, 20.0, 100.0),
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
    _sharePromoFuture = _loadSharePromoState();
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
    safeSetState(() {});
    await Future.delayed(const Duration(milliseconds: 350));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && !_isRefreshingOnResume) {
      _isRefreshingOnResume = true;
      _refreshHomeContent().whenComplete(() {
        _isRefreshingOnResume = false;
      });
    }
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
      return const HomeLoadingState();
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
                background: ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: Image.asset(
                    'assets/images/Background.png',
                    fit: BoxFit.cover,
                    alignment: const Alignment(1.0, -1.0),
                  ),
                ),
                centerTitle: true,
                expandedTitleScale: 1.0,
                titlePadding:
                    const EdgeInsetsDirectional.fromSTEB(20.0, 30.0, 20.0, 0.0),
              ),
            ),
          ),
          body: SafeArea(
            top: true,
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
                          20.0, 30.0, 20.0, 100.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          if (!_model.searchActive)
                            _buildTopDynamicZone(context),
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

                                    return HomeSearchResultsList(
                                      games: search,
                                      itemBuilder: (context, searchItem) =>
                                          HomeSearchResultCard(
                                        game: searchItem,
                                        onTap: () async {
                                          await searchItem.reference.update({
                                            ...mapToFirestore(
                                              {
                                                'views': FieldValue.increment(1),
                                              },
                                            ),
                                          });

                                          final rowEnseignesRecord =
                                              await EnseignesRecord.getDocumentOnce(
                                            searchItem.enseigneId!,
                                          );

                                          if (!context.mounted) {
                                            return;
                                          }

                                          context.pushNamed(
                                            JeuDetailJoueurPageWidget.routeName,
                                            queryParameters: {
                                              'gameDoc': serializeParam(
                                                searchItem,
                                                ParamType.Document,
                                              ),
                                              'enseigneDoc': serializeParam(
                                                rowEnseignesRecord,
                                                ParamType.Document,
                                              ),
                                            }.withoutNulls,
                                            extra: <String, dynamic>{
                                              'gameDoc': searchItem,
                                              'enseigneDoc': rowEnseignesRecord,
                                              kTransitionInfoKey:
                                                  const TransitionInfo(
                                                hasTransition: true,
                                                transitionType:
                                                    PageTransitionType.fade,
                                              ),
                                            },
                                          );
                                        },
                                      ),
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
                                          if (isGuestOrAnonymous ||
                                              ((currentUserDocument?.birthday !=
                                                      null) &&
                                                  functions.isAdult(
                                                      currentUserDocument!
                                                          .birthday!))) {
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
                                                          Container(
                                                            width:
                                                                double.infinity,
                                                            height: AppStyles.gameCardHeight + 8.0,
                                                            decoration:
                                                                const BoxDecoration(),
                                                            child: PagedListView<
                                                                DocumentSnapshot<
                                                                    Object?>?,
                                                                GamesRecord>.separated(
                                                              pagingController:
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
                                                              ),
                                                              padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                              primary: false,
                                                              reverse: false,
                                                              scrollDirection:
                                                                  Axis.horizontal,
                                                              separatorBuilder: (_,
                                                                      __) =>
                                                                  const SizedBox(
                                                                      width:
                                                                          10.0),
                                                              builderDelegate:
                                                                  PagedChildBuilderDelegate<
                                                                      GamesRecord>(
                                                                // Customize what your widget looks like when it's loading the first page.
                                                                firstPageProgressIndicatorBuilder:
                                                                    (_) => const SizedBox
                                                                        .shrink(),
                                                                // Customize what your widget looks like when it's loading another page.
                                                                newPageProgressIndicatorBuilder:
                                                                    (_) => const SizedBox
                                                                        .shrink(),
                                                                noItemsFoundIndicatorBuilder:
                                                                    (_) =>
                                                                        const SizedBox(
                                                                  height: AppStyles.gameCardHeight,
                                                                  child:
                                                                      ListEmptyComponentWidget(
                                                                    title:
                                                                        'Liste vide',
                                                                    description:
                                                                        'Il n\'y a pas de jeux pour le moment',
                                                                  ),
                                                                ),
                                                                itemBuilder:
                                                                    (context, _,
                                                                        listViewIndex) {
                                                                  final listViewGamesRecord = _model
                                                                          .listViewPagingController2!
                                                                          .itemList![
                                                                      listViewIndex];
                                                                  if (!_isGameVisibleForPlayer(listViewGamesRecord)) {
                                                                    return const SizedBox.shrink();
                                                                  }
                                                                  return HomeAsyncGameCard(
                                                                    game:
                                                                        listViewGamesRecord,
                                                                    onTap:
                                                                        () async {
                                                                      await _openGameDetails(
                                                                        listViewGamesRecord,
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
                                                          Container(
                                                            width:
                                                                double.infinity,
                                                            height: AppStyles.gameCardHeight + 8.0,
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
                                                                      .setListViewController4(
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
                                                                  EdgeInsets
                                                                      .zero,
                                                              primary: false,
                                                              reverse: false,
                                                              scrollDirection:
                                                                  Axis.horizontal,
                                                              separatorBuilder: (_,
                                                                      __) =>
                                                                  const SizedBox(
                                                                      width:
                                                                          10.0),
                                                              builderDelegate:
                                                                  PagedChildBuilderDelegate<
                                                                      GamesRecord>(
                                                                // Customize what your widget looks like when it's loading the first page.
                                                                firstPageProgressIndicatorBuilder:
                                                                    (_) => const SizedBox
                                                                        .shrink(),
                                                                // Customize what your widget looks like when it's loading another page.
                                                                newPageProgressIndicatorBuilder:
                                                                    (_) => const SizedBox
                                                                        .shrink(),
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
                                                                          .listViewPagingController4!
                                                                          .itemList![
                                                                      listViewIndex];
                                                                  if (!_isGameVisibleForPlayer(listViewGamesRecord)) {
                                                                    return const SizedBox.shrink();
                                                                  }
                                                                  return HomeAsyncGameCard(
                                                                    game:
                                                                        listViewGamesRecord,
                                                                    onTap:
                                                                        () async {
                                                                      await _openGameDetails(
                                                                        listViewGamesRecord,
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
                                                          Text(
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
                                                          Container(
                                                            width:
                                                                double.infinity,
                                                            height: AppStyles.gameCardHeight + 8.0,
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
                                                              ),
                                                              padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                              primary: false,
                                                              reverse: false,
                                                              scrollDirection:
                                                                  Axis.horizontal,
                                                              separatorBuilder: (_,
                                                                      __) =>
                                                                  const SizedBox(
                                                                      width:
                                                                          10.0),
                                                              builderDelegate:
                                                                  PagedChildBuilderDelegate<
                                                                      GamesRecord>(
                                                                // Customize what your widget looks like when it's loading the first page.
                                                                firstPageProgressIndicatorBuilder:
                                                                    (_) => const SizedBox
                                                                        .shrink(),
                                                                // Customize what your widget looks like when it's loading another page.
                                                                newPageProgressIndicatorBuilder:
                                                                    (_) => const SizedBox
                                                                        .shrink(),
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
                                                                          .listViewPagingController3!
                                                                          .itemList![
                                                                      listViewIndex];

                                                                  if (!_isGameVisibleForPlayer(listViewGamesRecord)) {

                                                                    return const SizedBox.shrink();

                                                                  }

                                                                  return HomeAsyncGameCard(
                                                                    game:
                                                                        listViewGamesRecord,
                                                                    onTap:
                                                                        () async {
                                                                      await _openGameDetails(
                                                                        listViewGamesRecord,
                                                                      );
                                                                    },
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                          ),
                                                          Text(
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
                                                          StreamBuilder<
                                                              List<
                                                                  GamesRecord>>(
                                                            stream:
                                                                queryGamesRecord(
                                                              queryBuilder:
                                                                  (gamesRecord) =>
                                                                      gamesRecord
                                                                          .orderBy(
                                                                'end_date',
                                                                descending: true,
                                                              ),
                                                            ),
                                                            builder: (context,
                                                                snapshot) {
                                                              if (!snapshot
                                                                  .hasData) {
                                                                return const SizedBox
                                                                    .shrink();
                                                              }
                                                              _markHomeDataReady(
                                                                itemCount:
                                                                    snapshot.data
                                                                        ?.length ??
                                                                        0,
                                                              );
                                                              final recentlyEndedGames = snapshot
                                                                  .data!
                                                                  .where(
                                                                    _shouldShowInFinishedGames,
                                                                  )
                                                                  .toList()
                                                                ..sort((a, b) => (b
                                                                            .endDate ??
                                                                        DateTime
                                                                            .fromMillisecondsSinceEpoch(
                                                                                0))
                                                                    .compareTo(a
                                                                            .endDate ??
                                                                        DateTime.fromMillisecondsSinceEpoch(
                                                                            0)));

                                                              if (recentlyEndedGames
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
                                                                height: AppStyles.finishedGameListHeight,
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
                                                                      recentlyEndedGames
                                                                          .length,
                                                                  separatorBuilder: (_,
                                                                          __) =>
                                                                      const SizedBox(
                                                                          width:
                                                                              10.0),
                                                                  itemBuilder:
                                                                      (context,
                                                                          idx) {
                                                                    final game =
                                                                        recentlyEndedGames[
                                                                            idx];
                                                                    return HomeFinishedGameCard(
                                                                      game:
                                                                          game,
                                                                      onTap:
                                                                          () async {
                                                                        await _openGameDetails(
                                                                          game,
                                                                        );
                                                                      },
                                                                    );
                                                                  },
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        ].divide(const SizedBox(
                                                            height: 5.0)),
                                                      ),
                                                    ),
                                                  ].divide(
                                                      const SizedBox(height: 15.0)),
                                                ),
                                              ),
                                            );
                                          } else {
                                            return SingleChildScrollView(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.max,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    decoration: const BoxDecoration(),
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
                                                          height: AppStyles.gameCardHeight + 8.0,
                                                          decoration:
                                                              const BoxDecoration(),
                                                          child: PagedListView<
                                                              DocumentSnapshot<
                                                                  Object?>?,
                                                              GamesRecord>.separated(
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
                                                            separatorBuilder: (_,
                                                                    __) =>
                                                                const SizedBox(
                                                                    width:
                                                                        10.0),
                                                            builderDelegate:
                                                                PagedChildBuilderDelegate<
                                                                    GamesRecord>(
                                                              // Customize what your widget looks like when it's loading the first page.
                                                              firstPageProgressIndicatorBuilder:
                                                                  (_) => const SizedBox
                                                                      .shrink(),
                                                              // Customize what your widget looks like when it's loading another page.
                                                              newPageProgressIndicatorBuilder:
                                                                  (_) => const SizedBox
                                                                      .shrink(),
                                                              noItemsFoundIndicatorBuilder:
                                                                  (_) =>
                                                                      const SizedBox(
                                                                height: AppStyles.gameCardHeight,
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
                                                                if (!_isGameVisibleForPlayer(listViewGamesRecord)) {
                                                                  return const SizedBox.shrink();
                                                                }
                                                                return HomeAsyncGameCard(
                                                                  game:
                                                                      listViewGamesRecord,
                                                                  onTap:
                                                                      () async {
                                                                    await _openGameDetails(
                                                                      listViewGamesRecord,
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
                                                    decoration: const BoxDecoration(),
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
                                                          height: AppStyles.gameCardHeight + 8.0,
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
                                                                EdgeInsets.zero,
                                                            primary: false,
                                                            reverse: false,
                                                            scrollDirection:
                                                                Axis.horizontal,
                                                            separatorBuilder: (_,
                                                                    __) =>
                                                                const SizedBox(
                                                                    width:
                                                                        10.0),
                                                            builderDelegate:
                                                                PagedChildBuilderDelegate<
                                                                    GamesRecord>(
                                                              // Customize what your widget looks like when it's loading the first page.
                                                              firstPageProgressIndicatorBuilder:
                                                                  (_) => const SizedBox
                                                                      .shrink(),
                                                              // Customize what your widget looks like when it's loading another page.
                                                              newPageProgressIndicatorBuilder:
                                                                  (_) => const SizedBox
                                                                      .shrink(),
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
                                                                        .listViewPagingController6!
                                                                        .itemList![
                                                                    listViewIndex];
                                                                if (!_isGameVisibleForPlayer(listViewGamesRecord)) {
                                                                  return const SizedBox.shrink();
                                                                }
                                                                return HomeAsyncGameCard(
                                                                  game:
                                                                      listViewGamesRecord,
                                                                  onTap:
                                                                      () async {
                                                                    await _openGameDetails(
                                                                      listViewGamesRecord,
                                                                    );
                                                                  },
                                                                  isHighlighted:
                                                                      listViewIndex ==
                                                                          0,
                                                                );
                                                              },
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Container(
                                                    decoration: const BoxDecoration(),
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
                                                          height: AppStyles.gameCardHeight + 8.0,
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
                                                                  .orderBy(
                                                                      'end_date'),
                                                            ),
                                                            padding:
                                                                EdgeInsets.zero,
                                                            primary: false,
                                                            reverse: false,
                                                            scrollDirection:
                                                                Axis.horizontal,
                                                            separatorBuilder: (_,
                                                                    __) =>
                                                                const SizedBox(
                                                                    width:
                                                                        10.0),
                                                            builderDelegate:
                                                                PagedChildBuilderDelegate<
                                                                    GamesRecord>(
                                                              // Customize what your widget looks like when it's loading the first page.
                                                              firstPageProgressIndicatorBuilder:
                                                                  (_) => const SizedBox
                                                                      .shrink(),
                                                              // Customize what your widget looks like when it's loading another page.
                                                              newPageProgressIndicatorBuilder:
                                                                  (_) => const SizedBox
                                                                      .shrink(),
                                                              noItemsFoundIndicatorBuilder:
                                                                  (_) =>
                                                                      const ListEmptyComponentWidget(
                                                                title:
                                                                    'Aucun jeux',
                                                                description:
                                                                    ' ',
                                                              ),
                                                              itemBuilder: (context,
                                                                  _,
                                                                  listViewIndex) {
                                                                final listViewGamesRecord = _model
                                                                        .listViewPagingController7!
                                                                        .itemList![
                                                                    listViewIndex];
                                                                if (!_isGameVisibleForPlayer(listViewGamesRecord)) {
                                                                  return const SizedBox.shrink();
                                                                }
                                                                return HomeAsyncGameCard(
                                                                  game:
                                                                      listViewGamesRecord,
                                                                  onTap:
                                                                      () async {
                                                                    await _openGameDetails(
                                                                      listViewGamesRecord,
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
                                                ].divide(
                                                    const SizedBox(height: 10.0)),
                                              ),
                                            );
                                          }
                                        },
                                      );
                                    } else {
                                      return RefreshIndicator(
                                        key: const Key('RefreshIndicator_jug9m9tx'),
                                        onRefresh: _refreshHomeContent,
                                        child: SingleChildScrollView(
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.max,
                                            children: [
                                              Container(
                                                width: double.infinity,
                                                decoration: const BoxDecoration(),
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
                                                    Container(
                                                      width: double.infinity,
                                                      height: AppStyles.gameCardHeight + 8.0,
                                                      decoration:
                                                          const BoxDecoration(),
                                                      child: PagedListView<
                                                          DocumentSnapshot<
                                                              Object?>?,
                                                          GamesRecord>.separated(
                                                        pagingController: _model
                                                            .setListViewController8(
                                                          GamesRecord.collection
                                                              .where(
                                                                'hasWinner',
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
                                                            (_, __) => const SizedBox(
                                                                width: 10.0),
                                                        builderDelegate:
                                                            PagedChildBuilderDelegate<
                                                                GamesRecord>(
                                                          // Customize what your widget looks like when it's loading the first page.
                                                          firstPageProgressIndicatorBuilder:
                                                              (_) => const SizedBox
                                                                  .shrink(),
                                                          // Customize what your widget looks like when it's loading another page.
                                                          newPageProgressIndicatorBuilder:
                                                              (_) => const SizedBox
                                                                  .shrink(),
                                                          noItemsFoundIndicatorBuilder:
                                                              (_) => const SizedBox(
                                                            height: AppStyles.gameCardHeight,
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
                                                            if (!_isGameVisibleForPlayer(listViewGamesRecord)) {
                                                              return const SizedBox.shrink();
                                                            }
                                                            return HomeAsyncGameCard(
                                                              game:
                                                                  listViewGamesRecord,
                                                              isHighlighted:
                                                                  listViewIndex ==
                                                                      0,
                                                              onTap: () async {
                                                                await _openGameDetails(
                                                                  listViewGamesRecord,
                                                                );
                                                              },
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                    ),
                                                  ].divide(
                                                      const SizedBox(height: 5.0)),
                                                ),
                                              ),
                                              Container(
                                                width: double.infinity,
                                                decoration: const BoxDecoration(),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    Text(
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
                                                    Container(
                                                      width: double.infinity,
                                                      height: AppStyles.gameCardHeight + 8.0,
                                                      decoration: const BoxDecoration(
                                                        color:
                                                            Colors.transparent,
                                                      ),
                                                      child: PagedListView<
                                                          DocumentSnapshot<
                                                              Object?>?,
                                                          GamesRecord>.separated(
                                                        pagingController: _model
                                                            .setListViewController9(
                                                          GamesRecord.collection
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
                                                            EdgeInsets.zero,
                                                        primary: false,
                                                        reverse: false,
                                                        scrollDirection:
                                                            Axis.horizontal,
                                                        separatorBuilder:
                                                            (_, __) => const SizedBox(
                                                                width: 10.0),
                                                        builderDelegate:
                                                            PagedChildBuilderDelegate<
                                                                GamesRecord>(
                                                          // Customize what your widget looks like when it's loading the first page.
                                                          firstPageProgressIndicatorBuilder:
                                                              (_) => const SizedBox
                                                                  .shrink(),
                                                          // Customize what your widget looks like when it's loading another page.
                                                          newPageProgressIndicatorBuilder:
                                                              (_) => const SizedBox
                                                                  .shrink(),
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
                                                            if (!_isGameVisibleForPlayer(listViewGamesRecord)) {
                                                              return const SizedBox.shrink();
                                                            }
                                                            return HomeAsyncGameCard(
                                                              game:
                                                                  listViewGamesRecord,
                                                              onTap: () async {
                                                                await _openGameDetails(
                                                                  listViewGamesRecord,
                                                                );
                                                              },
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                    ),
                                                  ].divide(
                                                      const SizedBox(height: 5.0)),
                                                ),
                                              ),
                                              Container(
                                                decoration: const BoxDecoration(),
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
                                                      height: AppStyles.gameCardHeight + 8.0,
                                                      decoration: const BoxDecoration(
                                                        color:
                                                            Colors.transparent,
                                                      ),
                                                      child: PagedListView<
                                                          DocumentSnapshot<
                                                              Object?>?,
                                                          GamesRecord>.separated(
                                                        pagingController: _model
                                                            .setListViewController10(
                                                          GamesRecord.collection
                                                              .where(
                                                                'hasWinner',
                                                                isEqualTo:
                                                                    false,
                                                              )
                                                              .orderBy(
                                                                  'end_date'),
                                                        ),
                                                        padding:
                                                            EdgeInsets.zero,
                                                        primary: false,
                                                        reverse: false,
                                                        scrollDirection:
                                                            Axis.horizontal,
                                                        separatorBuilder:
                                                            (_, __) => const SizedBox(
                                                                width: 10.0),
                                                        builderDelegate:
                                                            PagedChildBuilderDelegate<
                                                                GamesRecord>(
                                                          // Customize what your widget looks like when it's loading the first page.
                                                          firstPageProgressIndicatorBuilder:
                                                              (_) => const SizedBox
                                                                  .shrink(),
                                                          // Customize what your widget looks like when it's loading another page.
                                                          newPageProgressIndicatorBuilder:
                                                              (_) => const SizedBox
                                                                  .shrink(),
                                                          noItemsFoundIndicatorBuilder:
                                                              (_) =>
                                                                  const ListEmptyComponentWidget(
                                                            title: 'Aucun jeux',
                                                            description: ' ',
                                                          ),
                                                          itemBuilder: (context,
                                                              _,
                                                              listViewIndex) {
                                                            final listViewGamesRecord = _model
                                                                    .listViewPagingController10!
                                                                    .itemList![
                                                                listViewIndex];
                                                            if (!_isGameVisibleForPlayer(listViewGamesRecord)) {
                                                              return const SizedBox.shrink();
                                                            }
                                                            return HomeAsyncGameCard(
                                                              game:
                                                                  listViewGamesRecord,
                                                              onTap: () async {
                                                                await _openGameDetails(
                                                                  listViewGamesRecord,
                                                                );
                                                              },
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                    ),
                                                  ].divide(
                                                      const SizedBox(height: 5.0)),
                                                ),
                                              ),
                                            ].divide(const SizedBox(height: 15.0)),
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



