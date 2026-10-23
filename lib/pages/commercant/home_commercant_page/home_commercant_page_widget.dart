import '/components/merchant_games_load_error.dart';
import '/components/merchant_home_viewport.dart';
import '/services/merchant_prizes_service.dart';
import '/services/merchant_games_service.dart';
import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/components/custom_nav_bar_commercant2_widget.dart';
import '/components/list_empty_component_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/utils/game_metrics.dart';
import '/utils/proxiplay_layout.dart';
import '/widgets/proxiplay_loading_logo.dart';
import '/index.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_commercant_page_model.dart';
export 'home_commercant_page_model.dart';

class HomeCommercantPageWidget extends StatefulWidget {
  const HomeCommercantPageWidget({super.key});

  static String routeName = 'HomeCommercantPage';
  static String routePath = 'homeCommercantPage';

  @override
  State<HomeCommercantPageWidget> createState() =>
      _HomeCommercantPageWidgetState();
}

class _HomeCommercantPageWidgetState extends State<HomeCommercantPageWidget> {
  late HomeCommercantPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isCheckingCode = false;
  static const _suggestionMinimumCharacters = 3;
  static const _suggestionLimit = 5;
  static const _suggestionDebounce = Duration(milliseconds: 200);
  // A fast answer replaces the results directly; the "searching" line only
  // appears when the call takes longer, so typing does not make it flicker.
  static const _searchingIndicatorDelay = Duration(milliseconds: 250);

  String? _merchantPrizeCacheUid;
  List<PrizesRecord> _codeSuggestions = const [];
  Timer? _suggestionDebounceTimer;
  Timer? _searchingIndicatorTimer;
  bool _showSearchingIndicator = false;
  bool _isLoadingSuggestions = false;
  bool _showNoSuggestions = false;
  bool _suggestionLoadFailed = false;
  String _suggestionFailureMessage = '';
  int _suggestionRequestId = 0;
  // Code the displayed suggestions were searched for, and whether the server
  // returned every match (below the limit): only then can a partial code be
  // resolved to its single suggestion without the merchant tapping it.
  String? _suggestionsForCode;
  bool _suggestionsComplete = false;
  // Shown when "Vérifier" is pressed on a partial code that matches
  // suggestions the merchant still has to pick from.
  String? _pickHintForCode;
  String _pickHintMessage = '';

  void _stopSearchingIndicator() {
    _searchingIndicatorTimer?.cancel();
    _searchingIndicatorTimer = null;
    _showSearchingIndicator = false;
  }

  void _invalidatePrizeSuggestionCache() {
    _merchantPrizeCacheUid = null;
    _codeSuggestions = const [];
    _suggestionsForCode = null;
    _stopSearchingIndicator();
    _isLoadingSuggestions = false;
    _showNoSuggestions = false;
    _suggestionLoadFailed = false;
  }

  void _onWinningCodeChanged() {
    if (_isCheckingCode) return;
    _suggestionDebounceTimer?.cancel();
    final requestId = ++_suggestionRequestId;
    final normalizedCode = _normalizeClaimCode(_model.textController.text);
    if (normalizedCode.length < _suggestionMinimumCharacters) {
      if (mounted) {
        setState(() {
          _stopSearchingIndicator();
          _codeSuggestions = const [];
          _suggestionsForCode = null;
          _isLoadingSuggestions = false;
          _showNoSuggestions = false;
          _suggestionLoadFailed = false;
        });
      }
      return;
    }
    _suggestionDebounceTimer = Timer(_suggestionDebounce, () {
      _loadCodeSuggestions(normalizedCode, requestId);
    });
  }

