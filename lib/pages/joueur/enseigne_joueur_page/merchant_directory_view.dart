import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '/components/merchant_presentation.dart';
import '/utils/merchant_category_session_order.dart';
import 'merchant_directory_logic.dart';
import 'merchant_directory_source.dart';

const _muted = Color(0xFF656171);
const _cardBorder = Color(0xFFF0ECF1);
const _activeGameText = Color(0xFF1B7A43);
const _activeGameBackground = Color(0xFFE3F4EA);
const _searchBackground = Color(0xFFD4D3E7);
const _searchBorder = Color(0xFFE0E3E7);
const _searchText = Color(0xFF605F83);

enum _FilterKind { all, activeGames, category }

class _Filter {
  const _Filter(this.kind, [this.category = '']);
  static const all = _Filter(_FilterKind.all);
  static const activeGames = _Filter(_FilterKind.activeGames);
  final _FilterKind kind;
  final String category;

  @override
  bool operator ==(Object other) =>
      other is _Filter && other.kind == kind && other.category == category;

  @override
  int get hashCode => Object.hash(kind, category);
}

/// Compact list of merchants with search and one active filter, in a random
/// order drawn once per opening (historic behaviour).
///
/// Firestore cannot order randomly, and a stored random field would only
/// rotate one fixed permutation. The directory therefore reads the merchants
/// once at opening ([batchSize] per query, at most [maxMerchants]), shuffles
/// the whole list once with [random], and keeps that order for the session:
/// scrolling, filters and search only read it. Cards and photos are still
/// built progressively. Only beyond [maxMerchants] are further batches
/// appended on demand, each shuffled on its own: that tail is not part of the
/// global shuffle.
///
/// Other reads: one ongoing-games query for the badge (no ranking), one
/// favorites stream; a photo is read once, only for a displayed card.
class MerchantDirectoryView extends StatefulWidget {
  const MerchantDirectoryView({
    super.key,
    required this.source,
    required this.knownCategories,
    required this.onOpenMerchant,
    this.batchSize = 100,
    this.maxMerchants = 500,
    this.random,
    this.searchDebounce = const Duration(milliseconds: 300),
    this.now = DateTime.now,
  });

  final MerchantDirectorySource source;
  final List<String> knownCategories;
  final void Function(DirectoryMerchant merchant) onOpenMerchant;
  final int batchSize;
  final int maxMerchants;

  /// Session shuffle source; a new one per opening when null.
  final Random? random;
  final Duration searchDebounce;
  final DateTime Function() now;

  @override
  State<MerchantDirectoryView> createState() => _MerchantDirectoryViewState();
}

