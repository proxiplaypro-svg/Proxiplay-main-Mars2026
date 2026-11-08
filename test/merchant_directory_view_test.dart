import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/pages/joueur/enseigne_joueur_page/merchant_directory_logic.dart';
import 'package:proxi_play/pages/joueur/enseigne_joueur_page/merchant_directory_source.dart';
import 'package:proxi_play/pages/joueur/enseigne_joueur_page/merchant_directory_view.dart';
import 'package:proxi_play/utils/merchant_category_session_order.dart';

const categories = [
  'Alimentation',
  'Restaurants & bars',
  'Beauté & bien-être',
];

/// In-memory source: no Firebase, every call is counted.
class FakeSource implements MerchantDirectorySource {
  FakeSource({
    required this.merchants,
    this.activeIds = const {},
    this.activeComplete = true,
    this.signedIn = true,
    Map<String, List<Object>>? favorites,
  }) {
    if (favorites != null) favoriteState = favorites;
  }

  final List<DirectoryMerchant> merchants;
  Set<String> activeIds;
  bool activeComplete;
  final bool signedIn;
  Map<String, List<Object>> favoriteState = {};
  final _favorites = StreamController<Map<String, List<Object>>>.broadcast();

  int pageCalls = 0;
  int activeCalls = 0;
  final byIdCalls = <List<String>>[];
  final photoCalls = <String>[];
  final added = <String>[];
  final removed = <List<Object>>[];
  int favoritesStreams = 0;
  Object? pageError;
  bool failActive = false;

  /// Repeats the previous page's last merchant at the start of each next page.
  bool overlapPages = false;

  @override
  Future<DirectoryPage> fetchPage({Object? cursor, required int limit}) async {
    pageCalls++;
    if (pageError != null) throw pageError!;
    final start = (cursor as int?) ?? 0;
    final end =
        start + limit > merchants.length ? merchants.length : start + limit;
    return DirectoryPage(
      merchants: [
        if (overlapPages && start > 0) merchants[start - 1],
        ...merchants.sublist(start, end),
      ],
      cursor: end,
      hasMore: end < merchants.length,
    );
  }

  @override
  Future<List<DirectoryMerchant>> fetchByIds(List<String> ids) async {
    byIdCalls.add(ids);
    return merchants.where((m) => ids.contains(m.id)).toList();
  }

  @override
  Future<ActiveGamesResult> fetchActiveGames(DateTime now) async {
    activeCalls++;
    if (failActive) throw StateError('games unavailable');
    return ActiveGamesResult(merchantIds: activeIds, complete: activeComplete);
  }

  @override
  Stream<Map<String, List<Object>>>? favorites() {
    if (!signedIn) return null;
    favoritesStreams++;
    scheduleMicrotask(() => _favorites.add(favoriteState));
    return _favorites.stream;
  }

  void emitFavorites(Map<String, List<Object>> value) {
    favoriteState = value;
    _favorites.add(value);
  }

  @override
  Future<void> addFavorite(String merchantId) async {
    added.add(merchantId);
    emitFavorites({
      ...favoriteState,
      merchantId: ['fav/$merchantId']
    });
  }

  @override
  Future<void> removeFavorite(List<Object> favoriteHandles) async {
    removed.add(favoriteHandles);
    emitFavorites(Map.of(favoriteState)
      ..removeWhere((_, handles) => handles == favoriteHandles));
  }

  @override
  Future<String> photoUrl(DirectoryMerchant merchant) async {
    photoCalls.add(merchant.id);
    return '';
  }
}

DirectoryMerchant merchant(
  String id, {
  String? name,
  String description = '',
  String city = 'Lyon',
  List<String> cats = const ['Alimentation'],
  double? rating,
  int? reviews,
}) =>
    DirectoryMerchant(
      id: id,
      name: name ?? 'Commerce $id',
      description: description,
      city: city,
      categories: cats,
      googleRating: rating,
      googleReviewsCount: reviews,
    );

final opened = <DirectoryMerchant>[];

