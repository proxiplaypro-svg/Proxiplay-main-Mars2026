import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/components/list_empty_component_widget.dart';
import '/flutter_flow/flutter_flow_expanded_image_view.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/widgets/proxiplay_loading_logo.dart';
import '/widgets/proxiplay_network_image.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/index.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'enseigne_detail_joueur_page_model.dart';
export 'enseigne_detail_joueur_page_model.dart';

/// remplir le container sous l'image par une liste de text
class EnseigneDetailJoueurPageWidget extends StatefulWidget {
  const EnseigneDetailJoueurPageWidget({
    super.key,
    required this.enseigneDoc,
  });

  final EnseignesRecord? enseigneDoc;

  static String routeName = 'EnseigneDetailJoueurPage';
  static String routePath = 'enseigneDetailJoueurPage';

  @override
  State<EnseigneDetailJoueurPageWidget> createState() =>
      _EnseigneDetailJoueurPageWidgetState();
}

class _EnseigneDetailJoueurPageWidgetState
    extends State<EnseigneDetailJoueurPageWidget> {
  late EnseigneDetailJoueurPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  Future<List<GamesRecord>>? _ongoingGamesFuture;
  String? _ongoingGamesFutureKey;

  int _daySortIndex(HorairesRecord record) {
    final day = record.day;
    if (day != null) {
      return DayOfTheWeek.values.indexOf(day);
    }
    return record.order;
  }

  bool _isGameVisibleForPlayer(GamesRecord game) {
    final now = getCurrentTimestamp;
    final endDate = game.endDate;
    if (endDate == null || !endDate.isAfter(now)) {
      return false;
    }
    final startDate = game.startDate;
    if (startDate != null && now.isBefore(startDate)) {
      return false;
    }
    return true;
  }

  String _formatPrizeLabel(GamesRecord game) {
    final hasSecondaryPrizes = game.secondaryPrizes.isNotEmpty ||
        game.secondaryPrizeDescription.trim().isNotEmpty;
    if (game.prizeValue == 0 && hasSecondaryPrizes) {
      return 'Gains immediats';
    }
    return game.prizeValue.toString();
  }

  bool get _canViewMinorRestrictedGames =>
      currentUserUid == '' ||
      isGuestOrAnonymous ||
      ((currentUserDocument?.birthday != null) &&
          functions.isAdult(currentUserDocument!.birthday!));

  String _buildOngoingGamesFutureKey() =>
      '${widget.enseigneDoc?.reference.path ?? 'no_enseigne'}|'
      '${_canViewMinorRestrictedGames ? 'all_games' : 'adult_safe_only'}';

  Future<List<GamesRecord>> _createOngoingGamesFuture() {
    return queryGamesRecordOnce(
      queryBuilder: (gamesRecord) {
        var query = gamesRecord
            .where(
              'enseigne_id',
              isEqualTo: widget.enseigneDoc?.reference,
            )
            .where(
              'end_date',
              isGreaterThan: getCurrentTimestamp,
            );

        if (!_canViewMinorRestrictedGames) {
          query = query.where(
            'prohibited_for_minors',
            isEqualTo: false,
          );
        }

        return query;
      },
      limit: 15,
    );
  }

  Future<List<GamesRecord>> _getOngoingGamesFuture() {
    final nextKey = _buildOngoingGamesFutureKey();
    if (_ongoingGamesFuture == null || _ongoingGamesFutureKey != nextKey) {
      _ongoingGamesFutureKey = nextKey;
      _ongoingGamesFuture = _createOngoingGamesFuture();
    }
    return _ongoingGamesFuture!;
  }

  String? _ensureHttpScheme(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return 'https://$s';
  }

  bool _hasWhitespace(String s) => RegExp(r'\s').hasMatch(s);

  int _readFavoriteCounter(Map<String, dynamic> data) {
    final dynamic raw = data['favoritesCount'] ??
        data['favorites'] ??
        data['favorisCount'] ??
        data['favoris'] ??
        data['stats_favorites'] ??
        data['stats_favoris'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is List) return raw.length;
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  Future<void> _addMerchantToFavorites(DocumentReference enseigneRef) async {
    if (currentUserReference == null) {
      debugPrint(
        '[MERCHANT_PAGE_DEBUG] favorite_write_skipped_missing_user enseigneId=${enseigneRef.id}',
      );
      return;
    }
    final favoriteRef = FavoriteEnseignesRecord.createDoc(
      currentUserReference!,
      id: enseigneRef.id,
    );

    debugPrint(
        '[MERCHANT_PAGE_DEBUG] favorite_write_start enseigneId=${enseigneRef.id}');
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final favoriteSnap = await transaction.get(favoriteRef);
        if (favoriteSnap.exists) {
          return;
        }

        transaction.set(favoriteRef, {
          ...createFavoriteEnseignesRecordData(
            enseigneId: enseigneRef,
          ),
          ...mapToFirestore(
            {
              'added_at': FieldValue.serverTimestamp(),
            },
          ),
        });
      });
      debugPrint(
          '[MERCHANT_PAGE_DEBUG] favorite_write_success enseigneId=${enseigneRef.id}');
    } catch (error) {
      debugPrint(
        '[MERCHANT_PAGE_DEBUG] favorite_write_error enseigneId=${enseigneRef.id} error=$error',
      );
      rethrow;
    }
  }

  Future<void> _removeMerchantFromFavorites(
    FavoriteEnseignesRecord favoriteRecord,
  ) async {
    final enseigneId = favoriteRecord.enseigneId?.id ?? 'unknown';
    debugPrint(
        '[MERCHANT_PAGE_DEBUG] favorite_write_start enseigneId=$enseigneId');
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final favoriteSnap = await transaction.get(favoriteRecord.reference);
        if (!favoriteSnap.exists) {
          return;
        }

        transaction.delete(favoriteRecord.reference);
      });
      debugPrint(
          '[MERCHANT_PAGE_DEBUG] favorite_write_success enseigneId=$enseigneId');
    } catch (error) {
      debugPrint(
        '[MERCHANT_PAGE_DEBUG] favorite_write_error enseigneId=$enseigneId error=$error',
      );
      rethrow;
    }
  }

  bool _looksLikeUrl(String s) {
    final lower = s.toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('www.') ||
        lower.contains('://') ||
        lower.contains('.');
  }

  String _encodePossibleSpaces(String url) => Uri.encodeFull(url);

  String? _normalizeWebsiteUrl(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;

    // If it's already a URL (or looks like one), open exactly that.
    if (_looksLikeUrl(s)) {
      final withScheme = _ensureHttpScheme(s);
      return withScheme == null ? null : _encodePossibleSpaces(withScheme);
    }

    // Otherwise, treat it as a search query rather than inventing a URL.
    return Uri.https('www.google.com', '/search', {'q': s}).toString();
  }

  String? _normalizeFacebookUrl(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;

    final lower = s.toLowerCase();
    final looksLikeFacebookUrl = lower.contains('facebook.com') ||
        lower.contains('fb.com') ||
        lower.contains('fb.me');
    if (looksLikeFacebookUrl) {
      final withScheme = _ensureHttpScheme(s);
      return withScheme == null ? null : _encodePossibleSpaces(withScheme);
    }

    // If it's clearly a handle (no spaces), open profile. Otherwise search the exact text.
    final candidate = s.replaceAll('@', '').trim();
    if (candidate.isEmpty) return null;
    if (_hasWhitespace(candidate)) {
      return Uri.https('www.facebook.com', '/search/top', {'q': candidate})
          .toString();
    }
    final username = candidate.split('/').first.trim();
    if (username.isEmpty) return null;
    return Uri.https('www.facebook.com', '/$username').toString();
  }

  String? _normalizeInstagramUrl(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;

    final lower = s.toLowerCase();
    final looksLikeInstagramUrl =
        lower.contains('instagram.com') || lower.contains('instagr.am');
    if (looksLikeInstagramUrl) {
      final withScheme = _ensureHttpScheme(s);
      return withScheme == null ? null : _encodePossibleSpaces(withScheme);
    }

    final candidate = s.replaceAll('@', '').trim();
    if (candidate.isEmpty) return null;
    if (_hasWhitespace(candidate)) {
      return Uri.https(
              'www.instagram.com', '/explore/search/keyword/', {'q': candidate})
          .toString();
    }
    final username = candidate.split('/').first.trim();
    if (username.isEmpty) return null;
    return Uri.https('www.instagram.com', '/$username').toString();
  }

  String? _normalizeTwitterUrl(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;

    final lower = s.toLowerCase();
    final looksLikeTwitterUrl =
        lower.contains('twitter.com') || lower.contains('x.com');
    if (looksLikeTwitterUrl) {
      final withScheme = _ensureHttpScheme(s);
      return withScheme == null ? null : _encodePossibleSpaces(withScheme);
    }

    final candidate = s.replaceAll('@', '').trim();
    if (candidate.isEmpty) return null;
    if (_hasWhitespace(candidate)) {
      return Uri.https(
              'x.com', '/search', {'q': candidate, 'src': 'typed_query'})
          .toString();
    }
    final username = candidate.split('/').first.trim();
    if (username.isEmpty) return null;
    return Uri.https('x.com', '/$username').toString();
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => EnseigneDetailJoueurPageModel());

    // Initialize scroll controller for image carousel
    _model.imagesScrollController = ScrollController();
    _model.imagesScrollController?.addListener(() {
      if (_model.imagesScrollController!.hasClients) {
        final scrollPosition = _model.imagesScrollController!.offset;
        final screenWidth = MediaQuery.of(context).size.width;
        final imageWidth = (screenWidth - 40.0 - 32.0) +
            10.0; // (screen width - outer padding - card padding) + spacing
        final currentIndex = (scrollPosition / imageWidth).round();
        final clampedIndex = currentIndex.clamp(0, 1000);
        if (clampedIndex != _model.currentImageIndex) {
          safeSetState(() {
            _model.currentImageIndex = clampedIndex;
          });
        }
      }
    });

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'EnseigneDetailJoueurPage'});
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ongoingGamesFuture = _getOngoingGamesFuture();

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
            preferredSize: const Size.fromHeight(100.0),
            child: AppBar(
              backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
              automaticallyImplyLeading: false,
              actions: const [],
              flexibleSpace: FlexibleSpaceBar(
                title: Padding(
                  padding:
                      const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 14.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            0.0, 0.0, 12.0, 8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  12.0, 0.0, 0.0, 0.0),
                              child: Container(
                                width: 44.0,
                                height: 44.0,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.08),
                                      blurRadius: 10.0,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: FlutterFlowIconButton(
                                  borderColor: Colors.transparent,
                                  borderRadius: 30.0,
                                  borderWidth: 1.0,
                                  buttonSize: 44.0,
                                  icon: Icon(
                                    Icons.chevron_left_rounded,
                                    color: FlutterFlowTheme.of(context)
                                        .primaryText,
                                    size: 28.0,
                                  ),
                                  onPressed: () async {
                                    context.pop();
                                  },
                                ),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Image.asset(
                                  'assets/images/logo_D_secondaire.png',
                                  height: 34.0,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            Builder(
                              builder: (context) {
                                if (currentUserUid != '') {
                                  return StreamBuilder<
                                      List<FavoriteEnseignesRecord>>(
                                    stream: queryFavoriteEnseignesRecord(
                                      parent: currentUserReference,
                                      queryBuilder: (favoriteEnseignesRecord) =>
                                          favoriteEnseignesRecord.where(
                                        'enseigne_id',
                                        isEqualTo:
                                            widget.enseigneDoc?.reference,
                                      ),
                                      singleRecord: true,
                                    ),
                                    builder: (context, snapshot) {
                                      // Customize what your widget looks like when it's loading.
                                      if (!snapshot.hasData) {
                                        return const Center(
                                          child: SizedBox(
                                            width: 50.0,
                                            height: 50.0,
                                            child: ProxiplayLoadingLogo(
                                                size: 42.0),
                                          ),
                                        );
                                      }
                                      List<FavoriteEnseignesRecord>
                                          conditionalBuilderFavoriteEnseignesRecordList =
                                          snapshot.data!;
                                      final conditionalBuilderFavoriteEnseignesRecord =
                                          conditionalBuilderFavoriteEnseignesRecordList
                                                  .isNotEmpty
                                              ? conditionalBuilderFavoriteEnseignesRecordList
                                                  .first
                                              : null;

                                      return Builder(
                                        builder: (context) {
                                          if (!(conditionalBuilderFavoriteEnseignesRecord !=
                                              null)) {
                                            return FlutterFlowIconButton(
                                              borderRadius: 8.0,
                                              buttonSize: 40.0,
                                              icon: Icon(
                                                Icons.favorite_border_rounded,
                                                color: const Color(0xFFA0134D),
                                                size: 24.0,
                                              ),
                                              onPressed: () async {
                                                final enseigneRef = widget
                                                    .enseigneDoc?.reference;
                                                debugPrint(
                                                  '[MERCHANT_PAGE_DEBUG] favorite_tap enseigneId=${enseigneRef?.id ?? "unknown"}',
                                                );
                                                if (enseigneRef == null) {
                                                  return;
                                                }
                                                await _addMerchantToFavorites(enseigneRef);
                                                safeSetState(() => _model
                                                        .firestoreRequestCompleter =
                                                    null);
                                                await _model
                                                    .waitForFirestoreRequestCompleted();
                                              },
                                            );
                                          } else {
                                            return FlutterFlowIconButton(
                                              borderRadius: 8.0,
                                              buttonSize: 40.0,
                                              icon: Icon(
                                                Icons.favorite_rounded,
                                                color: const Color(0xFFA0134D),
                                                size: 24.0,
                                              ),
                                              onPressed: () async {
                                                debugPrint(
                                                  '[MERCHANT_PAGE_DEBUG] favorite_tap enseigneId=${conditionalBuilderFavoriteEnseignesRecord.enseigneId?.id ?? "unknown"}',
                                                );
                                                await _removeMerchantFromFavorites(
                                                  conditionalBuilderFavoriteEnseignesRecord,
                                                );
                                              },
                                            );
                                          }
                                        },
                                      );
                                    },
                                  );
                                } else {
                                  return Container(
                                    decoration: const BoxDecoration(),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
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
              ),
              elevation: 0.0,
            ),
          ),
          body: SafeArea(
            top: true,
            child: Container(
              decoration: const BoxDecoration(
                  // gradient: LinearGradient(
                  //   begin: Alignment.topCenter,
                  //   end: Alignment.bottomCenter,
                  //   colors: [
                  //     Color(0xFFF4F7FF),
                  //     Color(0xFFEFF2FB),
                  // ],
                  // ),
                  ),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          20.0, 0.0, 20.0, 0.0),
                      child: SingleChildScrollView(
                        primary: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              // decoration: BoxDecoration(
                              //   color: Colors.white,
                              //   borderRadius: BorderRadius.circular(20.0),
                              //   boxShadow: [
                              //     BoxShadow(
                              //       color: Colors.black.withOpacity(0.06),
                              //       blurRadius: 14.0,
                              //       offset: Offset(0, 4),
                              //     ),
                              //   ],
                              // ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.enseigneDoc!.name,
                                      style: FlutterFlowTheme.of(context)
                                          .headlineSmall
                                          .override(
                                            font: GoogleFonts.interTight(
                                              fontWeight: FontWeight.w700,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .headlineSmall
                                                      .fontStyle,
                                            ),
                                            color: const Color(0xFF23255E),
                                            letterSpacing: 0.0,
                                            fontWeight: FontWeight.w700,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .headlineSmall
                                                    .fontStyle,
                                          ),
                                    ),
                                    if (!functions.checkValueIsEmpty(
                                        widget.enseigneDoc!.city))
                                      Padding(
                                        padding: const EdgeInsetsDirectional
                                            .fromSTEB(0.0, 6.0, 0.0, 0.0),
                                        child: Text(
                                          widget.enseigneDoc!.city,
                                          style: FlutterFlowTheme.of(context)
                                              .labelLarge
                                              .override(
                                                font: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w600,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .labelLarge
                                                          .fontStyle,
                                                ),
                                                color: const Color(0xFF6B70A7),
                                                letterSpacing: 0.0,
                                                fontWeight: FontWeight.w600,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .labelLarge
                                                        .fontStyle,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20.0),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.06),
                                    blurRadius: 14.0,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    16.0, 16.0, 16.0, 16.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    FutureBuilder<List<ImagesRecord>>(
                                      future: queryImagesRecordOnce(
                                        parent: widget.enseigneDoc?.reference,
                                        limit: 5,
                                      ),
                                      builder: (context, snapshot) {
                                        // Customize what your widget looks like when it's loading.
                                        if (!snapshot.hasData) {
                                          return const Center(
                                            child: SizedBox(
                                              width: 50.0,
                                              height: 50.0,
                                              child: ProxiplayLoadingLogo(
                                                  size: 42.0),
                                            ),
                                          );
                                        }
                                        List<ImagesRecord> rowImagesRecordList =
                                            snapshot.data!;

                                        final descriptionText =
                                            widget.enseigneDoc!.description;
                                        final hasDescription = !functions
                                            .checkValueIsEmpty(descriptionText);
                                        final hasImages =
                                            rowImagesRecordList.isNotEmpty;

                                        if (rowImagesRecordList.length == 1 &&
                                            hasDescription) {
                                          final rowImagesRecord =
                                              rowImagesRecordList.first;
                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: double.infinity,
                                                height: 200.0,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          20.0),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withOpacity(0.10),
                                                      blurRadius: 16.0,
                                                      offset:
                                                          const Offset(0, 4),
                                                    ),
                                                  ],
                                                ),
                                                child: InkWell(
                                                  splashColor:
                                                      Colors.transparent,
                                                  focusColor:
                                                      Colors.transparent,
                                                  hoverColor:
                                                      Colors.transparent,
                                                  highlightColor:
                                                      Colors.transparent,
                                                  onTap: () async {
                                                    await Navigator.push(
                                                      context,
                                                      PageTransition(
                                                        type: PageTransitionType
                                                            .fade,
                                                        child:
                                                            FlutterFlowExpandedImageView(
                                                          image:
                                                              ProxiplayNetworkImage(
                                                            imageUrl:
                                                                rowImagesRecord
                                                                    .url,
                                                            fit: BoxFit.contain,
                                                          ),
                                                          allowRotation: false,
                                                          tag: rowImagesRecord
                                                              .url,
                                                          useHeroAnimation:
                                                              true,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  child: Hero(
                                                    tag: rowImagesRecord.url,
                                                    transitionOnUserGestures:
                                                        true,
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20.0),
                                                      child:
                                                          ProxiplayNetworkImage(
                                                        imageUrl:
                                                            rowImagesRecord.url,
                                                        width: double.infinity,
                                                        height: 200.0,
                                                        fit: BoxFit.cover,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 16.0),
                                              Text(
                                                descriptionText,
                                                style: GoogleFonts.inter(
                                                  fontSize: 16.0,
                                                  height: 1.6,
                                                  fontWeight: FontWeight.w400,
                                                  color:
                                                      const Color(0xFF2D3250),
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                            ],
                                          );
                                        }

                                        final screenWidth =
                                            MediaQuery.of(context).size.width;
                                        // Account for outer padding (20px each side) and card padding (16px each side)
                                        final imageWidth =
                                            screenWidth - 40.0 - 32.0;

                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (hasImages)
                                              Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SingleChildScrollView(
                                                    controller: _model
                                                        .imagesScrollController,
                                                    scrollDirection:
                                                        Axis.horizontal,
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.max,
                                                      children: List.generate(
                                                          rowImagesRecordList
                                                              .length,
                                                          (rowIndex) {
                                                        final rowImagesRecord =
                                                            rowImagesRecordList[
                                                                rowIndex];
                                                        return Container(
                                                          width: imageWidth,
                                                          height: 200.0,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors.white,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        20.0),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: Colors
                                                                    .black
                                                                    .withOpacity(
                                                                        0.10),
                                                                blurRadius:
                                                                    16.0,
                                                                offset:
                                                                    const Offset(
                                                                        0, 4),
                                                              ),
                                                            ],
                                                          ),
                                                          child: InkWell(
                                                            splashColor: Colors
                                                                .transparent,
                                                            focusColor: Colors
                                                                .transparent,
                                                            hoverColor: Colors
                                                                .transparent,
                                                            highlightColor:
                                                                Colors
                                                                    .transparent,
                                                            onTap: () async {
                                                              await Navigator
                                                                  .push(
                                                                context,
                                                                PageTransition(
                                                                  type:
                                                                      PageTransitionType
                                                                          .fade,
                                                                  child:
                                                                      FlutterFlowExpandedImageView(
                                                                    image: Image
                                                                        .network(
                                                                      rowImagesRecord
                                                                          .url,
                                                                      fit: BoxFit
                                                                          .contain,
                                                                    ),
                                                                    allowRotation:
                                                                        false,
                                                                    tag: rowImagesRecord
                                                                        .url,
                                                                    useHeroAnimation:
                                                                        true,
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                            child: Hero(
                                                              tag:
                                                                  rowImagesRecord
                                                                      .url,
                                                              transitionOnUserGestures:
                                                                  true,
                                                              child: ClipRRect(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            20.0),
                                                                child:
                                                                    ProxiplayNetworkImage(
                                                                  imageUrl:
                                                                      rowImagesRecord
                                                                          .url,
                                                                  width:
                                                                      imageWidth,
                                                                  height: 200.0,
                                                                  fit: BoxFit
                                                                      .cover,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      }).divide(const SizedBox(
                                                          width: 10.0)),
                                                    ),
                                                  ),
                                                  if (rowImagesRecordList
                                                          .length >
                                                      1)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsetsDirectional
                                                              .fromSTEB(0.0,
                                                              12.0, 0.0, 0.0),
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: List.generate(
                                                          rowImagesRecordList
                                                              .length,
                                                          (index) {
                                                            final currentIndex = _model
                                                                .currentImageIndex
                                                                .clamp(
                                                                    0,
                                                                    rowImagesRecordList
                                                                            .length -
                                                                        1);
                                                            final isActive =
                                                                index ==
                                                                    currentIndex;
                                                            return Container(
                                                              width: isActive
                                                                  ? 8.0
                                                                  : 6.0,
                                                              height: isActive
                                                                  ? 8.0
                                                                  : 6.0,
                                                              margin:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          4.0),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: isActive
                                                                    ? const Color(
                                                                        0xFF6B70A7)
                                                                    : const Color(
                                                                            0xFF6B70A7)
                                                                        .withOpacity(
                                                                            0.3),
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            if (hasDescription)
                                              Padding(
                                                padding: EdgeInsetsDirectional
                                                    .fromSTEB(
                                                        0.0,
                                                        hasImages ? 16.0 : 0.0,
                                                        0.0,
                                                        0.0),
                                                child: Text(
                                                  descriptionText,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 16.0,
                                                    height: 1.6,
                                                    fontWeight: FontWeight.w400,
                                                    color:
                                                        const Color(0xFF2D3250),
                                                    letterSpacing: 0.2,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              width: double.infinity,
                              // decoration: BoxDecoration(
                              //   color: Colors.white,
                              //   borderRadius: BorderRadius.circular(20.0),
                              //   boxShadow: [
                              //     BoxShadow(
                              //       color: Colors.black.withOpacity(0.06),
                              //       blurRadius: 14.0,
                              //       offset: Offset(0, 4),
                              //     ),
                              //   ],
                              // ),
                              child: Padding(
                                padding: const EdgeInsets.all(5.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.max,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(14.0),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(14.0),
                                        border: Border.all(
                                          color: const Color(0xFFE3E8F7),
                                          width: 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 36.0,
                                            height: 36.0,
                                            decoration: BoxDecoration(
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .primary
                                                      .withOpacity(0.12),
                                              borderRadius:
                                                  BorderRadius.circular(10.0),
                                            ),
                                            child: Icon(
                                              Icons.place_rounded,
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .primary,
                                              size: 20.0,
                                            ),
                                          ),
                                          const SizedBox(width: 12.0),

                                          Expanded(
                                            child: InkWell(
                                              onTap: () async {
                                                final city = widget
                                                    .enseigneDoc?.city
                                                    .trim();
                                                final address = widget
                                                    .enseigneDoc?.address
                                                    .trim();

                                                if (city == null ||
                                                    address == null) return;
                                                if (city.isEmpty ||
                                                    address.isEmpty) return;

                                                final fullAddress =
                                                    '$address, $city';

                                                // Encode for URL safety
                                                final encodedAddress =
                                                    Uri.encodeComponent(
                                                        fullAddress);

                                                final mapUrl =
                                                    "https://www.google.com/maps/search/?api=1&query=$encodedAddress";

                                                await launchURL(mapUrl);
                                              },
                                              child: Text(
                                                '${widget.enseigneDoc?.city} \u00B7 ${widget.enseigneDoc?.address}',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.inter(
                                                  fontSize: 15.0,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      const Color(0xFF3B3F74),
                                                ),
                                              ),
                                            ),
                                          ),

                                          // Expanded(
                                          //   child: Text(
                                          //     '${widget!.enseigneDoc?.city} \u00B7 ${widget!.enseigneDoc?.address}',
                                          //     maxLines: 2,
                                          //     overflow: TextOverflow.ellipsis,
                                          //     style: GoogleFonts.inter(
                                          //       fontSize: 15.0,
                                          //       fontWeight: FontWeight.w600,
                                          //       color: Color(0xFF3B3F74),
                                          //     ),
                                          //   ),
                                          // ),
                                        ],
                                      ),
                                    ),
                                    InkWell(
                                      splashColor: Colors.transparent,
                                      focusColor: Colors.transparent,
                                      hoverColor: Colors.transparent,
                                      highlightColor: Colors.transparent,
                                      onTap: () async {
                                        await launchURL(
                                            'tel:${widget.enseigneDoc!.phoneNumber}');
                                      },
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(14.0),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(14.0),
                                          border: Border.all(
                                            color: const Color(0xFFE3E8F7),
                                            width: 1.0,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 36.0,
                                              height: 36.0,
                                              decoration: BoxDecoration(
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primary
                                                        .withOpacity(0.12),
                                                borderRadius:
                                                    BorderRadius.circular(10.0),
                                              ),
                                              child: Icon(
                                                Icons.phone_rounded,
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primary,
                                                size: 20.0,
                                              ),
                                            ),
                                            const SizedBox(width: 12.0),
                                            Expanded(
                                              child: Text(
                                                widget.enseigneDoc!.phoneNumber,
                                                style: GoogleFonts.inter(
                                                  fontSize: 15.0,
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      const Color(0xFF3B3F74),
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              Icons.call_rounded,
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .primary,
                                              size: 18.0,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ]
                                      .divide(const SizedBox(height: 12.0))
                                      .around(const SizedBox(height: 6.0)),
                                ),
                              ),
                            ),
                            if (!functions.checkValueIsEmpty(
                                    widget.enseigneDoc!.facebookLink) ||
                                !functions.checkValueIsEmpty(
                                    widget.enseigneDoc!.twitterLink) ||
                                !functions.checkValueIsEmpty(
                                    widget.enseigneDoc!.siteWebUrl) ||
                                !functions.checkValueIsEmpty(
                                    widget.enseigneDoc!.instagramLink))
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20.0),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 14.0,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.max,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                            spacing: 8.0,
                                            runSpacing: 8.0,
                                            alignment: WrapAlignment.center,
                                            runAlignment: WrapAlignment.center,
                                            children: [
                                              if (!functions.checkValueIsEmpty(
                                                  widget
                                                      .enseigneDoc!.siteWebUrl))
                                                InkWell(
                                                  splashColor:
                                                      Colors.transparent,
                                                  focusColor:
                                                      Colors.transparent,
                                                  hoverColor:
                                                      Colors.transparent,
                                                  highlightColor:
                                                      Colors.transparent,
                                                  onTap: () async {
                                                    final link =
                                                        _normalizeWebsiteUrl(
                                                            widget.enseigneDoc
                                                                ?.siteWebUrl);
                                                    if (link == null) return;
                                                    await launchURL(link);
                                                  },
                                                  child: Container(
                                                    width: 48.0,
                                                    height: 48.0,
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              24.0),
                                                      border: Border.all(
                                                        color: Colors.black87,
                                                        width: 1.4,
                                                      ),
                                                    ),
                                                    alignment: Alignment.center,
                                                    child: const Icon(
                                                      Icons.language_rounded,
                                                      color: Colors.black87,
                                                      size: 24.0,
                                                    ),
                                                  ),
                                                  // child: Container(
                                                  //   width: double.infinity,
                                                  //   padding: EdgeInsets.all(14.0),
                                                  //   decoration: BoxDecoration(
                                                  //     color: Color(0xFFF7FAFF),
                                                  //     borderRadius:
                                                  //         BorderRadius.circular(14.0),
                                                  //     border: Border.all(
                                                  //       color: Color(0xFFE3E8F7),
                                                  //       width: 1.0,
                                                  //     ),
                                                  //   ),
                                                  //   child: Row(
                                                  //     children: [
                                                  //       Container(
                                                  //         width: 36.0,
                                                  //         height: 36.0,
                                                  //         decoration: BoxDecoration(
                                                  //           color: FlutterFlowTheme.of(
                                                  //                   context)
                                                  //               .primary
                                                  //               .withOpacity(0.12),
                                                  //           borderRadius:
                                                  //               BorderRadius.circular(
                                                  //                   10.0),
                                                  //         ),
                                                  //         child: Icon(
                                                  //           Icons.language_rounded,
                                                  //           color: FlutterFlowTheme.of(
                                                  //                   context)
                                                  //               .primary,
                                                  //           size: 20.0,
                                                  //         ),
                                                  //       ),
                                                  //       SizedBox(width: 10.0),
                                                  //       Expanded(
                                                  //         child: Text(
                                                  //           widget!.enseigneDoc!
                                                  //               .siteWebUrl,
                                                  //           maxLines: 1,
                                                  //           overflow:
                                                  //               TextOverflow.ellipsis,
                                                  //           style: GoogleFonts.inter(
                                                  //             fontSize: 15.0,
                                                  //             fontWeight:
                                                  //                 FontWeight.w600,
                                                  //             color: Color(0xFF3B3F74),
                                                  //           ),
                                                  //         ),
                                                  //       ),
                                                  //       Icon(
                                                  //         Icons.open_in_new_rounded,
                                                  //         color: FlutterFlowTheme.of(
                                                  //                 context)
                                                  //             .primary,
                                                  //         size: 18.0,
                                                  //       ),
                                                  //     ],
                                                  //   ),
                                                  // ),
                                                ),
                                              if (!functions.checkValueIsEmpty(
                                                  widget.enseigneDoc!
                                                      .facebookLink))
                                                InkWell(
                                                  splashColor:
                                                      Colors.transparent,
                                                  focusColor:
                                                      Colors.transparent,
                                                  hoverColor:
                                                      Colors.transparent,
                                                  highlightColor:
                                                      Colors.transparent,
                                                  onTap: () async {
                                                    final link =
                                                        _normalizeFacebookUrl(
                                                            widget.enseigneDoc
                                                                ?.facebookLink);
                                                    if (link == null) {
                                                      return;
                                                    }
                                                    await launchURL(link);
                                                  },
                                                  child: Container(
                                                    width: 48.0,
                                                    height: 48.0,
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                          0xFF4267B2),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              24.0),
                                                    ),
                                                    alignment: Alignment.center,
                                                    child: const FaIcon(
                                                      FontAwesomeIcons
                                                          .facebookF,
                                                      color: Colors.white,
                                                      size: 24.0,
                                                    ),
                                                  ),
                                                ),
                                              // instagram link
                                              if (!functions.checkValueIsEmpty(
                                                  widget.enseigneDoc!
                                                      .instagramLink))
                                                InkWell(
                                                  splashColor:
                                                      Colors.transparent,
                                                  focusColor:
                                                      Colors.transparent,
                                                  hoverColor:
                                                      Colors.transparent,
                                                  highlightColor:
                                                      Colors.transparent,
                                                  onTap: () async {
                                                    final link =
                                                        _normalizeInstagramUrl(
                                                            widget.enseigneDoc
                                                                ?.instagramLink);
                                                    if (link == null) {
                                                      return;
                                                    }
                                                    await launchURL(link);
                                                    // await launchURL(widget!
                                                    //     .enseigneDoc!
                                                    //     .instagramLink);
                                                  },
                                                  child: Container(
                                                    width: 48.0,
                                                    height: 48.0,
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                      gradient:
                                                          const LinearGradient(
                                                        begin: Alignment(
                                                            -1.0, -1.0),
                                                        end:
                                                            Alignment(1.0, 1.0),
                                                        colors: [
                                                          Color(0xFFFEDA75),
                                                          Color(0xFFFA7E1E),
                                                          Color(0xFFD62976),
                                                          Color(0xFF962FBF),
                                                          Color(0xFF4F5BD5),
                                                        ],
                                                      ),
                                                    ),
                                                    alignment: Alignment.center,
                                                    child: const FaIcon(
                                                      FontAwesomeIcons
                                                          .instagram,
                                                      color: Colors.white,
                                                      size: 24.0,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),

                                          const SizedBox(height: 1.0),

                                          // Social Media Links
                                          Wrap(
                                            spacing: 8.0,
                                            runSpacing: 8.0,
                                            alignment: WrapAlignment.center,
                                            runAlignment: WrapAlignment.center,
                                            children: [
                                              // Twitter
                                              if (!functions.checkValueIsEmpty(
                                                  widget.enseigneDoc!
                                                      .twitterLink))
                                                InkWell(
                                                  splashColor:
                                                      Colors.transparent,
                                                  focusColor:
                                                      Colors.transparent,
                                                  hoverColor:
                                                      Colors.transparent,
                                                  highlightColor:
                                                      Colors.transparent,
                                                  onTap: () async {
                                                    final link =
                                                        _normalizeTwitterUrl(
                                                            widget.enseigneDoc
                                                                ?.twitterLink);
                                                    if (link == null) {
                                                      return;
                                                    }
                                                    await launchURL(link);
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 12.0,
                                                        vertical: 8.0),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                              0xFF1DA1F2)
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const FaIcon(
                                                          FontAwesomeIcons
                                                              .twitter,
                                                          color:
                                                              Color(0xFF1DA1F2),
                                                          size: 18.0,
                                                        ),
                                                        const SizedBox(
                                                            width: 6.0),
                                                        Text(
                                                          'Twitter',
                                                          style:
                                                              GoogleFonts.inter(
                                                            fontSize: 13.0,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: const Color(
                                                                0xFF1DA1F2),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ])),
                              ),
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20.0),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.06),
                                    blurRadius: 14.0,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    16.0, 16.0, 16.0, 16.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    Text(
                                      'Horaires d\'ouverture',
                                      style: FlutterFlowTheme.of(context)
                                          .headlineSmall
                                          .override(
                                            font: GoogleFonts.interTight(
                                              fontWeight:
                                                  FlutterFlowTheme.of(context)
                                                      .headlineSmall
                                                      .fontWeight,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .headlineSmall
                                                      .fontStyle,
                                            ),
                                            fontSize: 20.0,
                                            letterSpacing: 0.0,
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .headlineSmall
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .headlineSmall
                                                    .fontStyle,
                                          ),
                                    ),
                                    FutureBuilder<List<HorairesRecord>>(
                                      future: (_model
                                                  .firestoreRequestCompleter ??=
                                              Completer<List<HorairesRecord>>()
                                                ..complete(
                                                    queryHorairesRecordOnce(
                                                  parent: widget
                                                      .enseigneDoc?.reference,
                                                  queryBuilder:
                                                      (horairesRecord) =>
                                                          horairesRecord.orderBy(
                                                              'created_time'),
                                                )))
                                          .future,
                                      builder: (context, snapshot) {
                                        // Customize what your widget looks like when it's loading.
                                        if (!snapshot.hasData) {
                                          return const Center(
                                            child: SizedBox(
                                              width: 50.0,
                                              height: 50.0,
                                              child: ProxiplayLoadingLogo(
                                                  size: 42.0),
                                            ),
                                          );
                                        }
                                        List<HorairesRecord>
                                            columnHorairesRecordList =
                                            List.of(snapshot.data!)
                                              ..sort(
                                                (a, b) => _daySortIndex(a)
                                                    .compareTo(
                                                        _daySortIndex(b)),
                                              );

                                        return Column(
                                          mainAxisSize: MainAxisSize.max,
                                          children: List.generate(
                                              columnHorairesRecordList.length,
                                              (columnIndex) {
                                            final columnHorairesRecord =
                                                columnHorairesRecordList[
                                                    columnIndex];
                                            return Padding(
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                      8.0, 0.0, 8.0, 0.0),
                                              child: Container(
                                                width: double.infinity,
                                                decoration: BoxDecoration(
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .secondaryBackground,
                                                ),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsetsDirectional
                                                          .fromSTEB(
                                                          8.0, 6.0, 8.0, 0.0),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(
                                                        columnHorairesRecord
                                                            .day!.name,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodyLarge
                                                                .override(
                                                                  font:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodyLarge
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodyLarge
                                                                        .fontStyle,
                                                                  ),
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyLarge
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyLarge
                                                                      .fontStyle,
                                                                ),
                                                      ),
                                                      Builder(
                                                        builder: (context) {
                                                          if (columnHorairesRecord
                                                              .isOpen) {
                                                            return Builder(
                                                              builder:
                                                                  (context) {
                                                                if (!columnHorairesRecord
                                                                    .isFullDay) {
                                                                  return Text(
                                                                    '${dateTimeFormat(
                                                                      "Hm",
                                                                      columnHorairesRecord
                                                                          .openingDay,
                                                                      locale: FFLocalizations.of(
                                                                              context)
                                                                          .languageCode,
                                                                    )} - ${dateTimeFormat(
                                                                      "Hm",
                                                                      columnHorairesRecord
                                                                          .closingDay,
                                                                      locale: FFLocalizations.of(
                                                                              context)
                                                                          .languageCode,
                                                                    )}',
                                                                    style: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodyMedium
                                                                        .override(
                                                                          font:
                                                                              GoogleFonts.inter(
                                                                            fontWeight:
                                                                                FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                            fontStyle:
                                                                                FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                          ),
                                                                          letterSpacing:
                                                                              0.0,
                                                                          fontWeight: FlutterFlowTheme.of(context)
                                                                              .bodyMedium
                                                                              .fontWeight,
                                                                          fontStyle: FlutterFlowTheme.of(context)
                                                                              .bodyMedium
                                                                              .fontStyle,
                                                                        ),
                                                                  );
                                                                } else {
                                                                  return Column(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .max,
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .end,
                                                                    children: [
                                                                      Text(
                                                                        '${dateTimeFormat(
                                                                          "Hm",
                                                                          columnHorairesRecord
                                                                              .openingMorning,
                                                                          locale:
                                                                              FFLocalizations.of(context).languageCode,
                                                                        )} - ${dateTimeFormat(
                                                                          "Hm",
                                                                          columnHorairesRecord
                                                                              .closingMorning,
                                                                          locale:
                                                                              FFLocalizations.of(context).languageCode,
                                                                        )}',
                                                                        style: FlutterFlowTheme.of(context)
                                                                            .bodyMedium
                                                                            .override(
                                                                              font: GoogleFonts.inter(
                                                                                fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                                fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                              ),
                                                                              letterSpacing: 0.0,
                                                                              fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                            ),
                                                                      ),
                                                                      Text(
                                                                        '${dateTimeFormat(
                                                                          "Hm",
                                                                          columnHorairesRecord
                                                                              .openingAfternoon,
                                                                          locale:
                                                                              FFLocalizations.of(context).languageCode,
                                                                        )} - ${dateTimeFormat(
                                                                          "Hm",
                                                                          columnHorairesRecord
                                                                              .closingAfternoon,
                                                                          locale:
                                                                              FFLocalizations.of(context).languageCode,
                                                                        )}',
                                                                        style: FlutterFlowTheme.of(context)
                                                                            .bodyMedium
                                                                            .override(
                                                                              font: GoogleFonts.inter(
                                                                                fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                                fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                              ),
                                                                              letterSpacing: 0.0,
                                                                              fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                            ),
                                                                      ),
                                                                    ],
                                                                  );
                                                                }
                                                              },
                                                            );
                                                          } else {
                                                            return Text(
                                                              'Ferm\u00E9',
                                                              style: FlutterFlowTheme
                                                                      .of(context)
                                                                  .bodyMedium
                                                                  .override(
                                                                    font: GoogleFonts
                                                                        .inter(
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodyMedium
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodyMedium
                                                                          .fontStyle,
                                                                    ),
                                                                    letterSpacing:
                                                                        0.0,
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodyMedium
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodyMedium
                                                                        .fontStyle,
                                                                  ),
                                                            );
                                                          }
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                        );
                                      },
                                    ),
                                  ].divide(const SizedBox(height: 16.0)),
                                ),
                              ),
                            ),
                            Align(
                              alignment: const AlignmentDirectional(-1.0, 0.0),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    0.0, 20.0, 0.0, 0.0),
                                child: Text(
                                  'JEUX EN COURS',
                                  textAlign: TextAlign.center,
                                  style: FlutterFlowTheme.of(context)
                                      .titleMedium
                                      .override(
                                        font: GoogleFonts.interTight(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .titleMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .titleMedium
                                                  .fontStyle,
                                        ),
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .titleMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .titleMedium
                                            .fontStyle,
                                      ),
                                ),
                              ),
                            ),
                            Container(
                              height: 500.0,
                              decoration: const BoxDecoration(),
                              child: Builder(
                                builder: (context) {
                                  if (currentUserUid != '') {
                                    return Builder(
                                      builder: (context) {
                                        if (isGuestOrAnonymous ||
                                            ((currentUserDocument?.birthday !=
                                                    null) &&
                                                functions.isAdult(
                                                    currentUserDocument!
                                                        .birthday!))) {
                                          return FutureBuilder<
                                              List<GamesRecord>>(
                                            future: ongoingGamesFuture,
                                            builder: (context, snapshot) {
                                              // Customize what your widget looks like when it's loading.
                                              if (!snapshot.hasData) {
                                                return const Center(
                                                  child: SizedBox(
                                                    width: 50.0,
                                                    height: 50.0,
                                                    child: ProxiplayLoadingLogo(
                                                        size: 42.0),
                                                  ),
                                                );
                                              }
                                              List<GamesRecord>
                                                  listViewGamesRecordList =
                                                  snapshot.data!
                                                      .where(
                                                          _isGameVisibleForPlayer)
                                                      .toList();
                                              if (listViewGamesRecordList
                                                  .isEmpty) {
                                                return const ListEmptyComponentWidget(
                                                  title: 'Liste vide',
                                                  description:
                                                      'Aucun jeux en cours',
                                                );
                                              }

                                              return ListView.separated(
                                                padding: EdgeInsets.zero,
                                                primary: false,
                                                scrollDirection: Axis.vertical,
                                                itemCount:
                                                    listViewGamesRecordList
                                                        .length,
                                                separatorBuilder: (_, __) =>
                                                    const SizedBox(
                                                        height: 10.0),
                                                itemBuilder:
                                                    (context, listViewIndex) {
                                                  final listViewGamesRecord =
                                                      listViewGamesRecordList[
                                                          listViewIndex];
                                                  return Material(
                                                    color: Colors.transparent,
                                                    elevation: 1.0,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20.0),
                                                    ),
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: FlutterFlowTheme
                                                                .of(context)
                                                            .secondaryBackground,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20.0),
                                                      ),
                                                      child: Builder(
                                                        builder: (context) {
                                                          return InkWell(
                                                            splashColor: Colors
                                                                .transparent,
                                                            focusColor: Colors
                                                                .transparent,
                                                            hoverColor: Colors
                                                                .transparent,
                                                            highlightColor:
                                                                Colors
                                                                    .transparent,
                                                            onTap: () async {
                                                            debugPrint('[MERCHANT_PAGE_DEBUG] game_card_tap gameId=${listViewGamesRecord.reference.id}');
                                                            debugPrint('[MERCHANT_PAGE_DEBUG] navigate_to_game gameId=${listViewGamesRecord.reference.id}');
                                                            context.pushNamed(
                                                                JeuDetailJoueurPageWidget
                                                                    .routeName,
                                                                queryParameters:
                                                                    {
                                                                  'gameDoc':
                                                                      serializeParam(
                                                                    listViewGamesRecord,
                                                                    ParamType
                                                                        .Document,
                                                                  ),
                                                                  'enseigneDoc':
                                                                      serializeParam(
                                                                    widget
                                                                        .enseigneDoc,
                                                                    ParamType
                                                                        .Document,
                                                                  ),
                                                                }.withoutNulls,
                                                                extra: <String,
                                                                    dynamic>{
                                                                  'gameDoc':
                                                                      listViewGamesRecord,
                                                                  'enseigneDoc':
                                                                      widget
                                                                          .enseigneDoc,
                                                                  kTransitionInfoKey:
                                                                      const TransitionInfo(
                                                                    hasTransition:
                                                                        true,
                                                                    transitionType:
                                                                        PageTransitionType
                                                                            .fade,
                                                                  ),
                                                                },
                                                              );
                                                            },
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .max,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .center,
                                                              children: [
                                                                Expanded(
                                                                  flex: 1,
                                                                  child:
                                                                      Container(
                                                                    height:
                                                                        150.0,
                                                                    decoration:
                                                                        const BoxDecoration(),
                                                                    child:
                                                                        ClipRRect(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              8.0),
                                                                      child: Image
                                                                          .network(
                                                                        listViewGamesRecord
                                                                            .photo,
                                                                        fit: BoxFit
                                                                            .fill,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                                Expanded(
                                                                  flex: 2,
                                                                  child:
                                                                      Padding(
                                                                    padding: const EdgeInsetsDirectional
                                                                        .fromSTEB(
                                                                        10.0,
                                                                        0.0,
                                                                        0.0,
                                                                        0.0),
                                                                    child:
                                                                        Column(
                                                                      mainAxisSize:
                                                                          MainAxisSize
                                                                              .max,
                                                                      mainAxisAlignment:
                                                                          MainAxisAlignment
                                                                              .start,
                                                                      crossAxisAlignment:
                                                                          CrossAxisAlignment
                                                                              .start,
                                                                      children:
                                                                          [
                                                                        SingleChildScrollView(
                                                                          scrollDirection:
                                                                              Axis.horizontal,
                                                                          child:
                                                                              Row(
                                                                            mainAxisSize:
                                                                                MainAxisSize.max,
                                                                            children: [
                                                                              Text(
                                                                                listViewGamesRecord.name,
                                                                                style: FlutterFlowTheme.of(context).bodyMedium.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FontWeight.w600,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                                      ),
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FontWeight.w600,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                                    ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                        Column(
                                                                          mainAxisSize:
                                                                              MainAxisSize.max,
                                                                          mainAxisAlignment:
                                                                              MainAxisAlignment.spaceEvenly,
                                                                          children:
                                                                              [
                                                                            Row(
                                                                              mainAxisSize: MainAxisSize.max,
                                                                              children: [
                                                                                Icon(
                                                                                  Icons.store_sharp,
                                                                                  color: FlutterFlowTheme.of(context).primaryText,
                                                                                  size: 18.0,
                                                                                ),
                                                                                Text(
                                                                                  widget.enseigneDoc?.name ?? '',
                                                                                  style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                        font: GoogleFonts.inter(
                                                                                          fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                          fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                        ),
                                                                                        letterSpacing: 0.0,
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                            Row(
                                                                              mainAxisSize: MainAxisSize.max,
                                                                              children: [
                                                                                Icon(
                                                                                  Icons.location_on_sharp,
                                                                                  color: FlutterFlowTheme.of(context).primaryText,
                                                                                  size: 18.0,
                                                                                ),
                                                                                Text(
                                                                                  widget.enseigneDoc?.city ?? '',
                                                                                  style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                        font: GoogleFonts.inter(
                                                                                          fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                          fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                        ),
                                                                                        letterSpacing: 0.0,
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                            Row(
                                                                              mainAxisSize: MainAxisSize.max,
                                                                              children: [
                                                                                FaIcon(
                                                                                  FontAwesomeIcons.piggyBank,
                                                                                  color: FlutterFlowTheme.of(context).primaryText,
                                                                                  size: 18.0,
                                                                                ),
                                                                                Text(
                                                                                  ' Valeur : ',
                                                                                  style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                        font: GoogleFonts.inter(
                                                                                          fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                          fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                        ),
                                                                                        letterSpacing: 0.0,
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                ),
                                                                                Text(
                                                                                  _formatPrizeLabel(listViewGamesRecord),
                                                                                  style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                        font: GoogleFonts.inter(
                                                                                          fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                          fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                        ),
                                                                                        letterSpacing: 0.0,
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                            Row(
                                                                              mainAxisSize: MainAxisSize.max,
                                                                              children: [
                                                                                Icon(
                                                                                  Icons.calendar_month,
                                                                                  color: FlutterFlowTheme.of(context).primaryText,
                                                                                  size: 18.0,
                                                                                ),
                                                                                Text(
                                                                                  ' Valable jusqu\'au : ',
                                                                                  style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                        font: GoogleFonts.inter(
                                                                                          fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                          fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                        ),
                                                                                        letterSpacing: 0.0,
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                ),
                                                                                Text(
                                                                                  dateTimeFormat(
                                                                                    "d/M/y",
                                                                                    listViewGamesRecord.endDate!,
                                                                                    locale: FFLocalizations.of(context).languageCode,
                                                                                  ),
                                                                                  style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                        font: GoogleFonts.inter(
                                                                                          fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                          fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                        ),
                                                                                        letterSpacing: 0.0,
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                          ].divide(const SizedBox(height: 5.0)),
                                                                        ),
                                                                      ].divide(const SizedBox(
                                                                              height: 5.0)),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                          );
                                        } else {
                                          return FutureBuilder<
                                              List<GamesRecord>>(
                                            future: ongoingGamesFuture,
                                            builder: (context, snapshot) {
                                              // Customize what your widget looks like when it's loading.
                                              if (!snapshot.hasData) {
                                                return const Center(
                                                  child: SizedBox(
                                                    width: 50.0,
                                                    height: 50.0,
                                                    child: ProxiplayLoadingLogo(
                                                        size: 42.0),
                                                  ),
                                                );
                                              }
                                              List<GamesRecord>
                                                  listViewGamesRecordList =
                                                  snapshot.data!
                                                      .where(
                                                          _isGameVisibleForPlayer)
                                                      .toList();
                                              if (listViewGamesRecordList
                                                  .isEmpty) {
                                                return const ListEmptyComponentWidget(
                                                  title: 'Liste vide',
                                                  description:
                                                      'Pas de jeu en cours',
                                                );
                                              }

                                              return ListView.separated(
                                                padding: EdgeInsets.zero,
                                                primary: false,
                                                scrollDirection: Axis.vertical,
                                                itemCount:
                                                    listViewGamesRecordList
                                                        .length,
                                                separatorBuilder: (_, __) =>
                                                    const SizedBox(
                                                        height: 10.0),
                                                itemBuilder:
                                                    (context, listViewIndex) {
                                                  final listViewGamesRecord =
                                                      listViewGamesRecordList[
                                                          listViewIndex];
                                                  return Container(
                                                    decoration: BoxDecoration(
                                                      color: FlutterFlowTheme
                                                              .of(context)
                                                          .secondaryBackground,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20.0),
                                                    ),
                                                    child: Builder(
                                                      builder: (context) {
                                                        return InkWell(
                                                          splashColor: Colors
                                                              .transparent,
                                                          focusColor: Colors
                                                              .transparent,
                                                          hoverColor: Colors
                                                              .transparent,
                                                          highlightColor: Colors
                                                              .transparent,
                                                          onTap: () async {
                                                            debugPrint('[MERCHANT_PAGE_DEBUG] game_card_tap gameId=${listViewGamesRecord.reference.id}');
                                                            debugPrint('[MERCHANT_PAGE_DEBUG] navigate_to_game gameId=${listViewGamesRecord.reference.id}');
                                                            context.pushNamed(
                                                              JeuDetailJoueurPageWidget
                                                                  .routeName,
                                                              queryParameters: {
                                                                'gameDoc':
                                                                    serializeParam(
                                                                  listViewGamesRecord,
                                                                  ParamType
                                                                      .Document,
                                                                ),
                                                                'enseigneDoc':
                                                                    serializeParam(
                                                                  widget
                                                                      .enseigneDoc,
                                                                  ParamType
                                                                      .Document,
                                                                ),
                                                              }.withoutNulls,
                                                              extra: <String,
                                                                  dynamic>{
                                                                'gameDoc':
                                                                    listViewGamesRecord,
                                                                'enseigneDoc':
                                                                    widget
                                                                        .enseigneDoc,
                                                                kTransitionInfoKey:
                                                                    const TransitionInfo(
                                                                  hasTransition:
                                                                      true,
                                                                  transitionType:
                                                                      PageTransitionType
                                                                          .fade,
                                                                ),
                                                              },
                                                            );
                                                          },
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .max,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .center,
                                                            children: [
                                                              Expanded(
                                                                flex: 1,
                                                                child:
                                                                    Container(
                                                                  height: 130.0,
                                                                  decoration:
                                                                      const BoxDecoration(),
                                                                  child:
                                                                      ClipRRect(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                            8.0),
                                                                    child: Image
                                                                        .network(
                                                                      listViewGamesRecord
                                                                          .photo,
                                                                      fit: BoxFit
                                                                          .fill,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              Expanded(
                                                                flex: 2,
                                                                child: Padding(
                                                                  padding:
                                                                      const EdgeInsetsDirectional
                                                                          .fromSTEB(
                                                                          10.0,
                                                                          0.0,
                                                                          0.0,
                                                                          0.0),
                                                                  child: Column(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .max,
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .start,
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    children: [
                                                                      Text(
                                                                        listViewGamesRecord
                                                                            .name,
                                                                        style: FlutterFlowTheme.of(context)
                                                                            .bodyMedium
                                                                            .override(
                                                                              font: GoogleFonts.inter(
                                                                                fontWeight: FontWeight.w600,
                                                                                fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                              ),
                                                                              letterSpacing: 0.0,
                                                                              fontWeight: FontWeight.w600,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                            ),
                                                                      ),
                                                                      Column(
                                                                        mainAxisSize:
                                                                            MainAxisSize.max,
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.spaceEvenly,
                                                                        children:
                                                                            [
                                                                          Row(
                                                                            mainAxisSize:
                                                                                MainAxisSize.max,
                                                                            children: [
                                                                              Icon(
                                                                                Icons.store_sharp,
                                                                                color: FlutterFlowTheme.of(context).primaryText,
                                                                                size: 18.0,
                                                                              ),
                                                                              Text(
                                                                                widget.enseigneDoc?.name ?? '',
                                                                                style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                    ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          Row(
                                                                            mainAxisSize:
                                                                                MainAxisSize.max,
                                                                            children: [
                                                                              Icon(
                                                                                Icons.location_on_sharp,
                                                                                color: FlutterFlowTheme.of(context).primaryText,
                                                                                size: 18.0,
                                                                              ),
                                                                              Text(
                                                                                widget.enseigneDoc?.city ?? '',
                                                                                style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                    ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          Row(
                                                                            mainAxisSize:
                                                                                MainAxisSize.max,
                                                                            children: [
                                                                              FaIcon(
                                                                                FontAwesomeIcons.piggyBank,
                                                                                color: FlutterFlowTheme.of(context).primaryText,
                                                                                size: 18.0,
                                                                              ),
                                                                              Text(
                                                                                ' Valeur : ',
                                                                                style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                    ),
                                                                              ),
                                                                              Text(
                                                                                _formatPrizeLabel(listViewGamesRecord),
                                                                                style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                    ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          Row(
                                                                            mainAxisSize:
                                                                                MainAxisSize.max,
                                                                            children: [
                                                                              Icon(
                                                                                Icons.calendar_month,
                                                                                color: FlutterFlowTheme.of(context).primaryText,
                                                                                size: 18.0,
                                                                              ),
                                                                              Text(
                                                                                ' Valable jusqu\'au : ',
                                                                                style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                    ),
                                                                              ),
                                                                              Text(
                                                                                dateTimeFormat(
                                                                                  "d/M/y",
                                                                                  listViewGamesRecord.endDate!,
                                                                                  locale: FFLocalizations.of(context).languageCode,
                                                                                ),
                                                                                style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                      font: GoogleFonts.inter(
                                                                                        fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                        fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                      ),
                                                                                      letterSpacing: 0.0,
                                                                                      fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                      fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                    ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ].divide(const SizedBox(height: 5.0)),
                                                                      ),
                                                                    ].divide(const SizedBox(
                                                                        height:
                                                                            5.0)),
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
                                          );
                                        }
                                      },
                                    );
                                  } else {
                                    return FutureBuilder<List<GamesRecord>>(
                                      future: ongoingGamesFuture,
                                      builder: (context, snapshot) {
                                        // Customize what your widget looks like when it's loading.
                                        if (!snapshot.hasData) {
                                          return const Center(
                                            child: SizedBox(
                                              width: 50.0,
                                              height: 50.0,
                                              child: ProxiplayLoadingLogo(
                                                  size: 42.0),
                                            ),
                                          );
                                        }
                                        List<GamesRecord>
                                            listViewGamesRecordList = snapshot
                                                .data!
                                                .where(_isGameVisibleForPlayer)
                                                .toList();
                                        if (listViewGamesRecordList.isEmpty) {
                                          return const ListEmptyComponentWidget(
                                            title: 'Liste vide',
                                            description: 'Aucun jeux en cours',
                                          );
                                        }

                                        return ListView.separated(
                                          padding: EdgeInsets.zero,
                                          primary: false,
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
                                            return Material(
                                              color: Colors.transparent,
                                              elevation: 1.0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20.0),
                                              ),
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .secondaryBackground,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          20.0),
                                                ),
                                                child: Builder(
                                                  builder: (context) {
                                                    return InkWell(
                                                      splashColor:
                                                          Colors.transparent,
                                                      focusColor:
                                                          Colors.transparent,
                                                      hoverColor:
                                                          Colors.transparent,
                                                      highlightColor:
                                                          Colors.transparent,
                                                      onTap: () async {
                                                            debugPrint('[MERCHANT_PAGE_DEBUG] game_card_tap gameId=${listViewGamesRecord.reference.id}');
                                                            debugPrint('[MERCHANT_PAGE_DEBUG] navigate_to_game gameId=${listViewGamesRecord.reference.id}');
                                                            context.pushNamed(
                                                          JeuDetailJoueurPageWidget
                                                              .routeName,
                                                          queryParameters: {
                                                            'gameDoc':
                                                                serializeParam(
                                                              listViewGamesRecord,
                                                              ParamType
                                                                  .Document,
                                                            ),
                                                            'enseigneDoc':
                                                                serializeParam(
                                                              widget
                                                                  .enseigneDoc,
                                                              ParamType
                                                                  .Document,
                                                            ),
                                                          }.withoutNulls,
                                                          extra: <String,
                                                              dynamic>{
                                                            'gameDoc':
                                                                listViewGamesRecord,
                                                            'enseigneDoc': widget
                                                                .enseigneDoc,
                                                            kTransitionInfoKey:
                                                                const TransitionInfo(
                                                              hasTransition:
                                                                  true,
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
                                                            CrossAxisAlignment
                                                                .center,
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
                                                                child: Image
                                                                    .network(
                                                                  listViewGamesRecord
                                                                      .photo,
                                                                  fit: BoxFit
                                                                      .fill,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          Expanded(
                                                            flex: 2,
                                                            child: Padding(
                                                              padding:
                                                                  const EdgeInsetsDirectional
                                                                      .fromSTEB(
                                                                      10.0,
                                                                      0.0,
                                                                      0.0,
                                                                      0.0),
                                                              child: Column(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .max,
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .start,
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  SingleChildScrollView(
                                                                    scrollDirection:
                                                                        Axis.horizontal,
                                                                    child: Row(
                                                                      mainAxisSize:
                                                                          MainAxisSize
                                                                              .max,
                                                                      children: [
                                                                        Text(
                                                                          listViewGamesRecord
                                                                              .name,
                                                                          style: FlutterFlowTheme.of(context)
                                                                              .bodyMedium
                                                                              .override(
                                                                                font: GoogleFonts.inter(
                                                                                  fontWeight: FontWeight.w600,
                                                                                  fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                                ),
                                                                                letterSpacing: 0.0,
                                                                                fontWeight: FontWeight.w600,
                                                                                fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                              ),
                                                                        ),
                                                                      ],
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
                                                                            MainAxisSize.max,
                                                                        children: [
                                                                          Icon(
                                                                            Icons.store_sharp,
                                                                            color:
                                                                                FlutterFlowTheme.of(context).primaryText,
                                                                            size:
                                                                                18.0,
                                                                          ),
                                                                          Text(
                                                                            widget.enseigneDoc?.name ??
                                                                                '',
                                                                            style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                  font: GoogleFonts.inter(
                                                                                    fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                  ),
                                                                                  letterSpacing: 0.0,
                                                                                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      Row(
                                                                        mainAxisSize:
                                                                            MainAxisSize.max,
                                                                        children: [
                                                                          Icon(
                                                                            Icons.location_on_sharp,
                                                                            color:
                                                                                FlutterFlowTheme.of(context).primaryText,
                                                                            size:
                                                                                18.0,
                                                                          ),
                                                                          Text(
                                                                            widget.enseigneDoc?.city ??
                                                                                '',
                                                                            style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                  font: GoogleFonts.inter(
                                                                                    fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                  ),
                                                                                  letterSpacing: 0.0,
                                                                                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      Row(
                                                                        mainAxisSize:
                                                                            MainAxisSize.max,
                                                                        children: [
                                                                          FaIcon(
                                                                            FontAwesomeIcons.piggyBank,
                                                                            color:
                                                                                FlutterFlowTheme.of(context).primaryText,
                                                                            size:
                                                                                18.0,
                                                                          ),
                                                                          Text(
                                                                            ' Valeur : ',
                                                                            style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                  font: GoogleFonts.inter(
                                                                                    fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                  ),
                                                                                  letterSpacing: 0.0,
                                                                                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                ),
                                                                          ),
                                                                          Text(
                                                                            _formatPrizeLabel(listViewGamesRecord),
                                                                            style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                  font: GoogleFonts.inter(
                                                                                    fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                  ),
                                                                                  letterSpacing: 0.0,
                                                                                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      Row(
                                                                        mainAxisSize:
                                                                            MainAxisSize.max,
                                                                        children: [
                                                                          Icon(
                                                                            Icons.calendar_month,
                                                                            color:
                                                                                FlutterFlowTheme.of(context).primaryText,
                                                                            size:
                                                                                18.0,
                                                                          ),
                                                                          Text(
                                                                            ' Valable jusqu\'au : ',
                                                                            style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                  font: GoogleFonts.inter(
                                                                                    fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                  ),
                                                                                  letterSpacing: 0.0,
                                                                                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                ),
                                                                          ),
                                                                          Text(
                                                                            dateTimeFormat(
                                                                              "d/M/y",
                                                                              listViewGamesRecord.endDate!,
                                                                              locale: FFLocalizations.of(context).languageCode,
                                                                            ),
                                                                            style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                  font: GoogleFonts.inter(
                                                                                    fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                  ),
                                                                                  letterSpacing: 0.0,
                                                                                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ].divide(const SizedBox(
                                                                        height:
                                                                            5.0)),
                                                                  ),
                                                                ].divide(
                                                                    const SizedBox(
                                                                        height:
                                                                            5.0)),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    );
                                  }
                                },
                              ),
                            ),
                          ].divide(const SizedBox(height: 10.0)),
                        ),
                      ),
                    ),
                  ),
                  wrapWithModel(
                    model: _model.customNavBarJoueurModel,
                    updateCallback: () => safeSetState(() {}),
                    child: const CustomNavBarJoueurWidget(),
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