class _MerchantDirectoryViewState extends State<MerchantDirectoryView> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  String _query = '';
  _Filter _filter = _Filter.all;

  late final Random _sessionRandom = widget.random ?? Random();
  ActiveGamesResult _active = ActiveGamesResult.unavailable;

  /// Session order: drawn once, then only appended to (beyond the cap).
  final List<DirectoryMerchant> _paged = [];
  final Set<String> _pagedIds = {};
  Object? _cursor;
  bool _hasMore = true;
  bool _initialLoading = true;
  bool _loadingMore = false;
  Object? _initialError;
  Object? _moreError;

  StreamSubscription<Map<String, List<Object>>>? _favoritesSubscription;
  bool _favoritesEnabled = false;
  Map<String, List<Object>> _favorites = const {};
  final Set<String> _favoritePending = {};

  final Map<String, Future<String>> _photos = {};
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _listenFavorites();
    _loadInitial();
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _favoritesSubscription?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _listenFavorites() {
    final stream = widget.source.favorites();
    _favoritesEnabled = stream != null;
    _favoritesSubscription = stream?.listen(
      (value) {
        if (!mounted) return;
        setState(() {
          _favorites = value;
        });
      },
      onError: (Object _) {
        // Favorites are an optional convenience. Keep the directory usable
        // if their stream is temporarily unavailable.
      },
    );
  }

  Future<void> _loadInitial() async {
    final generation = ++_generation;
    setState(() {
      _initialLoading = true;
      _initialError = null;
      _moreError = null;
    });
    final activeFuture = widget.source
        .fetchActiveGames(widget.now())
        .catchError((Object _) => ActiveGamesResult.unavailable);
    try {
      final loaded = <DirectoryMerchant>[];
      final seen = <String>{};
      Object? cursor;
      var hasMore = true;
      while (hasMore && loaded.length < widget.maxMerchants) {
        final remaining = widget.maxMerchants - loaded.length;
        final page = await widget.source.fetchPage(
            cursor: cursor,
            limit: remaining < widget.batchSize ? remaining : widget.batchSize);
        if (!mounted || generation != _generation) return;
        for (final merchant in page.merchants) {
          if (seen.add(merchant.id)) loaded.add(merchant);
        }
        cursor = page.cursor;
        hasMore = page.hasMore;
      }
      final active = await activeFuture;
      if (!mounted || generation != _generation) return;
      // One global shuffle for the whole session.
      final ordered = shuffledSessionCopy(loaded, _sessionRandom);
      setState(() {
        _active = active;
        _paged
          ..clear()
          ..addAll(ordered);
        _pagedIds
          ..clear()
          ..addAll(ordered.map((m) => m.id));
        _cursor = cursor;
        _hasMore = hasMore;
        _initialLoading = false;
      });
      _fillViewport();
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _initialLoading = false;
        _initialError = error;
      });
    }
  }

  /// Only beyond [MerchantDirectoryView.maxMerchants]: appends the next batch,
  /// shuffled on its own, after the session order (never reordering it).
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _initialLoading) return;
    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      var added = 0;
      for (var round = 0; round < 3 && _hasMore && added == 0; round++) {
        final page = await widget.source
            .fetchPage(cursor: _cursor, limit: widget.batchSize);
        if (!mounted || generation != _generation) return;
        final fresh =
            page.merchants.where((m) => !_pagedIds.contains(m.id)).toList();
        _paged.addAll(shuffledSessionCopy(fresh, _sessionRandom));
        _pagedIds.addAll(fresh.map((m) => m.id));
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        added += fresh.length;
      }
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _fillViewport();
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingMore = false;
        _moreError = error;
      });
    }
  }

  /// In "Tous" without search, keep loading while the list cannot scroll yet.
  void _fillViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_filter == _Filter.all &&
          _query.isEmpty &&
          _hasMore &&
          _moreError == null &&
          _scrollController.position.maxScrollExtent <= 0) {
        _loadMore();
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (_moreError == null &&
        position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  /// "Tous": every merchant, with or without a known category, in the
  /// session order. No merchant is ranked first for having a game.
  List<DirectoryMerchant> get _baseList => _paged;

  List<DirectoryMerchant> get _visible {
    final source = switch (_filter.kind) {
      _FilterKind.all => _baseList,
      // Deliberately use the exact same predicate as the green card badge.
      _FilterKind.activeGames => _baseList.where(_hasActiveGame).toList(),
      _FilterKind.category => _baseList
          .where((m) => m.categories.contains(_filter.category))
          .toList(),
    };
    return source.where((m) => merchantMatchesQuery(m, _query)).toList();
  }

  bool _hasActiveGame(DirectoryMerchant merchant) =>
      _active.merchantIds.contains(merchant.id);

  /// Results come from loaded pages only while more pages exist.
  bool get _resultsArePartial =>
      _hasMore &&
      (_filter.kind == _FilterKind.category ||
          _filter.kind == _FilterKind.activeGames ||
          _query.isNotEmpty);

  void _selectFilter(_Filter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(widget.searchDebounce, () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
    setState(() {}); // clear button visibility
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() => _query = '');
  }

  bool _isFavorite(DirectoryMerchant merchant) {
    final stored = _favorites.containsKey(merchant.id);
    return _favoritePending.contains(merchant.id) ? !stored : stored;
  }

  Future<void> _toggleFavorite(DirectoryMerchant merchant) async {
    if (_favoritePending.contains(merchant.id)) return;
    final handles = _favorites[merchant.id];
    setState(() => _favoritePending.add(merchant.id));
    try {
      if (handles != null && handles.isNotEmpty) {
        await widget.source.removeFavorite(handles);
      } else {
        await widget.source.addFavorite(merchant.id);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
            content: Text('Impossible de mettre à jour vos favoris.')));
      }
    } finally {
      if (mounted) {
        // The stream carries the stored state; the pending flip ends here.
        setState(() => _favoritePending.remove(merchant.id));
      }
    }
  }

  Future<String> _photo(DirectoryMerchant merchant) => _photos.putIfAbsent(
      merchant.id,
      () => widget.source.photoUrl(merchant).catchError((Object _) => ''));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchField(),
        const SizedBox(height: 10),
        _buildFilters(),
        const SizedBox(height: 10),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildSearchField() => Container(
        decoration: BoxDecoration(
          color: _searchBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _searchBorder),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          const Icon(Icons.search_rounded, color: merchantInk, size: 22),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              key: const Key('directory-search'),
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: _searchText, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Rechercher un commerce, une catégorie…',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              key: const Key('directory-search-clear'),
              tooltip: 'Effacer la recherche',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.cancel_outlined, color: merchantInk),
              onPressed: _clearSearch,
            ),
        ]),
      );

  Widget _buildFilters() {
    final categories =
        availableDirectoryCategories(_paged, widget.knownCategories);
    final filters = <(_Filter, String, Key)>[
      (_Filter.all, 'Tous', const Key('directory-filter-all')),
      (
        _Filter.activeGames,
        'Jeux en cours',
        const Key('directory-filter-active-games')
      ),
      for (final category in categories)
        (
          _Filter(_FilterKind.category, category),
          category,
          Key('directory-filter-category-$category'),
        ),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (filter, label, key) = filters[index];
          final selected = filter == _filter;
          return ChoiceChip(
            key: key,
            label: Text(label),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => _selectFilter(filter),
            labelStyle: TextStyle(
              color: selected ? Colors.white : merchantInk,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            selectedColor: merchantInk,
            backgroundColor: merchantPaper,
            side: BorderSide(color: selected ? merchantInk : _cardBorder),
            shape: const StadiumBorder(),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_initialLoading) {
      return const _DirectoryMessage(
        key: Key('directory-loading'),
        loading: true,
        title: 'Chargement des commerces…',
      );
    }
    if (_initialError != null) {
      return _DirectoryMessage(
        key: const Key('directory-error'),
        icon: Icons.wifi_off_rounded,
        title: 'Impossible de charger les commerces',
        body: 'Vérifiez votre connexion puis réessayez.',
        actionLabel: 'Réessayer',
        onAction: _loadInitial,
      );
    }
    final merchants = _visible;
    if (merchants.isEmpty) {
      if (_filter == _Filter.all && _query.isEmpty && !_hasMore) {
        return const _DirectoryMessage(
          key: Key('directory-empty'),
          icon: Icons.storefront_outlined,
          title: 'Aucun commerce pour le moment',
          body: 'Les commerces partenaires apparaîtront ici.',
        );
      }
      if (_filter == _Filter.activeGames && _query.isEmpty && !_hasMore) {
        return const _DirectoryMessage(
          key: Key('directory-no-active-games'),
          icon: Icons.sports_esports_outlined,
          title: 'Aucun jeu en cours',
          body: 'Revenez bientôt découvrir les prochains jeux.',
          compact: true,
          expand: false,
        );
      }
      return ListView(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _DirectoryMessage(
            key: const Key('directory-no-results'),
            icon: Icons.search_off_rounded,
            title: 'Aucun résultat',
            body: _resultsArePartial
                ? 'Aucun commerce chargé ne correspond.'
                : 'Aucun commerce ne correspond à votre recherche.',
            expand: false,
          ),
          if (_resultsArePartial || _moreError != null)
            _DirectoryFooter(
              loading: _loadingMore,
              error: _moreError != null,
              partial: _resultsArePartial,
              loadedCount: _baseList.length,
              onLoadMore: _loadMore,
            ),
        ],
      );
    }

    final showFooter = _hasMore || _loadingMore || _moreError != null;
    return ListView.separated(
      key: const Key('directory-list'),
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: merchants.length + (showFooter ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == merchants.length) {
          return _DirectoryFooter(
            loading: _loadingMore,
            error: _moreError != null,
            partial: _resultsArePartial,
            loadedCount: _baseList.length,
            onLoadMore: _loadMore,
          );
        }
        final merchant = merchants[index];
        return DirectoryMerchantCard(
          key: Key('directory-card-${merchant.id}'),
          merchant: merchant,
          hasActiveGame: _hasActiveGame(merchant),
          photo: _photo(merchant),
          isFavorite: _favoritesEnabled ? _isFavorite(merchant) : null,
          favoriteBusy: _favoritePending.contains(merchant.id),
          onTap: () => widget.onOpenMerchant(merchant),
          onFavorite: () => _toggleFavorite(merchant),
        );
      },
    );
  }
}

