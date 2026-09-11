import '/components/merchant_presentation.dart';
import '/backend/backend.dart';
import '/components/app_bar_joueur_widget.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/components/list_empty_component_widget.dart';
import '/auth/firebase_auth/auth_util.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/widgets/proxiplay_network_image.dart';
import 'dart:async';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:text_search/text_search.dart';
import 'enseigne_joueur_page_model.dart';
export 'enseigne_joueur_page_model.dart';

class EnseigneJoueurPageWidget extends StatefulWidget {
  const EnseigneJoueurPageWidget({super.key});

  static String routeName = 'EnseigneJoueurPage';
  static String routePath = 'enseigneJoueurPage';

  @override
  State<EnseigneJoueurPageWidget> createState() =>
      _EnseigneJoueurPageWidgetState();
}

class _EnseigneJoueurPageWidgetState extends State<EnseigneJoueurPageWidget> {
  late EnseigneJoueurPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  late StreamSubscription<bool> _keyboardVisibilitySubscription;
  bool _isKeyboardVisible = false;
  final Map<String, Future<List<ImagesRecord>>> _searchImageFutureCache = {};

  Future<List<ImagesRecord>> _getSearchImageFuture(EnseignesRecord enseigne) {
    return _searchImageFutureCache.putIfAbsent(
      enseigne.reference.path,
      () => queryImagesRecordOnce(
        parent: enseigne.reference,
        singleRecord: true,
      ),
    );
  }

  Future<void> _addMerchantToFavorites(DocumentReference enseigneRef) async {
    if (currentUserReference == null) {
      return;
    }
    final favoriteRef = FavoriteEnseignesRecord.createDoc(
      currentUserReference!,
      id: enseigneRef.id,
    );

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
  }

