import '/components/merchant_presentation.dart';
import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/components/custom_nav_bar_joueur_widget.dart';

import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/widgets/proxiplay_loading_logo.dart';
import '/widgets/proxiplay_network_image.dart';
import '/utils/player_game_visibility.dart';
import '/utils/external_link.dart';

import '/index.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'enseigne_detail_joueur_page_model.dart';
export 'enseigne_detail_joueur_page_model.dart';

/// Player-facing profile using the merchant's existing Proxiplay data.
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

  bool _isGameVisibleForPlayer(GamesRecord game) {
    if (isGameHiddenFromPlayer(game.snapshotData)) {
      return false;
    }
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
      return 'Gains immédiats';
    }
    return 'Valeur du lot : ${_formatPrice(game.prizeValue)}';
  }

  String _formatPrice(double value) {
    final hasDecimals = value != value.truncateToDouble();
    if (!hasDecimals) {
      return '${value.toStringAsFixed(0)} €';
    }

    return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  bool get _canViewMinorRestrictedGames => true;

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
      // The section may mount below the fold after the request completes.
      // Its FutureBuilder still receives the original success/error result.
      _ongoingGamesFuture!.ignore();
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

  Widget _buildMerchantFavoriteButton({
    double buttonSize = 40.0,
    double iconSize = 24.0,
  }) {
    if (currentUserUid == '') {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<FavoriteEnseignesRecord>>(
      stream: queryFavoriteEnseignesRecord(
        parent: currentUserReference,
        queryBuilder: (favoriteEnseignesRecord) =>
            favoriteEnseignesRecord.where(
          'enseigne_id',
          isEqualTo: widget.enseigneDoc?.reference,
        ),
        singleRecord: true,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: const Center(
              child: SizedBox(
                width: 26.0,
                height: 26.0,
                child: ProxiplayLoadingLogo(size: 22.0),
              ),
            ),
          );
        }

        final favoriteRecord =
            snapshot.data!.isNotEmpty ? snapshot.data!.first : null;
        final isFavorite = favoriteRecord != null;

        return FlutterFlowIconButton(
          borderRadius: buttonSize / 2,
          buttonSize: buttonSize,
          icon: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: const Color(0xFFA0134D),
            size: iconSize,
          ),
          onPressed: () async {
            if (isFavorite) {
              debugPrint(
                '[MERCHANT_PAGE_DEBUG] favorite_tap enseigneId=${favoriteRecord.enseigneId?.id ?? "unknown"}',
              );
              await _removeMerchantFromFavorites(favoriteRecord);
            } else {
              final enseigneRef = widget.enseigneDoc?.reference;
              debugPrint(
                '[MERCHANT_PAGE_DEBUG] favorite_tap enseigneId=${enseigneRef?.id ?? "unknown"}',
              );
              if (enseigneRef == null) {
                return;
              }
              await _addMerchantToFavorites(enseigneRef);
            }
          },
        );
      },
    );
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

  Future<List<ImagesRecord>>? _imagesFuture;
  Future<List<HorairesRecord>>? _hoursFuture;
  Stream<DocumentSnapshot>? _merchantStream;

  void _loadMerchant() {
    final ref = widget.enseigneDoc?.reference;
    final valid = ref != null && ref.parent.path == 'enseignes';
    _merchantStream = valid ? ref.snapshots() : null;
    _imagesFuture = null;
    _hoursFuture = null;
    _ongoingGamesFuture = null;
    _ongoingGamesFutureKey = null;
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => EnseigneDetailJoueurPageModel());
    _loadMerchant();
    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'EnseigneDetailJoueurPage'});
  }

  @override
  void didUpdateWidget(covariant EnseigneDetailJoueurPageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enseigneDoc?.reference != widget.enseigneDoc?.reference) {
      _loadMerchant();
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF7F5F8),
        appBar: AppBar(
          backgroundColor: merchantPaper,
          surfaceTintColor: Colors.transparent,
          foregroundColor: merchantInk,
          elevation: 0,
          title: const Text('Votre commerçant',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          leading: IconButton(
              tooltip: 'Retour',
              onPressed: () => context.safePop(),
              icon: const Icon(Icons.arrow_back_rounded)),
        ),
        bottomNavigationBar: SafeArea(
            top: false,
            child: wrapWithModel(
                model: _model.customNavBarJoueurModel,
                updateCallback: () => safeSetState(() {}),
                child: const CustomNavBarJoueurWidget())),
        body: _merchantStream == null
            ? _unavailable()
            : StreamBuilder<DocumentSnapshot>(
                stream: _merchantStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return _unavailable();
                  if (!snapshot.hasData) {
                    return const Center(child: ProxiplayLoadingLogo(size: 42));
                  }
                  if (!snapshot.data!.exists) return _unavailable();
                  final merchant = EnseignesRecord.fromSnapshot(snapshot.data!);
                  _imagesFuture ??=
                      queryImagesRecordOnce(parent: merchant.reference);
                  _hoursFuture ??=
                      queryHorairesRecordOnce(parent: merchant.reference);
                  _imagesFuture!.ignore();
                  _hoursFuture!.ignore();
                  return RefreshIndicator(
                    color: merchantAccent,
                    onRefresh: () async {
                      setState(() {
                        _imagesFuture =
                            queryImagesRecordOnce(parent: merchant.reference);
                        _hoursFuture =
                            queryHorairesRecordOnce(parent: merchant.reference);
                        _ongoingGamesFuture = null;
                      });
                      try {
                        await Future.wait([
                          _imagesFuture!,
                          _hoursFuture!,
                          _getOngoingGamesFuture()
                        ]);
                      } catch (_) {
                        // Each section displays its own unavailable state.
                      }
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      children: [
                        _identity(merchant),
                        if (merchant.description.trim().isNotEmpty) ...[
                          const SizedBox(height: 16),
                          MerchantSection(
                              title: 'Présentation',
                              child: _MerchantDescription(
                                  text: merchant.description.trim())),
                        ],
                        const SizedBox(height: 16),
                        _practicalInformation(merchant),
                        const SizedBox(height: 16),
                        _games(merchant),
                      ],
                    ),
                  );
                },
              ),
      );

  Widget _unavailable() => const Center(
          child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.storefront_outlined, size: 48, color: merchantInk),
          SizedBox(height: 16),
          Text('Fiche commerçant indisponible',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: merchantInk,
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('Les informations de cet établissement ne sont pas accessibles.',
              textAlign: TextAlign.center),
        ]),
      ));

  void _openMerchantPhotos(List<ImagesRecord> images, int initialIndex) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (_, __, ___) => MerchantPhotoViewer(
          photoUrls: images.map((image) => image.url).toList(growable: false),
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  Widget _identity(EnseignesRecord merchant) => ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: ColoredBox(
            color: merchantPaper,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(children: [
                AspectRatio(
                  aspectRatio: 1.3,
                  child: FutureBuilder<List<ImagesRecord>>(
                    future: _imagesFuture,
                    builder: (context, snapshot) {
                      final images = (snapshot.data ?? const <ImagesRecord>[])
                          .where((image) => image.url.trim().isNotEmpty)
                          .toList();
                      if (images.isEmpty) return const MerchantPhotoContent();
                      return Stack(children: [
                        PageView.builder(
                          key: const Key('merchant-photo-carousel'),
                          itemCount: images.length,
                          onPageChanged: (index) =>
                              setState(() => _model.currentImageIndex = index),
                          itemBuilder: (context, index) => GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _openMerchantPhotos(images, index),
                            child: MerchantPhotoContent(url: images[index].url),
                          ),
                        ),
                        if (images.length > 1)
                          Positioned(
                              bottom: 12,
                              right: 12,
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                      color: merchantPaper,
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text(
                                      '${(_model.currentImageIndex.clamp(0, images.length - 1)) + 1} / ${images.length}',
                                      style: const TextStyle(
                                          color: merchantInk)))),
                      ]);
                    },
                  ),
                ),
                Positioned(
                    top: 12,
                    right: 12,
                    child: Material(
                        color: merchantPaper,
                        shape: const CircleBorder(),
                        child: _buildMerchantFavoriteButton(
                            buttonSize: 48, iconSize: 27))),
              ]),
              Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (merchant.category
                            .any((category) => category.trim().isNotEmpty)) ...[
                          Text(
                              merchant.category
                                  .where(
                                      (category) => category.trim().isNotEmpty)
                                  .map((category) =>
                                      category.replaceAll('_', ' '))
                                  .join(' · '),
                              style: const TextStyle(
                                  color: merchantAccent,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                        ],
                        Text(
                            merchant.name.trim().isEmpty
                                ? 'Commerçant'
                                : merchant.name.trim(),
                            style: const TextStyle(
                                color: merchantInk,
                                fontSize: 28,
                                height: 1.15,
                                fontWeight: FontWeight.w800)),
                        if (merchant.city.trim().isNotEmpty ||
                            merchant.address.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                              merchant.city.trim().isNotEmpty
                                  ? merchant.city.trim()
                                  : merchant.address.trim(),
                              style: const TextStyle(
                                  color: merchantInk, fontSize: 16)),
                        ],
                        if (merchant.googleRating != null) ...[
                          const SizedBox(height: 12),
                          MerchantRating(merchant: merchant),
                        ],
                      ])),
            ])),
      );

  /// Brand marks (font_awesome_flutter, already a dependency) in their
  /// official colours, all readable on white; the site keeps the app accent.
  static const _externalLinkIcons = <String, (FaIconData, Color)>{
    'Site web': (FontAwesomeIcons.globe, merchantAccent),
    'Instagram': (FontAwesomeIcons.instagram, Color(0xFFE4405F)),
    'Facebook': (FontAwesomeIcons.facebook, Color(0xFF1877F2)),
    'X': (FontAwesomeIcons.xTwitter, Color(0xFF000000)),
  };

  /// Contact actions without border or background, at least 48 x 48 px.
  static final _contactActionStyle = TextButton.styleFrom(
      foregroundColor: merchantAccent,
      backgroundColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.padded,
      shape: const StadiumBorder());

  /// Directions and phone: icon and text, no frame.
  Widget _contactTextAction(
          {required Key key,
          required IconData icon,
          required String label,
          required VoidCallback onPressed}) =>
      TextButton.icon(
          key: key,
          style: _contactActionStyle,
          onPressed: onPressed,
          icon: Icon(icon, size: 22),
          label: Text(label,
              style: const TextStyle(
                  color: merchantInk, fontWeight: FontWeight.w600)));

  /// Web site, Instagram, Facebook, X: the logo alone, in its official
  /// colour. The visible label is gone, so the name is given to screen
  /// readers (merged into the button) and shown on long press.
  Widget _externalLinkButton(String label, String url) {
    final (icon, color) =
        _externalLinkIcons[label] ?? (FontAwesomeIcons.globe, merchantAccent);
    return IconButton(
      key: Key('merchant-link-$label'),
      tooltip: label,
      style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded),
      // Outside the app (Instagram, Facebook, browser…), see external_link.dart.
      onPressed: () => openMerchantExternalLink(url),
      icon: Semantics(
          label: label,
          child: SizedBox(
              width: 26,
              height: 26,
              child: Center(child: FaIcon(icon, size: 24, color: color)))),
    );
  }

  Widget _practicalInformation(EnseignesRecord merchant) {
    final address = merchantAddress(merchant);
    final links = <(String, String?)>[
      ('Site web', _normalizeWebsiteUrl(merchant.siteWebUrl)),
      ('Instagram', _normalizeInstagramUrl(merchant.instagramLink)),
      ('Facebook', _normalizeFacebookUrl(merchant.facebookLink)),
      ('X', _normalizeTwitterUrl(merchant.twitterLink)),
    ];
    return MerchantSection(
        title: 'Informations pratiques',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.location_on_outlined, color: merchantAccent),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
                    address.isEmpty ? 'Adresse non renseignée' : address,
                    style: const TextStyle(color: merchantInk, height: 1.5))),
          ]),
          const SizedBox(height: 8),
          // Practical actions and social profiles intentionally occupy two
          // rows: contact first, then a single horizontal strip of logos.
          Wrap(
              key: const Key('merchant-contact-row'),
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (address.isNotEmpty)
                  _contactTextAction(
                      key: const Key('merchant-contact-directions'),
                      icon: Icons.directions_outlined,
                      label: 'Itinéraire',
                      onPressed: () => openMerchantExternalLink(
                          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}')),
                if (merchant.phoneNumber.trim().isNotEmpty)
                  _contactTextAction(
                      key: const Key('merchant-contact-phone'),
                      icon: Icons.phone_outlined,
                      label: merchant.phoneNumber.trim(),
                      onPressed: () =>
                          launchURL('tel:${merchant.phoneNumber.trim()}')),
              ]),
          if (links.any((link) => link.$2 != null)) ...[
            const SizedBox(height: 2),
            // Social icons remain together; horizontal scrolling is only a
            // fallback for exceptionally narrow screens or large text.
            SingleChildScrollView(
              key: const Key('merchant-social-row'),
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final link in links)
                  if (link.$2 != null) _externalLinkButton(link.$1, link.$2!),
              ]),
            ),
          ],
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1, color: Color(0xFFF0ECF1))),
          const Text('Horaires',
              style: TextStyle(
                  color: merchantInk,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const SizedBox(height: 8),
          FutureBuilder<List<HorairesRecord>>(
              future: _hoursFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Horaires indisponibles');
                }
                if (!snapshot.hasData) {
                  return const Text('Chargement des horaires…');
                }
                return MerchantTodayHours(hours: snapshot.data!);
              }),
        ]));
  }

  Widget _games(EnseignesRecord merchant) => FutureBuilder<List<GamesRecord>>(
        future: _getOngoingGamesFuture(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('Les jeux sont momentanément indisponibles.');
          }
          if (!snapshot.hasData) {
            return const Center(child: ProxiplayLoadingLogo(size: 32));
          }
          final games = snapshot.data!.where(_isGameVisibleForPlayer).toList();
          if (games.isEmpty) {
            return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text('Aucun jeu en cours actuellement.',
                    style: TextStyle(color: Color(0xFF656171))));
          }
          return MerchantSection(
              title: 'Jeux en cours',
              child: Column(
                  children: games
                      .map((game) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Material(
                              color: const Color(0xFFF8F5F8),
                              borderRadius: BorderRadius.circular(18),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                  onTap: () => context.pushNamed(
                                        JeuDetailJoueurPageWidget.routeName,
                                        queryParameters: {
                                          'gameDoc': serializeParam(
                                              game, ParamType.Document),
                                          'enseigneDoc': serializeParam(
                                              merchant, ParamType.Document),
                                        }.withoutNulls,
                                        extra: <String, dynamic>{
                                          'gameDoc': game,
                                          'enseigneDoc': merchant
                                        },
                                      ),
                                  child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(children: [
                                        ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: SizedBox(
                                                width: 72,
                                                height: 86,
                                                child: MerchantPhotoContent(
                                                    url: game.photo))),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              Text(game.name,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      color: merchantInk,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                              const SizedBox(height: 6),
                                              Text(_formatPrizeLabel(game),
                                                  style: const TextStyle(
                                                      color: merchantAccent,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                              if (game.endDate != null)
                                                Text(
                                                    'Jusqu’au ${dateTimeFormat('d/M/y', game.endDate)}',
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            Color(0xFF656171))),
                                            ])),
                                        const Icon(Icons.chevron_right_rounded,
                                            color: merchantAccent),
                                      ]))),
                            ),
                          ))
                      .toList()));
        },
      );
}