class _DirectoryFooter extends StatelessWidget {
  const _DirectoryFooter({
    required this.loading,
    required this.error,
    required this.partial,
    required this.loadedCount,
    required this.onLoadMore,
  });

  final bool loading;
  final bool error;
  final bool partial;
  final int loadedCount;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        key: Key('directory-loading-more'),
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
            child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5))),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        if (error)
          const Text('Le chargement a échoué.',
              key: Key('directory-more-error'),
              style: TextStyle(color: _muted)),
        TextButton(
          key: const Key('directory-load-more'),
          onPressed: onLoadMore,
          style: TextButton.styleFrom(foregroundColor: merchantAccent),
          child: Text(error ? 'Réessayer' : 'Voir plus de commerces'),
        ),
        // Discreet but explicit: the search is not exhaustive yet.
        if (partial && !error)
          Text(
            'Recherche effectuée uniquement parmi les $loadedCount '
            'commerces chargés.',
            key: const Key('directory-partial-notice'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
      ]),
    );
  }
}

class _DirectoryMessage extends StatelessWidget {
  const _DirectoryMessage({
    super.key,
    required this.title,
    this.body,
    this.icon,
    this.loading = false,
    this.actionLabel,
    this.onAction,
    this.expand = true,
    this.compact = false,
  });