/// List.shuffle swaps position `length - 1` with `nextInt(length)`:
/// always answering `max - 1` keeps the original order.
class KeepOrderRandom implements Random {
  @override
  int nextInt(int max) => max - 1;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

Future<void> pumpDirectory(
  WidgetTester tester,
  FakeSource source, {
  Size size = const Size(390, 844),
  double textScale = 1.0,
  int batchSize = 100,
  int maxMerchants = 500,
  Random? random,
  Object? openingKey,
}) async {
  opened.clear();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data:
          MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: MerchantDirectoryView(
            key: ObjectKey(openingKey ?? source),
            source: source,
            knownCategories: categories,
            onOpenMerchant: opened.add,
            batchSize: batchSize,
            maxMerchants: maxMerchants,
            random: random ?? KeepOrderRandom(),
            now: () => DateTime(2026, 11, 8, 12),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('directory-search')), text);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

List<String> cardIds(WidgetTester tester) => tester
    .widgetList<DirectoryMerchantCard>(find.byType(DirectoryMerchantCard))
    .map((card) => card.merchant.id)
    .toList();

void main() {
  testWidgets(
      'cartes compactes : nom, description sur 2 lignes, note, badge seulement '
      'pour un jeu confirmé, aucun titre de catégorie', (tester) async {
    final source = FakeSource(merchants: [
      merchant('a',
          name: 'Boulangerie Martin',
          description: 'Pain au levain, viennoiseries maison et pâtisseries '
                  'fines préparées chaque matin sur place. ' *
              3,
          rating: 4.56,
          reviews: 128),
      merchant('b', name: 'Bar du Port', cats: ['Restaurants & bars']),
    ], activeIds: {
      'b'
    });
    await pumpDirectory(tester, source);

    expect(find.text('Boulangerie Martin'), findsOneWidget);
    expect(find.text('4,6 Google (128 avis)'), findsOneWidget);
    final description =
        tester.widget<Text>(find.textContaining('Pain au levain'));
    expect(description.maxLines, 2);
    expect(description.overflow, TextOverflow.ellipsis);
    expect(
        find.byKey(const Key('directory-active-game-badge')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('directory-card-b')),
            matching: find.text('Jeu en cours')),
        findsOneWidget);
    // Category names only appear in the filter chips, never as list titles.
    expect(
        find.descendant(
            of: find.byKey(const Key('directory-list')),
            matching: find.text('Restaurants & bars')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'lectures : une requête jeux, une page, les commerces actifs par id, '
      'une photo par carte affichée et jamais relue', (tester) async {
    final source = FakeSource(
      merchants: [for (var i = 0; i < 12; i++) merchant('m$i')],
      activeIds: {'m7', 'm9'},
    );
    await pumpDirectory(tester, source);

    expect(source.activeCalls, 1);
    expect(source.pageCalls, 1);
    expect(source.byIdCalls, isEmpty,
        reason: 'aucun commerce n’est relu pour être placé en tête');
    expect(source.favoritesStreams, 1, reason: 'un seul flux favoris par page');
    final firstPhotos = source.photoCalls.toList();
    expect(firstPhotos.toSet().length, firstPhotos.length);
    expect(firstPhotos.length, lessThan(12),
        reason: 'les cartes hors écran ne lisent pas leur photo');

    await tester.tap(find.byKey(const Key('directory-filter-favorites')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('directory-filter-all')));
    await tester.pumpAndSettle();
    expect(source.photoCalls, firstPhotos,
        reason: 'photo mise en cache pour la page');
    expect(source.pageCalls, 1);
  });

  testWidgets(
      'aucune priorité aux jeux en cours : l’ordre de session est conservé, '
      'le badge reste affiché', (tester) async {
    final merchants = [
      merchant('a', name: 'Alpha'),
      merchant('b', name: 'Bravo'),
      merchant('c', name: 'Charlie'),
    ];
    var source = FakeSource(merchants: merchants, activeIds: {'c'});
    await pumpDirectory(tester, source);
    expect(cardIds(tester), ['a', 'b', 'c']);
    expect(source.byIdCalls, isEmpty);

    source = FakeSource(
        merchants: merchants, activeIds: {'c'}, activeComplete: false);
    await pumpDirectory(tester, source);
    expect(cardIds(tester), ['a', 'b', 'c']);
    expect(source.byIdCalls, isEmpty);
    expect(
        find.descendant(
            of: find.byKey(const Key('directory-card-c')),
            matching: find.text('Jeu en cours')),
        findsOneWidget);

    source = FakeSource(merchants: merchants)..failActive = true;
    await pumpDirectory(tester, source);
    expect(cardIds(tester), ['a', 'b', 'c']);
    expect(find.text('Jeu en cours'), findsNothing,
        reason: 'sans source fiable, aucun badge');
  });

  testWidgets(
      'recherche avec délai, insensible à la casse et aux accents, par nom, '
      'catégorie et ville', (tester) async {
    final source = FakeSource(merchants: [
      merchant('a', name: 'Crèmerie Dupont', city: 'Colmar'),
      merchant('b', name: 'Institut Zen', cats: ['Beauté & bien-être']),
      merchant('c', name: 'Le Comptoir', city: 'Sélestat'),
    ]);
    await pumpDirectory(tester, source);

    await tester.enterText(find.byKey(const Key('directory-search')), 'creme');
    await tester.pump(const Duration(milliseconds: 100));
    expect(cardIds(tester), ['a', 'b', 'c'], reason: 'pas avant le délai');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(cardIds(tester), ['a']);

    await search(tester, 'BEAUTE');
    expect(cardIds(tester), ['b']);
    await search(tester, 'selestat');
    expect(cardIds(tester), ['c']);

    await search(tester, 'piscine');
    expect(find.byKey(const Key('directory-no-results')), findsOneWidget);
    expect(find.text('Aucun commerce ne correspond à votre recherche.'),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('directory-search-clear')));
    await tester.pumpAndSettle();
    expect(cardIds(tester), ['a', 'b', 'c']);
    expect(source.pageCalls, 1, reason: 'la recherche ne lit rien');
  });

  testWidgets(
      'une recherche sur des commerces partiellement chargés le dit et '
      'propose d’en charger plus', (tester) async {
    final source = FakeSource(merchants: [
      for (var i = 0; i < 10; i++) merchant('m$i'),
      merchant('z', name: 'Zinc Café'),
    ]);
    await pumpDirectory(tester, source, batchSize: 10, maxMerchants: 10);
    expect(source.pageCalls, 1, reason: 'plafond atteint : 10 chargés');

    await search(tester, 'zinc');
    expect(find.byKey(const Key('directory-no-results')), findsOneWidget);
    expect(find.text('Aucun commerce chargé ne correspond.'), findsOneWidget);
    expect(
        find.text('Recherche effectuée uniquement parmi les 10 commerces '
            'chargés.'),
        findsOneWidget);
    expect(find.text('Voir plus de commerces'), findsOneWidget);
    await tester.tap(find.byKey(const Key('directory-load-more')));
    await tester.pumpAndSettle();
    expect(cardIds(tester), ['z']);
    expect(find.byKey(const Key('directory-partial-notice')), findsNothing,
        reason: 'tout est chargé : la recherche est complète');
  });

  testWidgets(
      'filtres : Tous, Favoris puis catégories présentes ; un seul actif',
      (tester) async {
    final source = FakeSource(merchants: [
      merchant('a', cats: ['Alimentation']),
      merchant('b', cats: ['Restaurants & bars']),
      merchant('c', cats: ['Autre']),
      merchant('d', cats: []),
    ]);
    // Wide surface: the horizontal chip list builds lazily.
    await pumpDirectory(tester, source, size: const Size(1400, 844));

    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .map((chip) => (chip.label as Text).data)
        .toList();
    expect(chips,
        ['Tous', 'Favoris', 'Alimentation', 'Restaurants & bars', 'Autre']);
    expect(cardIds(tester), ['a', 'b', 'c', 'd'],
        reason: 'Tous inclut les commerces sans catégorie connue ou sans '
            'catégorie');

    await tester.tap(
        find.byKey(const Key('directory-filter-category-Restaurants & bars')));
    await tester.pumpAndSettle();
    expect(cardIds(tester), ['b']);
    final selected = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((chip) => chip.selected)
        .map((chip) => (chip.label as Text).data)
        .toList();
    expect(selected, ['Restaurants & bars']);
  });

  testWidgets(
      'favoris : le cœur agit seul, sans ouvrir la fiche ; filtre Favoris '
      'complet, y compris hors des pages chargées', (tester) async {
    final source = FakeSource(
      merchants: [
        merchant('a'),
        merchant('b'),
        for (var i = 0; i < 10; i++) merchant('x$i'),
        merchant('far', name: 'Lointain'),
      ],
      favorites: {
        'far': ['fav/far']
      },
    );
    await pumpDirectory(tester, source, batchSize: 10, maxMerchants: 10);
    expect(source.pageCalls, 1);

    await tester.tap(find.byKey(const Key('directory-favorite-a')));
    await tester.pumpAndSettle();
    expect(source.added, ['a']);
    expect(opened, isEmpty, reason: 'le cœur n’ouvre pas la fiche');
    final heart = tester
        .widget<IconButton>(find.byKey(const Key('directory-favorite-a')));
    expect((heart.icon as Icon).icon, Icons.favorite_rounded);

    await tester.tap(find.byKey(const Key('directory-filter-favorites')));
    await tester.pumpAndSettle();
    expect(cardIds(tester), ['a', 'far']);
    expect(source.byIdCalls.last, ['far'],
        reason: 'favori non chargé : lu par identifiant');
    expect(find.byKey(const Key('directory-partial-notice')), findsNothing);

    await tester.tap(find.byKey(const Key('directory-favorite-far')));
    await tester.pumpAndSettle();
    expect(source.removed, [
      ['fav/far']
    ]);
    expect(cardIds(tester), ['a']);
  });

  testWidgets('invité : ni cœur ni filtre Favoris', (tester) async {
    final source = FakeSource(merchants: [merchant('a')], signedIn: false);
    await pumpDirectory(tester, source);
    expect(find.byKey(const Key('directory-filter-favorites')), findsNothing);
    expect(find.byKey(const Key('directory-favorite-a')), findsNothing);
    expect(source.favoritesStreams, 0);
  });

  testWidgets('toute la carte ouvre la fiche du commerçant', (tester) async {
    final source = FakeSource(merchants: [merchant('a', name: 'Alpha')]);
    await pumpDirectory(tester, source);
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tapAt(tester
        .getTopLeft(find.byKey(const Key('directory-card-a')))
        .translate(20, 20)); // the photo area
    await tester.pumpAndSettle();
    expect(opened.map((m) => m.id), ['a', 'a']);
  });

  testWidgets('états : aucun favori, aucun commerce, erreur puis Réessayer',
      (tester) async {
    var source = FakeSource(merchants: [merchant('a')]);
    await pumpDirectory(tester, source);
    await tester.tap(find.byKey(const Key('directory-filter-favorites')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('directory-no-favorites')), findsOneWidget);

    source = FakeSource(merchants: []);
    await pumpDirectory(tester, source);
    expect(find.byKey(const Key('directory-empty')), findsOneWidget);

    source = FakeSource(merchants: [merchant('a')])
      ..pageError = StateError('offline');
    await pumpDirectory(tester, source);
    expect(find.byKey(const Key('directory-error')), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    source.pageError = null;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(cardIds(tester), ['a']);
  });

  testWidgets('au-delà du plafond : suite chargée au défilement, sans doublon',
      (tester) async {
    final source = FakeSource(merchants: [
      for (var i = 0; i < 25; i++) merchant('m${i.toString().padLeft(2, '0')}')
    ]);
    await pumpDirectory(tester, source, batchSize: 10, maxMerchants: 10);
    final initialPages = source.pageCalls;
    expect(initialPages, greaterThanOrEqualTo(1));

    await tester.drag(
        find.byKey(const Key('directory-list')), const Offset(0, -4000));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const Key('directory-list')), const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(source.pageCalls, 3);
    expect(find.byKey(const Key('directory-load-more')), findsNothing);
    await tester.drag(
        find.byKey(const Key('directory-list')), const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(find.text('Commerce m24'), findsOneWidget);
    expect(source.pageCalls, 3, reason: 'aucune page de trop');
  });

  group('ordre aléatoire de session', () {
    final all = [for (var i = 0; i < 10; i++) merchant('s$i')];
    List<String> shuffled(int seed, [List<DirectoryMerchant>? items]) =>
        shuffledSessionCopy(items ?? all, Random(seed))
            .map((m) => m.id)
            .toList();
    // Tall surface: every card is built, so the full order is visible.
    const tall = Size(390, 2400);

    testWidgets(
        'mélange global en une fois, même chargé par lots (pas lot par lot)',
        (tester) async {
      final source = FakeSource(merchants: all);
      await pumpDirectory(tester, source,
          size: tall, batchSize: 4, random: Random(7));
      expect(source.pageCalls, 3, reason: '10 commerces lus par lots de 4');
      expect(cardIds(tester), shuffled(7));
      // A per-batch shuffle would keep s0..s3 in the first four places.
      expect(cardIds(tester).take(4).toSet(), isNot({'s0', 's1', 's2', 's3'}));
    });

    testWidgets('nouvel ordre à chaque ouverture de la page', (tester) async {
      final source = FakeSource(merchants: all);
      await pumpDirectory(tester, source,
          size: tall, random: Random(1), openingKey: 'ouverture-1');
      final first = cardIds(tester);
      await pumpDirectory(tester, source,
          size: tall, random: Random(2), openingKey: 'ouverture-2');
      final second = cardIds(tester);
      expect(first, shuffled(1));
      expect(second, shuffled(2));
      expect(second, isNot(first));
      expect(source.pageCalls, 2, reason: 'chaque ouverture relit la liste');
      for (final order in [first, second]) {
        expect(order.toSet(), all.map((m) => m.id).toSet());
        expect(order.length, all.length);
      }
    });

    testWidgets(
        'ordre conservé pendant la consultation : défilement, filtres, '
        'recherche et favoris', (tester) async {
      final source = FakeSource(
        merchants: [
          for (var i = 0; i < 10; i++)
            merchant('s$i',
                cats: [i.isEven ? 'Alimentation' : 'Restaurants & bars'])
        ],
        favorites: {
          for (final id in ['s1', 's4', 's8']) id: ['fav/$id']
        },
      );
      await pumpDirectory(tester, source, size: tall, random: Random(3));
      final session = cardIds(tester);
      List<String> inSession(bool Function(String id) keep) =>
          session.where(keep).toList();

      await tester.drag(
          find.byKey(const Key('directory-list')), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.drag(
          find.byKey(const Key('directory-list')), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(cardIds(tester), session);

      await tester
          .tap(find.byKey(const Key('directory-filter-category-Alimentation')));
      await tester.pumpAndSettle();
      expect(cardIds(tester),
          inSession((id) => int.parse(id.substring(1)).isEven));

      await tester.tap(find.byKey(const Key('directory-filter-favorites')));
      await tester.pumpAndSettle();
      expect(cardIds(tester), inSession({'s1', 's4', 's8'}.contains));

      await tester.tap(find.byKey(const Key('directory-filter-all')));
      await tester.pumpAndSettle();
      await search(tester, 'commerce');
      expect(cardIds(tester), session);
      await search(tester, 's');
      expect(cardIds(tester), session);
      await tester.tap(find.byKey(const Key('directory-search-clear')));
      await tester.pumpAndSettle();
      expect(cardIds(tester), session);
      expect(source.pageCalls, 1, reason: 'rien n’est relu ni remélangé');
    });

    testWidgets(
        'retour depuis une fiche et reconstruction de la page : ni relecture '
        'ni nouveau mélange', (tester) async {
      final source = FakeSource(merchants: all);
      await pumpDirectory(tester, source, size: tall, random: Random(4));
      final session = cardIds(tester);
      final photos = source.photoCalls.length;

      // A merchant page is pushed above the directory (pushNamed), then popped.
      tester.state<NavigatorState>(find.byType(Navigator)).push(
          MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('fiche'))));
      await tester.pumpAndSettle();
      expect(find.text('fiche'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      // The page rebuilds its directory (keyboard, app bar...): same state.
      await pumpDirectory(tester, source, size: tall, random: Random(99));

      expect(cardIds(tester), session);
      expect(source.pageCalls, 1);
      expect(source.activeCalls, 1);
      expect(source.favoritesStreams, 1);
      expect(source.photoCalls.length, photos, reason: 'photos en cache');
    });

    testWidgets('aucun doublon ni omission, même si les lots se chevauchent',
        (tester) async {
      final source = FakeSource(merchants: all)..overlapPages = true;
      await pumpDirectory(tester, source,
          size: tall, batchSize: 3, random: Random(11));
      final ids = cardIds(tester);
      expect(ids.length, all.length);
      expect(ids.toSet(), all.map((m) => m.id).toSet());
    });

    testWidgets('un commerce avec jeu en cours n’est pas forcé en tête',
        (tester) async {
      final order = shuffled(5);
      final source = FakeSource(merchants: all, activeIds: {order.last});
      await pumpDirectory(tester, source, size: tall, random: Random(5));
      expect(cardIds(tester), order);
      expect(
          find.descendant(
              of: find.byKey(Key('directory-card-${order.last}')),
              matching: find.text('Jeu en cours')),
          findsOneWidget);
    });

    testWidgets(
        'au-delà du plafond seulement : le reste s’ajoute après, sans '
        'modifier l’ordre déjà affiché', (tester) async {
      final source = FakeSource(merchants: all);
      await pumpDirectory(tester, source,
          size: tall, batchSize: 6, maxMerchants: 6, random: Random(9));
      // The screen is not full: the view itself loads the tail at once.
      final ids = cardIds(tester);
      expect(source.pageCalls, 2);
      expect(ids.take(6), shuffled(9, all.sublist(0, 6)),
          reason: 'l’ordre des 6 premiers n’est jamais modifié');
      expect(ids.skip(6).toSet(), {'s6', 's7', 's8', 's9'},
          reason: 'la suite est ajoutée après, sans s’intercaler');
      expect(ids.toSet(), all.map((m) => m.id).toSet());
      expect(ids.length, all.length);
    });
  });

  for (final (label, size) in [
    ('iPhone SE', const Size(320, 568)),
    ('Android compact', const Size(360, 640)),
    ('Android standard', const Size(412, 915)),
  ]) {
    testWidgets(
        'écran $label, texte normal et agrandi : badge, note et favori '
        'ensemble sans débordement', (tester) async {
      final source = FakeSource(merchants: [
        merchant('a',
            name: 'Un nom de commerce particulièrement long pour le test',
            description: 'Description longue ' * 20,
            rating: 4.9,
            reviews: 12345),
        merchant('b', cats: ['Beauté & bien-être']),
        merchant('c', name: 'Bar', rating: 3.3, reviews: 480),
      ], activeIds: {
        'a',
        'c'
      }, favorites: {
        'a': ['fav/a']
      });
      for (final scale in [1.0, 1.3]) {
        await pumpDirectory(tester, source, size: size, textScale: scale);
        expect(tester.takeException(), isNull, reason: '$label x$scale');
        final card = tester.getSize(find.byKey(const Key('directory-card-a')));
        expect(card.width, lessThanOrEqualTo(size.width - 32));
        // Test font glyphs are as wide as they are tall: real fonts are
        // narrower, so these are upper bounds. Minimum card height: 84.
        expect(card.height, lessThanOrEqualTo(scale == 1.0 ? 100 : 125),
            reason: 'plusieurs commerces visibles sans défilement');
        expect(tester.getSize(find.byKey(const Key('directory-card-b'))).height,
            84);
        for (final id in ['a', 'c']) {
          final cardFinder = find.byKey(Key('directory-card-$id'));
          expect(
              find.descendant(
                  of: cardFinder,
                  matching:
                      find.byKey(const Key('directory-active-game-badge'))),
              findsOneWidget);
          expect(
              find.descendant(
                  of: cardFinder, matching: find.byIcon(Icons.star_rounded)),
              findsOneWidget);
          expect(find.byKey(Key('directory-favorite-$id')), findsOneWidget);
          // Everything stays inside the card.
          final cardRect = tester.getRect(cardFinder);
          for (final part in [
            find.descendant(
                of: cardFinder,
                matching: find.byKey(const Key('directory-active-game-badge'))),
            find.byKey(Key('directory-favorite-$id')),
          ]) {
            final rect = tester.getRect(part);
            expect(
                cardRect.contains(rect.topLeft) &&
                    cardRect.contains(rect.bottomRight - const Offset(1, 1)),
                isTrue,
                reason: '$label x$scale $id');
          }
        }
        final heart = tester
            .widget<IconButton>(find.byKey(const Key('directory-favorite-a')));
        expect((heart.icon as Icon).icon, Icons.favorite_rounded);
      }
    });
  }
}