  Future<void> _loadCodeSuggestions(
      String normalizedCode, int requestId) async {
    final uid = currentUserUid;
    if (uid.isEmpty || requestId != _suggestionRequestId) return;
    if (_merchantPrizeCacheUid != null && _merchantPrizeCacheUid != uid) {
      _invalidatePrizeSuggestionCache();
    }
    _merchantPrizeCacheUid ??= uid;

    try {
      if (mounted && requestId == _suggestionRequestId) {
        setState(() {
          _isLoadingSuggestions = true;
          _suggestionLoadFailed = false;
        });
        _searchingIndicatorTimer?.cancel();
        _searchingIndicatorTimer = Timer(_searchingIndicatorDelay, () {
          if (!mounted ||
              requestId != _suggestionRequestId ||
              !_isLoadingSuggestions) {
            return;
          }
          setState(() => _showSearchingIndicator = true);
        });
      }
      final loadedPrizes = await searchMerchantPrizeCodes(normalizedCode)
          .timeout(const Duration(seconds: 15));
      if (!mounted || requestId != _suggestionRequestId || currentUserUid != uid) return;
      final suggestions = loadedPrizes
          // Claimed prizes stay listed, flagged "Déjà retiré"; the server
          // returns them after the prizes that can still be handed over.
          .where((prize) => prize.fulfillmentType == 'merchant' && !prize.isExpired &&
              _normalizeClaimCode(prize.claimCode).startsWith(normalizedCode))
          .take(_suggestionLimit).toList(growable: false);
      setState(() {
        _stopSearchingIndicator();
        _isLoadingSuggestions = false;
        _suggestionLoadFailed = false;
        _codeSuggestions = suggestions;
        _suggestionsForCode = normalizedCode;
        _suggestionsComplete = loadedPrizes.length < _suggestionLimit;
        _showNoSuggestions = suggestions.isEmpty;
      });
    } catch (error) {
      if (!mounted ||
          requestId != _suggestionRequestId ||
          currentUserUid != uid) {
        return;
      }
      // A failed load is not cached: a later edit can retry without ever
      // treating stale or partial data as an authorization decision.
      setState(() {
        _stopSearchingIndicator();
        _isLoadingSuggestions = false;
        _codeSuggestions = const [];
        _suggestionsForCode = null;
        _showNoSuggestions = false;
        _suggestionLoadFailed = true;
        _suggestionFailureMessage = suggestionFailureMessage(error);
      });
    }
  }

  void _selectCodeSuggestion(PrizesRecord prize) {
    _suggestionDebounceTimer?.cancel();
    _suggestionRequestId++;
    _model.textController.text = _normalizeClaimCode(prize.claimCode);
    _model.textController!.selection = TextSelection.collapsed(
      offset: _model.textController!.text.length,
    );
    setState(() {
      _stopSearchingIndicator();
      _isLoadingSuggestions = false;
      _codeSuggestions = const [];
      _showNoSuggestions = false;
      _suggestionLoadFailed = false;
    });
    FocusScope.of(context).unfocus();
  }