  final String title;
  final String? body;
  final IconData? icon;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool expand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding:
          EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 16 : 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (loading)
          const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3))
        else if (icon != null)
          Icon(icon, size: 40, color: merchantInk),
        const SizedBox(height: 12),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: merchantInk, fontSize: 16, fontWeight: FontWeight.w700)),
        if (body != null) ...[
          const SizedBox(height: 6),
          Text(body!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, height: 1.35)),
        ],
        if (actionLabel != null) ...[
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(backgroundColor: merchantAccent),
            child: Text(actionLabel!),
          ),
        ],
      ]),
    );
    if (!expand) return content;
    return SingleChildScrollView(child: Center(child: content));
  }
}

/// Horizontal merchant card (reference design): photo flush on the left over
/// the full card height, name, two-line description, Google rating, optional
/// "Jeu en cours" badge and an independent favorite heart.
class DirectoryMerchantCard extends StatelessWidget {
  const DirectoryMerchantCard({
    super.key,
    required this.merchant,
    required this.hasActiveGame,
    required this.photo,
    required this.onTap,
    required this.onFavorite,
    this.isFavorite,
    this.favoriteBusy = false,
  });

  final DirectoryMerchant merchant;
  final bool hasActiveGame;
  final Future<String> photo;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  /// null hides the heart (no signed-in player).
  final bool? isFavorite;
  final bool favoriteBusy;

  static const photoWidth = 96.0;
  static const compactPhotoWidth = 80.0;
  static const minHeight = 84.0;