/// Full-screen, read-only merchant gallery. The separate route means Android
/// Back returns to the merchant detail without changing its scroll position.
class MerchantPhotoViewer extends StatefulWidget {
  const MerchantPhotoViewer({
    super.key,
    required this.photoUrls,
    required this.initialIndex,
  });

  final List<String> photoUrls;
  final int initialIndex;

  @override
  State<MerchantPhotoViewer> createState() => _MerchantPhotoViewerState();
}

class _MerchantPhotoViewerState extends State<MerchantPhotoViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index =
        widget.initialIndex.clamp(0, widget.photoUrls.length - 1).toInt();
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multiplePhotos = widget.photoUrls.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              key: const Key('merchant-photo-viewer-pages'),
              controller: _controller,
              itemCount: widget.photoUrls.length,
              onPageChanged: (index) => setState(() => _index = index),
              itemBuilder: (context, index) => Center(
                child: ProxiplayNetworkImage(
                  imageUrl: widget.photoUrls[index],
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  errorBackgroundColor: Colors.black,
                  errorIconColor: Colors.white70,
                ),
              ),
            ),
            if (multiplePhotos)
              Positioned(
                top: 12,
                left: 16,
                child: Semantics(
                  label: 'Photo ${_index + 1} sur ${widget.photoUrls.length}',
                  child: Text(
                    '${_index + 1} / ${widget.photoUrls.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              right: 4,
              child: IconButton(
                key: const Key('merchant-photo-viewer-close'),
                tooltip: 'Fermer',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MerchantDescription extends StatefulWidget {
  const _MerchantDescription({required this.text});
  final String text;
  @override
  State<_MerchantDescription> createState() => _MerchantDescriptionState();
}

class _MerchantDescriptionState extends State<_MerchantDescription> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        const style =
            TextStyle(color: Color(0xFF656171), height: 1.6, fontSize: 15);
        final painter = TextPainter(
          text: TextSpan(
              text: widget.text,
              style: DefaultTextStyle.of(context).style.merge(style)),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 5,
        )..layout(maxWidth: constraints.maxWidth);
        final truncated = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.text,
                maxLines: expanded ? null : 5,
                overflow:
                    expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: style),
            if (truncated)
              TextButton(
                  style: TextButton.styleFrom(foregroundColor: merchantAccent),
                  onPressed: () => setState(() => expanded = !expanded),
                  child: Text(expanded ? 'Voir moins' : 'Lire la suite')),
          ],
        );
      });
}