  Widget _buildCodeSuggestions() {
    // Never render cached data for a different session, even if an auth
    // transition happens without another keystroke.
    if (_merchantPrizeCacheUid != null &&
        _merchantPrizeCacheUid != currentUserUid) {
      return const SizedBox.shrink();
    }
    final typedCode = _normalizeClaimCode(_model.textController?.text ?? '');
    if (_showSearchingIndicator) {
      return const Padding(
        key: ValueKey('code-search-in-progress'),
        padding: EdgeInsetsDirectional.fromSTEB(16.0, 0.0, 16.0, 8.0),
        child: Row(
          children: [
            SizedBox(
              width: 16.0,
              height: 16.0,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
            SizedBox(width: 8.0),
            Text('Recherche en cours…'),
          ],
        ),
      );
    }
    // Until the delayed indicator shows, keep the previous answer on screen
    // as long as it still fits what is typed, instead of blanking it.
    final visibleSuggestions = _codeSuggestions
        .where((prize) =>
            _normalizeClaimCode(prize.claimCode).startsWith(typedCode))
        .toList(growable: false);
    if (_suggestionLoadFailed && !_isLoadingSuggestions) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16.0, 0.0, 16.0, 8.0),
        child: Text(_suggestionFailureMessage),
      );
    }
    // "No match" is a final answer: never shown while a search is running.
    if (_showNoSuggestions &&
        !_isLoadingSuggestions &&
        visibleSuggestions.isEmpty) {
      return const Padding(
        padding: EdgeInsetsDirectional.fromSTEB(16.0, 0.0, 16.0, 8.0),
        child: Text('Aucun code correspondant'),
      );
    }
    if (visibleSuggestions.isEmpty) return const SizedBox.shrink();

    final list = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16.0, 0.0, 16.0, 8.0),
      child: Material(
        color: FlutterFlowTheme.of(context).primaryBackground,
        borderRadius: BorderRadius.circular(12.0),
        child: ConstrainedBox(
          // Keep the home content usable above the Android keyboard. More
          // than three of the five capped results remains scrollable here.
          constraints: const BoxConstraints(maxHeight: 156.0),
          child: ListView.separated(
            shrinkWrap: true,
            primary: false,
            padding: EdgeInsets.zero,
            itemCount: visibleSuggestions.length,
            separatorBuilder: (_, __) => const Divider(height: 1.0),
            itemBuilder: (context, index) {
              final prize = visibleSuggestions[index];
              return ListTile(
                dense: true,
                title: Text(prize.claimCode),
                subtitle: prize.name.trim().isEmpty ? null : Text(prize.name),
                trailing: prize.claimed
                    ? const Text('Déjà retiré',
                        style: TextStyle(
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.w600))
                    : const Icon(Icons.chevron_right_rounded),
                onTap: () => _selectCodeSuggestion(prize),
              );
            },
          ),
        ),
      ),
    );
    // The hint only applies to the code it was raised for: any edit hides it.
    if (_pickHintForCode != typedCode) return list;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          key: const ValueKey('code-pick-hint'),
          padding: const EdgeInsetsDirectional.fromSTEB(16.0, 0.0, 16.0, 6.0),
          child: Text(
            _pickHintMessage,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  color: FlutterFlowTheme.of(context).primary,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        list,
      ],
    );
  }

  Future<void> _checkWinningCode() async {
    if (_isCheckingCode) return;
    final clock = Stopwatch()..start();
    void trace(String stage) {
      if (kDebugMode) {
        debugPrint(
            '[MerchantCodeCheck] $stage elapsedMs=${clock.elapsedMilliseconds}');
      }
    }

    trace('T0 click');
    var code = _normalizeClaimCode(_model.textController.text);
    // A partial code with suggestions on screen: the merchant meant one of
    // them. Use it when it is provably the only match, otherwise ask them to
    // pick, instead of answering "Code invalide" next to the right lot.
    final matches = _codeSuggestions
        .where((p) => _normalizeClaimCode(p.claimCode).startsWith(code))
        .toList(growable: false);
    final isExact =
        matches.any((p) => _normalizeClaimCode(p.claimCode) == code);
    if (code.length >= _suggestionMinimumCharacters &&
        !isExact &&
        matches.isNotEmpty) {
      final searched = _suggestionsForCode;
      final allMatchesKnown = !_isLoadingSuggestions &&
          searched != null &&
          code.startsWith(searched) &&
          (searched == code || _suggestionsComplete);
      if (matches.length == 1 && allMatchesKnown) {
        code = _normalizeClaimCode(matches.single.claimCode);
      } else {
        setState(() {
          _pickHintForCode = code;
          _pickHintMessage = matches.length > 1
              ? 'Plusieurs lots correspondent : touchez le bon code ci-dessous.'
              : 'Touchez le code ci-dessous pour le vérifier.';
        });
        FocusScope.of(context).unfocus();
        return;
      }
    }
    _suggestionDebounceTimer?.cancel();
    _suggestionRequestId++;
    setState(() {
      _isCheckingCode = true;
      _codeSuggestions = const [];
      _suggestionsForCode = null;
      _pickHintForCode = null;
      _showNoSuggestions = false;
      _suggestionLoadFailed = false;
    });
    FocusScope.of(context).unfocus();
    _model.textController.text = code;
    PrizesRecord? prize;
    String? message;
    try {
      // Paint the loading state before starting network work.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      trace('T1 request');
      prize = await _findPrizeForMerchantClaimCode(code, onTrace: trace);
      trace('T2 response');
      if (prize == null) {
        message = 'Code invalide';
      } else if (prize.claimed) {
        message = 'Ce lot a déjà été retiré.';
      } else if (prize.isExpired) {
        message = 'Ce code a expiré.';
      }
    } catch (_) {
      // Never log the code, contact data, or raw backend errors.
      trace('T2 error_or_timeout');
      message = 'Impossible de vérifier le code pour le moment. Réessayez.';
    } finally {
      if (mounted) setState(() => _isCheckingCode = false);
    }
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    if (message != null) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(message!),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer'))
          ],
        ),
      );
    } else {
      await context.pushNamed(
        ValidationLotCommercantPageWidget.routeName,
        queryParameters:
            {'prize': serializeParam(prize, ParamType.Document)}.withoutNulls,
        extra: <String, dynamic>{'prize': prize},
      );
      // A successful claim is made on the next screen. Refresh after every
      // return so a cached code can never be suggested as still available.
      if (mounted) {
        setState(_invalidatePrizeSuggestionCache);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) trace('T3 result_frame');
    });
  }

  String _normalizeClaimCode(String rawValue) {
    return rawValue.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  Future<PrizesRecord?> _findPrizeForMerchantClaimCode(String rawCode,
      {void Function(String)? onTrace}) async {
    final code = _normalizeClaimCode(rawCode);
    if (code.isEmpty || currentUserReference == null) return null;
    final prizes = await loadMerchantPrizes(
        timeout: const Duration(seconds: 15), onTrace: onTrace);
    return prizes.firstWhereOrNull(
        (prize) => _normalizeClaimCode(prize.claimCode) == code);
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 7.0),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Text(
        'Actif',
        style: FlutterFlowTheme.of(context).bodySmall.override(
              font: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
              ),
              color: const Color(0xFF2E7D32),
              letterSpacing: 0.0,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _buildMetricChip({
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(14.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16.0,
            color: FlutterFlowTheme.of(context).primary,
          ),
          const SizedBox(width: 5.0),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  font: GoogleFonts.inter(
                    fontWeight:
                        FlutterFlowTheme.of(context).bodySmall.fontWeight,
                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                  ),
                  color: FlutterFlowTheme.of(context).primaryText,
                  letterSpacing: 0.0,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentGameCard(GamesRecord game) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 154.0),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(22.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C0E1220),
            blurRadius: 14.0,
            offset: Offset(0.0, 4.0),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 104.0,
              height: 104.0,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18.0),
                color: FlutterFlowTheme.of(context).primary,
              ),
              clipBehavior: Clip.antiAlias,
              child: CachedNetworkImage(
                fadeInDuration: const Duration(milliseconds: 300),
                fadeOutDuration: const Duration(milliseconds: 300),
                imageUrl: game.photo,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 16.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          game.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              FlutterFlowTheme.of(context).titleLarge.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FontWeight.w700,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleLarge
                                          .fontStyle,
                                    ),
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 10.0),
                      _buildStatusBadge(),
                    ],
                  ),
                  const SizedBox(height: 10.0),
                  Text(
                    'Du ${dateTimeFormat(
                      "d/M/y",
                      game.startDate,
                      locale: FFLocalizations.of(context).languageCode,
                    )} au ${dateTimeFormat(
                      "d/M/y",
                      game.endDate,
                      locale: FFLocalizations.of(context).languageCode,
                    )}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                          font: GoogleFonts.inter(
                            fontWeight: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .fontWeight,
                            fontStyle: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .fontStyle,
                          ),
                          color: FlutterFlowTheme.of(context).secondaryText,
                          letterSpacing: 0.0,
                        ),
                  ),
                  const SizedBox(height: 10.0),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: [
                      _buildMetricChip(
                        icon: Icons.remove_red_eye,
                        text: 'Ouvertures ${gameViewsDisplayValue(game)}',
                      ),
                      _buildMetricChip(
                        icon: Icons.sports_esports_rounded,
                        text: 'Joueurs ${game.participations}',
                      ),
                      _buildMetricChip(
                        icon: Icons.star_rounded,
                        text: 'Favoris ${game.favorites}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => HomeCommercantPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'HomeCommercantPage'});
    _model.textController ??= TextEditingController();
    _model.textFieldFocusNode ??= FocusNode();
    _model.textController!.addListener(_onWinningCodeChanged);
  }

  @override
  void dispose() {
    _suggestionDebounceTimer?.cancel();
    _searchingIndicatorTimer?.cancel();
    _model.textController?.removeListener(_onWinningCodeChanged);
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: PopScope(
        canPop: false,
        child: Scaffold(
          key: scaffoldKey,
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(60.0),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0.0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0.0,
              automaticallyImplyLeading: false,
              actions: const [],
              flexibleSpace: FlexibleSpaceBar(
                title: Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: SvgPicture.asset(
                        'assets/images/logo_D_secondaire_sans_html_avec_couleurs.svg',
                        width: 200.0,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
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
                    const EdgeInsetsDirectional.fromSTEB(0.0, 10.0, 0.0, 0.0),
              ),
              toolbarHeight: 60.0,
            ),
          ),
          body: SafeArea(
            top: true,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                image: DecorationImage(
                  fit: BoxFit.cover,
                  alignment: const AlignmentDirectional(-1.0, 1.0),
                  image: Image.asset(
                    'assets/images/Background.png',
                  ).image,
                ),
              ),
              child: SizedBox(
                height: double.infinity,
                child: Stack(
                  alignment: const AlignmentDirectional(0.0, 1.0),
                  children: [
                    Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        0.0,
                        0.0,
                        0.0,
                        MediaQuery.viewInsetsOf(context).bottom > 0
                            ? 0.0
                            : ProxiPlayLayout.bottomNavHeight(context) + 20.0,
                      ),
                      child: MerchantHomeViewport(
                        builder: (context, availableHeight) => Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              20.0, 20.0, 20.0, 0.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.max,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                decoration: const BoxDecoration(),
                              ),
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryBackground,
                                  borderRadius: BorderRadius.circular(20.0),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(10.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.max,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsetsDirectional
                                            .fromSTEB(16.0, 8.0, 0.0, 0.0),
                                        child: Text(
                                          'V\u00E9rifier le code gagnant',
                                          style: FlutterFlowTheme.of(context)
                                              .bodyMedium
                                              .override(
                                                font: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w600,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontStyle,
                                                ),
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primary,
                                                letterSpacing: 0.0,
                                                fontWeight: FontWeight.w600,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontStyle,
                                              ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsetsDirectional
                                            .fromSTEB(16.0, 0.0, 16.0, 16.0),
                                        child: TextFormField(
                                          controller: _model.textController,
                                          enabled: !_isCheckingCode,
                                          focusNode: _model.textFieldFocusNode,
                                          autofocus: false,
                                          obscureText: false,
                                          textCapitalization:
                                              TextCapitalization.characters,
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                              RegExp(r'[A-Za-z0-9\-\s]'),
                                            ),
                                          ],
                                          decoration: InputDecoration(
                                            labelStyle:
                                                FlutterFlowTheme.of(context)
                                                    .labelMedium
                                                    .override(
                                                      font: GoogleFonts.inter(
                                                        fontWeight:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .labelMedium
                                                                .fontWeight,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .labelMedium
                                                                .fontStyle,
                                                      ),
                                                      color:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .fieldText,
                                                      letterSpacing: 0.0,
                                                      fontWeight:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .labelMedium
                                                              .fontWeight,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .labelMedium
                                                              .fontStyle,
                                                    ),
                                            hintText:
                                                'Saisissez les premiers caractères du code gagnant…',
                                            hintMaxLines: 2,
                                            enabledBorder: OutlineInputBorder(
                                              borderSide: const BorderSide(
                                                color: Color(0x00000000),
                                                width: 2.0,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12.0),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primary,
                                                width: 2.0,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12.0),
                                            ),
                                            errorBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .error,
                                                width: 2.0,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12.0),
                                            ),
                                            focusedErrorBorder:
                                                OutlineInputBorder(
                                              borderSide: BorderSide(
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .error,
                                                width: 2.0,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12.0),
                                            ),
                                            filled: true,
                                            fillColor:
                                                FlutterFlowTheme.of(context)
                                                    .fieldBg,
                                            contentPadding:
                                                const EdgeInsets.all(24.0),
                                          ),
                                          style: FlutterFlowTheme.of(context)
                                              .bodyMedium
                                              .override(
                                                font: GoogleFonts.inter(
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontStyle,
                                                ),
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .fieldText,
                                                letterSpacing: 0.0,
                                                fontWeight:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontWeight,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontStyle,
                                              ),
                                          validator: _model
                                              .textControllerValidator
                                              .asValidator(context),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsetsDirectional
                                            .fromSTEB(16.0, 0.0, 16.0, 8.0),
                                        child: Align(
                                          alignment:
                                              AlignmentDirectional.centerStart,
                                          child: Text(
                                            'Les lots correspondants apparaissent automatiquement.',
                                            style: FlutterFlowTheme.of(context)
                                                .labelSmall
                                                .override(
                                                  font: GoogleFonts.inter(),
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .secondaryText,
                                                  letterSpacing: 0.0,
                                                ),
                                          ),
                                        ),
                                      ),
                                      _buildCodeSuggestions(),
                                      Builder(
                                        builder: (context) => Padding(
                                          padding: const EdgeInsetsDirectional
                                              .fromSTEB(16.0, 0.0, 16.0, 16.0),
                                          child: FFButtonWidget(
                                            onPressed: _isCheckingCode
                                                ? null
                                                : _checkWinningCode,
                                            showLoadingIndicator: false,
                                            icon: _isCheckingCode
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color:
                                                                Colors.white))
                                                : null,
                                            text: _isCheckingCode
                                                ? 'V\u00e9rification...'
                                                : 'V\u00e9rifier',
                                            options: FFButtonOptions(
                                              width: double.infinity,
                                              height: 40.0,
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                      16.0, 0.0, 16.0, 0.0),
                                              iconPadding:
                                                  const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                      0.0, 0.0, 0.0, 0.0),
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .primary,
                                              textStyle: FlutterFlowTheme.of(
                                                      context)
                                                  .titleSmall
                                                  .override(
                                                    font:
                                                        GoogleFonts.interTight(
                                                      fontWeight:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .titleSmall
                                                              .fontWeight,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .titleSmall
                                                              .fontStyle,
                                                    ),
                                                    color: Colors.white,
                                                    letterSpacing: 0.0,
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .titleSmall
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .titleSmall
                                                            .fontStyle,
                                                  ),
                                              elevation: 0.0,
                                              borderRadius:
                                                  BorderRadius.circular(8.0),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ].divide(const SizedBox(height: 15.0)),
                                  ),
                                ),
                              ),
                              Align(
                                alignment:
                                    const AlignmentDirectional(-1.0, 0.0),
                                child: Container(
                                  decoration: const BoxDecoration(),
                                  child: Text(
                                    'Jeux en cours',
                                    style: FlutterFlowTheme.of(context)
                                        .titleLarge
                                        .override(
                                          font: GoogleFonts.interTight(
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .titleLarge
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .titleLarge
                                                    .fontStyle,
                                          ),
                                          color: FlutterFlowTheme.of(context)
                                              .primary,
                                          letterSpacing: 0.0,
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .titleLarge
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .titleLarge
                                                  .fontStyle,
                                        ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: availableHeight > 500
                                    ? availableHeight - 320
                                    : 180,
                                child: Container(
                                  height: double.infinity,
                                  decoration: const BoxDecoration(),
                                  child: FutureBuilder<List<GamesRecord>>(
                                    future: (_model
                                                .firestoreRequestCompleter ??=
                                            Completer<List<GamesRecord>>()
                                              ..complete(logMerchantGamesFailure(
                                                      loadAllMerchantGames(),
                                                      'home')
                                                  .then((games) => games
                                                      .where((g) =>
                                                          g.endDate != null &&
                                                          !g.endDate!.isBefore(
                                                              getCurrentTimestamp))
                                                      .toList())))
                                        .future,
                                    builder: (context, snapshot) {
                                      // Customize what your widget looks like when it's loading.
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const Center(
                                          child: SizedBox(
                                            width: 40.0,
                                            height: 40.0,
                                            child: ProxiplayLoadingLogo(
                                                size: 42.0),
                                          ),
                                        );
                                      }
                                      if (snapshot.hasError) {
                                        return MerchantGamesLoadError(
                                            onRetry: () => setState(() {
                                                  _model.firestoreRequestCompleter =
                                                      null;
                                                }));
                                      }
                                      List<GamesRecord>
                                          listViewGamesRecordList =
                                          snapshot.data!;
                                      if (listViewGamesRecordList.isEmpty) {
                                        return const SizedBox(
                                          height: double.infinity,
                                          child: ListEmptyComponentWidget(
                                            title: 'Liste vide',
                                            description: 'Aucun jeux en cours',
                                          ),
                                        );
                                      }

                                      return RefreshIndicator(
                                        onRefresh: () async {
                                          safeSetState(() =>
                                              _model.firestoreRequestCompleter =
                                                  null);
                                          await _model
                                              .waitForFirestoreRequestCompleted();
                                        },
                                        child: ListView.separated(
                                          padding: EdgeInsets.zero,
                                          scrollDirection: Axis.vertical,
                                          itemCount:
                                              listViewGamesRecordList.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(height: 10.0),
                                          itemBuilder:
                                              (context, listViewIndex) {
                                            final listViewGamesRecord =
                                                listViewGamesRecordList[
                                                    listViewIndex];
                                            return InkWell(
                                              splashColor: Colors.transparent,
                                              focusColor: Colors.transparent,
                                              hoverColor: Colors.transparent,
                                              highlightColor:
                                                  Colors.transparent,
                                              onTap: () async {
                                                _model.enseigneRef =
                                                    await EnseignesRecord
                                                        .getDocumentOnce(
                                                            listViewGamesRecord
                                                                .enseigneId!);
                                                if (!context.mounted) return;

                                                context.pushNamed(
                                                  JeuDetailCommercantPageWidget
                                                      .routeName,
                                                  queryParameters: {
                                                    'gameDoc': serializeParam(
                                                      listViewGamesRecord,
                                                      ParamType.Document,
                                                    ),
                                                    'enseigneDoc':
                                                        serializeParam(
                                                      _model.enseigneRef,
                                                      ParamType.Document,
                                                    ),
                                                  }.withoutNulls,
                                                  extra: <String, dynamic>{
                                                    'gameDoc':
                                                        listViewGamesRecord,
                                                    'enseigneDoc':
                                                        _model.enseigneRef,
                                                  },
                                                );

                                                safeSetState(() {});
                                              },
                                              child: _buildCurrentGameCard(
                                                listViewGamesRecord,
                                              ),
                                            );
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ].divide(const SizedBox(height: 10.0)),
                          ),
                        ),
                      ),
                    ),
                    if (MediaQuery.viewInsetsOf(context).bottom == 0) wrapWithModel(
                      model: _model.customNavBarCommercant2Model,
                      updateCallback: () => safeSetState(() {}),
                      child: const CustomNavBarCommercant2Widget(
                        indexActive: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