  @override
  Widget build(BuildContext context) {
    final description = merchant.description.trim();
    final rating = merchant.ratingLabel;
    final ratingText = rating == null
        ? null
        : merchant.googleReviewsCount != null
            ? '$rating Google (${merchant.googleReviewsCount} avis)'
            : '$rating Google';

    const nameStyle = TextStyle(
        color: merchantInk,
        fontSize: 15.5,
        fontWeight: FontWeight.w800,
        height: 1.2);
    const ratingStyle = TextStyle(color: merchantInk, fontSize: 12.5);
    final content = LayoutBuilder(builder: (context, constraints) {
      // Measured with the real text scale: the badge is never cut, it moves
      // to the line where it fits completely.
      final placement = hasActiveGame
          ? _badgePlacement(context,
              maxWidth: constraints.maxWidth,
              name: merchant.displayName,
              nameStyle: nameStyle,
              ratingText: ratingText,
              ratingStyle: ratingStyle)
          : _BadgePlacement.none;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                merchant.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: nameStyle,
              ),
            ),
            if (placement == _BadgePlacement.besideName) ...[
              const SizedBox(width: 6),
              const _ActiveGameBadge(),
            ],
          ]),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(color: _muted, fontSize: 12.5, height: 1.3),
            ),
          ],
          if (ratingText != null ||
              placement == _BadgePlacement.ratingLine) ...[
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (ratingText != null) ...[
                const Icon(Icons.star_rounded,
                    color: Color(0xFFF5AB16), size: 17),
                const SizedBox(width: 3),
                // Wraps to a second line rather than being cut.
                Flexible(
                  child: Text(ratingText,
                      key: const Key('directory-rating-text'),
                      softWrap: true,
                      style: ratingStyle),
                ),
              ],
              if (placement == _BadgePlacement.ratingLine) ...[
                if (ratingText != null) const SizedBox(width: 6),
                const _ActiveGameBadge(),
              ],
            ]),
          ],
          if (placement == _BadgePlacement.ownLine) ...[
            const SizedBox(height: 4),
            // Extreme text scale on a 320 px screen: shrink slightly, never cut.
            const FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _ActiveGameBadge(),
            ),
          ],
        ],
      );
    });

    return Material(
      color: merchantPaper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(builder: (context, constraints) {
          // Narrower photo on 320 px screens: the room goes to the rating and
          // the badge, which are never cut.
          final photoWidth = constraints.maxWidth < 320
              ? compactPhotoWidth
              : DirectoryMerchantCard.photoWidth;
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minHeight),
            child: Stack(children: [
              Padding(
                padding: EdgeInsets.only(left: photoWidth),
                child: Row(children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                      child: content,
                    ),
                  ),
                  if (isFavorite != null)
                    IconButton(
                      key: Key('directory-favorite-${merchant.id}'),
                      tooltip: isFavorite!
                          ? 'Retirer des favoris'
                          : 'Ajouter aux favoris',
                      onPressed: favoriteBusy ? null : onFavorite,
                      icon: Icon(
                        isFavorite!
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: merchantAccent,
                        size: 24,
                      ),
                    )
                  else
                    const SizedBox(width: 8),
                ]),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: photoWidth,
                child: FutureBuilder<String>(
                  future: photo,
                  builder: (context, snapshot) =>
                      MerchantPhotoContent(url: snapshot.data ?? ''),
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }
}

const _activeGameStyle = TextStyle(
    color: _activeGameText, fontSize: 11.5, fontWeight: FontWeight.w700);

enum _BadgePlacement { none, besideName, ratingLine, ownLine }

double _textWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
        text: text, style: DefaultTextStyle.of(context).style.merge(style)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Width of [_ActiveGameBadge]: padding 7 + icon 14 + gap 4 + text + padding 7.
double _badgeWidth(BuildContext context) =>
    32 + _textWidth(context, 'Jeu en cours', _activeGameStyle) + 1;

_BadgePlacement _badgePlacement(
  BuildContext context, {
  required double maxWidth,
  required String name,
  required TextStyle nameStyle,
  required String? ratingText,
  required TextStyle ratingStyle,
}) {
  final badge = _badgeWidth(context);
  if (_textWidth(context, name, nameStyle) + 6 + badge <= maxWidth) {
    return _BadgePlacement.besideName;
  }
  final rating = ratingText == null
      ? 0.0
      : 20 + _textWidth(context, ratingText, ratingStyle) + 6;
  if (rating + badge <= maxWidth) return _BadgePlacement.ratingLine;
  return _BadgePlacement.ownLine;
}

class _ActiveGameBadge extends StatelessWidget {
  const _ActiveGameBadge();

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('directory-active-game-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: _activeGameBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.sports_esports_rounded, color: _activeGameText, size: 14),
          SizedBox(width: 4),
          Text('Jeu en cours',
              key: Key('directory-active-game-text'),
              maxLines: 1,
              softWrap: false,
              style: _activeGameStyle),
        ]),
      );
}
