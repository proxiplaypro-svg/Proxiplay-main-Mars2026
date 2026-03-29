import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/components/app_bar_joueur_widget.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/components/game_card_widget.dart';
import '/components/list_empty_component_widget.dart';
import '/flutter_flow/flutter_flow_button_tabbar.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/widgets/proxiplay_network_image.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'favoris_joueur_page_model.dart';
export 'favoris_joueur_page_model.dart';

class FavorisJoueurPageWidget extends StatefulWidget {
  const FavorisJoueurPageWidget({super.key});

  static String routeName = 'FavorisJoueurPage';
  static String routePath = 'favorisJoueurPage';

  @override
  State<FavorisJoueurPageWidget> createState() =>
      _FavorisJoueurPageWidgetState();
}

class _FavorisJoueurPageWidgetState extends State<FavorisJoueurPageWidget>
    with TickerProviderStateMixin {
  late FavorisJoueurPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  final Map<String, Future<int>> _activeGamesCountByMerchantCache = {};

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

  Future<int> _getActiveGamesCountForMerchant(
    DocumentReference? enseigneRef,
  ) {
    if (enseigneRef == null) {
      return Future.value(0);
    }

    return _activeGamesCountByMerchantCache.putIfAbsent(enseigneRef.path, () async {
      final games = await queryGamesRecordOnce(
        queryBuilder: (gamesRecord) => gamesRecord
            .where(
              'enseigne_id',
              isEqualTo: enseigneRef,
            )
            .where(
              'end_date',
              isGreaterThan: getCurrentTimestamp,
            ),
      );

      return games.where(_isGameVisibleForPlayer).length;
    });
  }

  Future<void> _removeMerchantFavorite(
    FavoriteEnseignesRecord favoriteRecord,
  ) async {
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final favoriteSnap = await transaction.get(favoriteRecord.reference);
      if (!favoriteSnap.exists) {
        return;
      }

      final enseigneRef = favoriteRecord.enseigneId;
      if (enseigneRef != null) {
        final enseigneSnap = await transaction.get(enseigneRef);
        final currentCount =
            _readFavoriteCounter(enseigneSnap.data() as Map<String, dynamic>? ?? {});
        final nextCount = (currentCount - 1).clamp(0, 1 << 30);
        transaction.set(
          enseigneRef,
          {
            'favoritesCount': nextCount,
            'favorites': nextCount,
            'favorisCount': nextCount,
            'favoris': nextCount,
            'stats_favorites': nextCount,
            'stats_favoris': nextCount,
          },
          SetOptions(merge: true),
        );
      }

      transaction.delete(favoriteRecord.reference);
    });
  }

  DateTime? _endOfGameDay(DateTime? gameEndDate) {
    if (gameEndDate == null) return null;
    return DateTime(
      gameEndDate.year,
      gameEndDate.month,
      gameEndDate.day,
      23,
      59,
      59,
    );
  }

  bool _isGameFinished(GamesRecord game) {
    final endOfGameDay = _endOfGameDay(game.endDate);
    return endOfGameDay == null || !endOfGameDay.isAfter(getCurrentTimestamp);
  }

  Future<List<_FavoriteGameListItem>> _loadSortedFavoriteGames() async {
    final favoriteRecords = await queryFavoriteGamesRecordOnce(
      parent: currentUserReference,
    );

    final items = await Future.wait(
      favoriteRecords.map((favoriteRecord) async {
        final gameRef = favoriteRecord.gameId;
        if (gameRef == null) return null;

        final game = await GamesRecord.getDocumentOnce(gameRef);
        if (!_isGameVisibleForPlayer(game)) return null;

        final enseigneRef = game.enseigneId;
        if (enseigneRef == null) return null;

        final enseigne = await EnseignesRecord.getDocumentOnce(enseigneRef);
        return _FavoriteGameListItem(
          favoriteRecord: favoriteRecord,
          game: game,
          enseigne: enseigne,
        );
      }),
    );

    final sortedItems = items.whereType<_FavoriteGameListItem>().toList();
    sortedItems.sort((a, b) {
      final aFinished = _isGameFinished(a.game);
      final bFinished = _isGameFinished(b.game);
      if (aFinished != bFinished) {
        return aFinished ? 1 : -1;
      }

      final aEnd = _endOfGameDay(a.game.endDate);
      final bEnd = _endOfGameDay(b.game.endDate);
      if (aEnd == null && bEnd == null) return 0;
      if (aEnd == null) return 1;
      if (bEnd == null) return -1;
      return aEnd.compareTo(bEnd);
    });
    return sortedItems;
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => FavorisJoueurPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'FavorisJoueurPage'});
    _model.tabBarController = TabController(
      vsync: this,
      length: 2,
      initialIndex: 0,
    )..addListener(() => safeSetState(() {}));
  }

  @override
  void dispose() {
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
          resizeToAvoidBottomInset: false,
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(100.0),
            child: AppBar(
              backgroundColor: Colors.transparent,
              automaticallyImplyLeading: false,
              actions: const [],
              flexibleSpace: FlexibleSpaceBar(
                title: wrapWithModel(
                  model: _model.appBarJoueurModel,
                  updateCallback: () => safeSetState(() {}),
                  child: const AppBarJoueurWidget(),
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
              decoration: BoxDecoration(
                image: DecorationImage(
                  fit: BoxFit.cover,
                  image: Image.asset(
                    'assets/images/Background.png',
                  ).image,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(20.0, 30.0, 20.0, 0.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              height: 100.0,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                              child: Column(
                                children: [
                                  Align(
                                    alignment: const Alignment(0.0, 0),
                                    child: FlutterFlowButtonTabBar(
                                      useToggleButtonStyle: true,
                                      labelStyle: FlutterFlowTheme.of(context)
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
                                            fontSize: 16.0,
                                            letterSpacing: 0.0,
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .titleMedium
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .titleMedium
                                                    .fontStyle,
                                          ),
                                      unselectedLabelStyle: FlutterFlowTheme.of(
                                              context)
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
                                            fontSize: 16.0,
                                            letterSpacing: 0.0,
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .titleMedium
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .titleMedium
                                                    .fontStyle,
                                          ),
                                      labelColor: FlutterFlowTheme.of(context)
                                          .primaryBackground,
                                      unselectedLabelColor:
                                          FlutterFlowTheme.of(context)
                                              .primaryBackground,
                                      backgroundColor:
                                          FlutterFlowTheme.of(context).accent1,
                                      unselectedBackgroundColor:
                                          FlutterFlowTheme.of(context)
                                              .fieldText,
                                      borderColor:
                                          FlutterFlowTheme.of(context).primary,
                                      unselectedBorderColor:
                                          FlutterFlowTheme.of(context)
                                              .alternate,
                                      borderWidth: 0.0,
                                      borderRadius: 8.0,
                                      elevation: 0.0,
                                      buttonMargin:
                                          const EdgeInsetsDirectional.fromSTEB(
                                              8.0, 0.0, 8.0, 0.0),
                                      tabs: const [
                                        Tab(
                                          text: 'Mes favoris',
                                        ),
                                        Tab(
                                          text: 'Mes jeux',
                                        ),
                                      ],
                                      controller: _model.tabBarController,
                                      onTap: (i) async {
                                        [() async {}, () async {}][i]();
                                      },
                                    ),
                                  ),
                                  Expanded(
                                    child: TabBarView(
                                      controller: _model.tabBarController,
                                      children: [
                                        Padding(
                                          padding:
                                              const EdgeInsetsDirectional.fromSTEB(
                                                  0.0, 5.0, 0.0, 0.0),
                                          child: Container(
                                            decoration: const BoxDecoration(),
                                            child: PagedListView<
                                                DocumentSnapshot<Object?>?,
                                                FavoriteEnseignesRecord>.separated(
                                              pagingController:
                                                  _model.setListViewController1(
                                                      FavoriteEnseignesRecord
                                                          .collection(
                                                              currentUserReference),
                                                      parent:
                                                          currentUserReference),
                                              padding: EdgeInsets.zero,
                                              reverse: false,
                                              scrollDirection: Axis.vertical,
                                              separatorBuilder: (_, __) =>
                                                  const SizedBox(height: 10.0),
                                              builderDelegate:
                                                  PagedChildBuilderDelegate<
                                                      FavoriteEnseignesRecord>(
                                                // Customize what your widget looks like when it's loading the first page.
                                                firstPageProgressIndicatorBuilder:
                                                    (_) => const Center(
                                                  child: SizedBox(
                                                    width: 50.0,
                                                    height: 50.0,
                                                    child:
                                                        SizedBox.shrink(),
                                                  ),
                                                ),
                                                // Customize what your widget looks like when it's loading another page.
                                                newPageProgressIndicatorBuilder:
                                                    (_) => const Center(
                                                  child: SizedBox(
                                                    width: 50.0,
                                                    height: 50.0,
                                                    child:
                                                        SizedBox.shrink(),
                                                  ),
                                                ),
                                                noItemsFoundIndicatorBuilder:
                                                    (_) =>
                                                        const ListEmptyComponentWidget(
                                                  title: 'Aucun Favori',
                                                  description:
                                                      'Votre liste est actuellement vide',
                                                ),
                                                itemBuilder: (context, _,
                                                    listViewIndex) {
                                                  final listViewFavoriteEnseignesRecord =
                                                      _model.listViewPagingController1!
                                                              .itemList![
                                                          listViewIndex];
                                                  return StreamBuilder<
                                                      EnseignesRecord>(
                                                    stream: EnseignesRecord
                                                        .getDocument(
                                                            listViewFavoriteEnseignesRecord
                                                                .enseigneId!),
                                                    builder:
                                                        (context, snapshot) {
                                                      // Customize what your widget looks like when it's loading.
                                                      if (!snapshot.hasData) {
                                                        return const Center(
                                                          child: SizedBox(
                                                            width: 50.0,
                                                            height: 50.0,
                                                            child:
                                                                SizedBox.shrink(),
                                                          ),
                                                        );
                                                      }

                                                      final containerEnseignesRecord =
                                                          snapshot.data!;

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
                                                          context.pushNamed(
                                                            EnseigneDetailJoueurPageWidget
                                                                .routeName,
                                                            queryParameters: {
                                                              'enseigneDoc':
                                                                  serializeParam(
                                                                containerEnseignesRecord,
                                                                ParamType
                                                                    .Document,
                                                              ),
                                                            }.withoutNulls,
                                                            extra: <String,
                                                                dynamic>{
                                                              'enseigneDoc':
                                                                  containerEnseignesRecord,
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
                                                        child: Container(
                                                          decoration:
                                                              BoxDecoration(
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .secondaryBackground,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        20.0),
                                                          ),
                                                          child: Builder(
                                                            builder: (context) {
                                                              return Row(
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
                                                                          130.0,
                                                                      decoration:
                                                                          const BoxDecoration(),
                                                                      child: FutureBuilder<
                                                                          List<ImagesRecord>>(
                                                                        future:
                                                                            queryImagesRecordOnce(
                                                                          parent:
                                                                              containerEnseignesRecord.reference,
                                                                          singleRecord:
                                                                              true,
                                                                        ),
                                                                        builder:
                                                                            (context, snapshot) {
                                                                          // Customize what your widget looks like when it's loading.
                                                                          if (!snapshot.hasData) {
                                                                            return const Center(
                                                                              child: SizedBox(
                                                                                width: 50.0,
                                                                                height: 50.0,
                                                                                child: SizedBox.shrink(),
                                                                              ),
                                                                            );
                                                                          }
                                                                          List<ImagesRecord>
                                                                              imageImagesRecordList =
                                                                              snapshot.data!;
                                                                          // Return an empty Container when the item does not exist.
                                                                          if (snapshot.data!.isEmpty) {
                                                                            return Container();
                                                                          }
                                                                          final imageImagesRecord = imageImagesRecordList.isNotEmpty
                                                                              ? imageImagesRecordList.first
                                                                              : null;

                                                                          return ClipRRect(
                                                                              borderRadius: BorderRadius.circular(8.0),
                                                                              child: ProxiplayNetworkImage(
                                                                                imageUrl: imageImagesRecord!.url,
                                                                                fit: BoxFit.cover,
                                                                              ),
                                                                            );
                                                                          },
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  Expanded(
                                                                    flex: 2,
                                                                    child:
                                                                        Padding(
                                                                      padding: const EdgeInsetsDirectional.fromSTEB(
                                                                          10.0,
                                                                          0.0,
                                                                          0.0,
                                                                          0.0),
                                                                      child:
                                                                          Column(
                                                                        mainAxisSize:
                                                                            MainAxisSize.max,
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.start,
                                                                        crossAxisAlignment:
                                                                            CrossAxisAlignment.start,
                                                                        children:
                                                                            [
                                                                          Text(
                                                                            containerEnseignesRecord.name,
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
                                                                          Column(
                                                                            mainAxisSize: MainAxisSize.max,
                                                                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                                            children: [
                                                                              Row(
                                                                                mainAxisSize: MainAxisSize.max,
                                                                                children: [
                                                                                  Container(
                                                                                    width: 30.0,
                                                                                    decoration: const BoxDecoration(),
                                                                                    alignment: const AlignmentDirectional(-1.0, 0.0),
                                                                                    child: Icon(
                                                                                      Icons.card_giftcard,
                                                                                      color: FlutterFlowTheme.of(context).primaryText,
                                                                                      size: 18.0,
                                                                                    ),
                                                                                  ),
                                                                                  Text(
                                                                                    'Jeux en cours : ',
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
                                                                                  FutureBuilder<int>(
                                                                                    future: _getActiveGamesCountForMerchant(
                                                                                      listViewFavoriteEnseignesRecord.enseigneId,
                                                                                    ),
                                                                                    builder: (context, snapshot) {
                                                                                      // Customize what your widget looks like when it's loading.
                                                                                      if (!snapshot.hasData) {
                                                                                        return const Center(
                                                                                          child: SizedBox(
                                                                                            width: 50.0,
                                                                                            height: 50.0,
                                                                                            child: SizedBox.shrink(),
                                                                                          ),
                                                                                        );
                                                                                      }
                                                                                      final textCount =
                                                                                          snapshot.data ?? 0;

                                                                                      return Text(
                                                                                        textCount.toString(),
                                                                                        style: FlutterFlowTheme.of(context).bodySmall.override(
                                                                                              font: GoogleFonts.inter(
                                                                                                fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                                fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                              ),
                                                                                              letterSpacing: 0.0,
                                                                                              fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                                                                                              fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                                                                                            ),
                                                                                      );
                                                                                    },
                                                                                  ),
                                                                                ],
                                                                              ),
                                                                              Row(
                                                                                mainAxisSize: MainAxisSize.max,
                                                                                children: [
                                                                                  Container(
                                                                                    width: 30.0,
                                                                                    decoration: const BoxDecoration(),
                                                                                    alignment: const AlignmentDirectional(-1.0, 0.0),
                                                                                    child: Icon(
                                                                                      Icons.location_on_sharp,
                                                                                      color: FlutterFlowTheme.of(context).primaryText,
                                                                                      size: 18.0,
                                                                                    ),
                                                                                  ),
                                                                                  Text(
                                                                                    containerEnseignesRecord.city,
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
                                                                                  Container(
                                                                                    width: 30.0,
                                                                                    decoration: const BoxDecoration(),
                                                                                    alignment: const AlignmentDirectional(-1.0, 0.0),
                                                                                    child: Icon(
                                                                                      Icons.phone,
                                                                                      color: FlutterFlowTheme.of(context).primaryText,
                                                                                      size: 18.0,
                                                                                    ),
                                                                                  ),
                                                                                  Text(
                                                                                    containerEnseignesRecord.phoneNumber,
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
                                                                        ].divide(const SizedBox(height: 5.0)),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              );
                                                                                                                        },
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding:
                                              const EdgeInsetsDirectional.fromSTEB(
                                                  0.0, 5.0, 0.0, 0.0),
                                          child: Container(
                                            decoration: const BoxDecoration(),
                                            child: FutureBuilder<
                                                List<_FavoriteGameListItem>>(
                                              future: _loadSortedFavoriteGames(),
                                              builder: (context, snapshot) {
                                                if (!snapshot.hasData) {
                                                  return const Center(
                                                    child: SizedBox(
                                                      width: 50.0,
                                                      height: 50.0,
                                                      child: SizedBox.shrink(),
                                                    ),
                                                  );
                                                }

                                                final favoriteGameItems =
                                                    snapshot.data!;
                                                if (favoriteGameItems.isEmpty) {
                                                  return const Center(
                                                    child:
                                                        ListEmptyComponentWidget(
                                                      title: 'Aucun favori',
                                                      description:
                                                          'Votre liste est actuellement vide',
                                                    ),
                                                  );
                                                }

                                                return ListView.separated(
                                                  padding: EdgeInsets.zero,
                                                  itemCount:
                                                      favoriteGameItems.length,
                                                  separatorBuilder: (_, __) =>
                                                      const SizedBox(
                                                          height: 16.0),
                                                  itemBuilder:
                                                      (context, listViewIndex) {
                                                    final favoriteItem =
                                                        favoriteGameItems[
                                                            listViewIndex];
                                                    final containerGamesRecord =
                                                        favoriteItem.game;
                                                    final rowEnseignesRecord =
                                                        favoriteItem.enseigne;
                                                    final isFinished =
                                                        _isGameFinished(
                                                            containerGamesRecord);
                                                    final hasWinnerAnnouncement =
                                                        isFinished &&
                                                            containerGamesRecord
                                                                .hasWinner &&
                                                            containerGamesRecord
                                                                    .mainPrizeWinner !=
                                                                null;

                                                    Widget buildCard(
                                                        {String? winnerText}) {
                                                      return GameCardWidget(
                                                        title:
                                                            containerGamesRecord
                                                                .name,
                                                        imageUrl:
                                                            containerGamesRecord
                                                                .photo,
                                                        storeName:
                                                            rowEnseignesRecord
                                                                .name,
                                                        city:
                                                            rowEnseignesRecord
                                                                .city,
                                                        prizeText:
                                                            containerGamesRecord
                                                                        .prizeValue ==
                                                                    0
                                                                ? 'Gains instantanés'
                                                                : '${containerGamesRecord.prizeValue} €',
                                                        endDateText:
                                                            containerGamesRecord
                                                                        .endDate !=
                                                                    null
                                                                ? 'Valable jusqu\'au : ${dateTimeFormat("d/M/y", containerGamesRecord.endDate, locale: FFLocalizations.of(context).languageCode)}'
                                                                : 'Valable jusqu\'au : -',
                                                        winnerText: winnerText,
                                                        winnerMaxLines: 1,
                                                        isFinished: isFinished,
                                                        width: double.infinity,
                                                        onTap: () async {
                                                          await containerGamesRecord
                                                              .reference
                                                              .update({
                                                            ...mapToFirestore(
                                                              {
                                                                'views':
                                                                    FieldValue
                                                                        .increment(
                                                                            1),
                                                              },
                                                            ),
                                                          });

                                                          if (!context.mounted) {
                                                            return;
                                                          }

                                                          context.pushNamed(
                                                            JeuDetailJoueurPageWidget
                                                                .routeName,
                                                            queryParameters: {
                                                              'gameDoc':
                                                                  serializeParam(
                                                                containerGamesRecord,
                                                                ParamType
                                                                    .Document,
                                                              ),
                                                              'enseigneDoc':
                                                                  serializeParam(
                                                                rowEnseignesRecord,
                                                                ParamType
                                                                    .Document,
                                                              ),
                                                            }.withoutNulls,
                                                            extra: <String,
                                                                dynamic>{
                                                              'gameDoc':
                                                                  containerGamesRecord,
                                                              'enseigneDoc':
                                                                  rowEnseignesRecord,
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
                                                      );
                                                    }

                                                    if (!hasWinnerAnnouncement) {
                                                      return buildCard();
                                                    }

                                                    return FutureBuilder<
                                                        UsersRecord>(
                                                      future: UsersRecord
                                                          .getDocumentOnce(
                                                              containerGamesRecord
                                                                  .mainPrizeWinner!),
                                                      builder: (context,
                                                          winnerSnapshot) {
                                                        final winner =
                                                            winnerSnapshot.data;
                                                        final firstName =
                                                            (winner?.firstName ??
                                                                    '')
                                                                .trim();
                                                        final city =
                                                            (winner?.city ?? '')
                                                                .trim();
                                                        final winnerIdentity =
                                                            city.isNotEmpty
                                                                ? '$firstName - $city'
                                                                : firstName;
                                                        final winnerLabel =
                                                            winnerIdentity
                                                                    .isNotEmpty
                                                                ? 'Gagné par $winnerIdentity'
                                                                : 'Gagnant annoncé';
                                                        return buildCard(
                                                          winnerText:
                                                              winnerLabel,
                                                        );
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
                                ],
                              ),
                            ),
                          ),
                        ].divide(const SizedBox(height: 20.0)),
                      ),
                    ),
                  ),
                  wrapWithModel(
                    model: _model.customNavBarJoueurModel,
                    updateCallback: () => safeSetState(() {}),
                    child: const CustomNavBarJoueurWidget(
                      indexActive: 2,
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

class _FavoriteGameListItem {
  const _FavoriteGameListItem({
    required this.favoriteRecord,
    required this.game,
    required this.enseigne,
  });

  final FavoriteGamesRecord favoriteRecord;
  final GamesRecord game;
  final EnseignesRecord enseigne;
}