  Future<void> _removeMerchantFromFavorites(
    FavoriteEnseignesRecord favoriteRecord,
  ) async {
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final favoriteSnap = await transaction.get(favoriteRecord.reference);
      if (!favoriteSnap.exists) {
        return;
      }

      transaction.delete(favoriteRecord.reference);
    });
  }

  Widget _buildMerchantFavoriteButton(EnseignesRecord enseigne) {
    if (currentUserUid.isEmpty || currentUserReference == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<FavoriteEnseignesRecord>>(
      stream: queryFavoriteEnseignesRecord(
        parent: currentUserReference,
        queryBuilder: (favoriteEnseignesRecord) =>
            favoriteEnseignesRecord.where(
          'enseigne_id',
          isEqualTo: enseigne.reference,
        ),
        singleRecord: true,
      ),
      builder: (context, snapshot) {
        final favoriteRecord = snapshot.hasData && snapshot.data!.isNotEmpty
            ? snapshot.data!.first
            : null;
        final isFavorite = favoriteRecord != null;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20.0),
            onTap: () async {
              if (isFavorite) {
                await _removeMerchantFromFavorites(favoriteRecord);
              } else {
                await _addMerchantToFavorites(enseigne.reference);
              }
            },
            child: Ink(
              width: 36.0,
              height: 36.0,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 10.0,
                    offset: Offset(0.0, 3.0),
                  ),
                ],
              ),
              child: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: const Color(0xFFA0134D),
                size: 20.0,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => EnseigneJoueurPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'EnseigneJoueurPage'});
    if (!isWeb) {
      _keyboardVisibilitySubscription =
          KeyboardVisibilityController().onChange.listen((bool visible) {
        safeSetState(() {
          _isKeyboardVisible = visible;
        });
      });
    }

    _model.textController ??= TextEditingController();
    _model.textFieldFocusNode ??= FocusNode();
  }

  @override
  void dispose() {
    _model.dispose();

    if (!isWeb) {
      _keyboardVisibilitySubscription.cancel();
    }
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Container(
                      height: double.infinity,
                      decoration: const BoxDecoration(),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            20.0, 30.0, 20.0, 0.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: double.infinity,
                              decoration: const BoxDecoration(),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: FlutterFlowTheme.of(context).fieldBg,
                                  borderRadius: BorderRadius.circular(12.0),
                                  shape: BoxShape.rectangle,
                                  border: Border.all(
                                    color:
                                        FlutterFlowTheme.of(context).alternate,
                                    width: 1.0,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(
                                      8.0, 8.0, 8.0, 8.0),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.max,
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.search_rounded,
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        size: 24.0,
                                      ),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _model.textController,
                                          focusNode: _model.textFieldFocusNode,
                                          onFieldSubmitted: (_) async {
                                            await queryEnseignesRecordOnce()
                                                .then(
                                                  (records) => _model
                                                          .simpleSearchResults =
                                                      TextSearch(
                                                    records
                                                        .map(
                                                          (record) =>
                                                              TextSearchItem
                                                                  .fromTerms(
                                                                      record, [
                                                            record.name
                                                          ]),
                                                        )
                                                        .toList(),
                                                  )
                                                          .search(_model
                                                              .textController
                                                              .text)
                                                          .map((r) => r.object)
                                                          .take(10)
                                                          .toList(),
                                                )
                                                .onError((_, __) => _model
                                                    .simpleSearchResults = [])
                                                .whenComplete(
                                                    () => safeSetState(() {}));

                                            _model.searchActive = true;
                                          },
                                          autofocus: false,
                                          obscureText: false,
                                          decoration: const InputDecoration(
                                            alignLabelWithHint: false,
                                            hintText:
                                                'Rechercher un point de vente',
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            errorBorder: InputBorder.none,
                                            focusedErrorBorder:
                                                InputBorder.none,
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
                                          textAlign: TextAlign.start,
                                          validator: _model
                                              .textControllerValidator
                                              .asValidator(context),
                                        ),
                                      ),
                                      if (_model.searchActive)
                                        FlutterFlowIconButton(
                                          borderColor: Colors.transparent,
                                          borderRadius: 30.0,
                                          buttonSize: 40.0,
                                          icon: Icon(
                                            Icons.cancel_outlined,
                                            color: FlutterFlowTheme.of(context)
                                                .primary,
                                            size: 24.0,
                                          ),
                                          onPressed: () async {
                                            safeSetState(() {
                                              _model.textController?.clear();
                                            });
                                            _model.searchActive = false;
                                          },
                                        ),
                                    ].divide(const SizedBox(width: 8.0)),
                                  ),
                                ),
                              ),
                            ),
                            if (_model.searchActive)
                              Expanded(
                                child: Container(
                                  decoration: const BoxDecoration(),
                                  child: Builder(
                                    builder: (context) {
                                      final search =
                                          _model.simpleSearchResults.toList();
                                      if (search.isEmpty) {
                                        return const ListEmptyComponentWidget(
                                          title: 'Aucun résultat',
                                          description: ' ',
                                        );
                                      }

                                      return ListView.separated(
                                        padding: EdgeInsets.zero,
                                        primary: false,
                                        scrollDirection: Axis.vertical,
                                        itemCount: search.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 10.0),
                                        itemBuilder: (context, searchIndex) {
                                          final searchItem =
                                              search[searchIndex];
                                          return MerchantSummaryCard(
                                            merchant: searchItem,
                                            onTap: () async {
                                              context.pushNamed(
                                                EnseigneDetailJoueurPageWidget
                                                    .routeName,
                                                queryParameters: {
                                                  'enseigneDoc': serializeParam(
                                                    searchItem,
                                                    ParamType.Document,
                                                  ),
                                                }.withoutNulls,
                                                extra: <String, dynamic>{
                                                  'enseigneDoc': searchItem,
                                                  kTransitionInfoKey:
                                                      const TransitionInfo(
                                                    hasTransition: true,
                                                    transitionType:
                                                        PageTransitionType.fade,
                                                  ),
                                                },
                                              );
                                            },
                                            compact: true,
                                            photoFuture: _getSearchImageFuture(
                                                searchItem),
                                            favorite:
                                                _buildMerchantFavoriteButton(
                                                    searchItem),
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
                                      final catgeorie =
                                          FFAppConstants.Category.toList();

                                      return SingleChildScrollView(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.max,
                                          children:
                                              List.generate(catgeorie.length,
                                                  (catgeorieIndex) {
                                            final catgeorieItem =
                                                catgeorie[catgeorieIndex];
                                            return FutureBuilder<
                                                List<EnseignesRecord>>(
                                              future: queryEnseignesRecordOnce(
                                                queryBuilder:
                                                    (enseignesRecord) =>
                                                        enseignesRecord.where(
                                                  'category',
                                                  arrayContains: catgeorieItem,
                                                ),
                                                limit: 20,
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
                                                List<EnseignesRecord>
                                                    containerEnseignesRecordList =
                                                    snapshot.data!;

                                                return Container(
                                                  decoration:
                                                      const BoxDecoration(),
                                                  child: Visibility(
                                                    visible:
                                                        containerEnseignesRecordList
                                                            .isNotEmpty,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.max,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        Text(
                                                          catgeorieItem,
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
                                                        SingleChildScrollView(
                                                          scrollDirection:
                                                              Axis.horizontal,
                                                          child: Row(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children:
                                                                containerEnseignesRecordList
                                                                    .map((enseigneItem) =>
                                                                        SizedBox(
                                                                          width:
                                                                              260,
                                                                          child:
                                                                              MerchantSummaryCard(
                                                                            merchant:
                                                                                enseigneItem,
                                                                            onTap: () =>
                                                                                context.pushNamed(
                                                                              EnseigneDetailJoueurPageWidget.routeName,
                                                                              queryParameters: {
                                                                                'enseigneDoc': serializeParam(enseigneItem, ParamType.Document)
                                                                              }.withoutNulls,
                                                                              extra: <String, dynamic>{
                                                                                'enseigneDoc': enseigneItem
                                                                              },
                                                                            ),
                                                                            photoFuture:
                                                                                _getSearchImageFuture(enseigneItem),
                                                                            favorite:
                                                                                _buildMerchantFavoriteButton(enseigneItem),
                                                                          ),
                                                                        ))
                                                                    .toList()
                                                                    .divide(const SizedBox(
                                                                        width:
                                                                            10)),
                                                          ),
                                                        ),
                                                      ].divide(const SizedBox(
                                                          height: 5.0)),
                                                    ),
                                                  ),
                                                );
                                              },
                                            );
                                          }).divide(
                                                  const SizedBox(height: 15.0)),
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
                  if (!(isWeb
                      ? MediaQuery.viewInsetsOf(context).bottom > 0
                      : _isKeyboardVisible))
                    wrapWithModel(
                      model: _model.customNavBarJoueurModel,
                      updateCallback: () => safeSetState(() {}),
                      child: const CustomNavBarJoueurWidget(
                        indexActive: 3,
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
