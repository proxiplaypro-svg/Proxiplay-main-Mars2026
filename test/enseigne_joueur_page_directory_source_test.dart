import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The page and the Firestore source depend on Firebase, unavailable here:
/// their wiring is guarded from the source text (same convention as
/// test/favoris_joueur_guest_gate_source_test.dart). Behaviour is covered by
/// merchant_directory_view_test.dart with an in-memory source.
void main() {
  final page = File(
          'lib/pages/joueur/enseigne_joueur_page/enseigne_joueur_page_widget.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final source = File(
          'lib/pages/joueur/enseigne_joueur_page/merchant_directory_source.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final playerNavigation =
      File('lib/components/custom_nav_bar_joueur_widget.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
  final routes = File('lib/flutter_flow/nav/nav.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  test('l’onglet Commerçants ouvre uniquement le nouvel annuaire', () {
    // The tab targets the player merchant route; that route has no role or
    // parameter-dependent alternative and builds the page below.
    expect(
        playerNavigation,
        contains(
            'context.goNamed(\n                                EnseigneJoueurPageWidget.routeName'));
    expect(routes, contains('name: EnseigneJoueurPageWidget.routeName'));
    expect(
        routes,
        contains(
            'builder: (context, params) => const EnseigneJoueurPageWidget()'));

    // The route page always instantiates the compact directory implementation.
    expect(page, contains("import 'merchant_directory_view.dart';"));
    expect(page, contains('child: MerchantDirectoryView('));
    expect(page, isNot(contains('Rechercher un point de vente')));
  });

  test(
      'la page garde l’en-tête, la navigation basse et ouvre la fiche existante',
      () {
    expect(page, contains('const AppBarJoueurWidget()'));
    expect(
        page,
        contains(
            'CustomNavBarJoueurWidget(\n                        indexActive: 3'));
    expect(page, contains('EnseigneDetailJoueurPageWidget.routeName'));
    expect(page,
        contains("'enseigneDoc': serializeParam(record, ParamType.Document)"));
    expect(page, contains("extra: <String, dynamic>{'enseigneDoc': record}"));
    expect(page, contains('knownCategories: FFAppConstants.Category'));
  });

  test('plus aucune requête par catégorie ni lecture par carte dans la page',
      () {
    expect(page, isNot(contains("arrayContains")));
    expect(page, isNot(contains('queryEnseignesRecordOnce')));
    expect(page, isNot(contains('queryFavoriteEnseignesRecord')));
    expect(page, isNot(contains('queryImagesRecordOnce')));
  });

  test('source Firestore : pagination stable, une requête jeux, favoris sûrs',
      () {
    expect(source, contains('.orderBy(FieldPath.documentId)'));
    expect(source, contains('query.startAfterDocument(cursor)'));
    expect(source, contains("where(FieldPath.documentId, whereIn: chunk)"));
    expect(source, contains('start += 30'));
    // Single-field range + order on the same field: no composite index.
    expect(source, contains(".where('end_date', isGreaterThan: now)"));
    expect(source, contains(".orderBy('end_date')"));
    expect(source, contains('.limit(activeGamesLimit)'));
    expect(
        source, contains('complete: snapshot.docs.length < activeGamesLimit'));
    // A guest has no user reference: never a collection-group favorites read.
    expect(
        source,
        contains(
            'if (currentUserUid.isEmpty || currentUserReference == null) return null;'));
    expect(source,
        contains('FavoriteEnseignesRecord.createDoc(user, id: merchantId)'));
    // Only writes: create / delete a favorite inside a transaction.
    expect('.set('.allMatches(source).length, 1);
    expect(source, contains('transaction.set(favoriteRef'));
    expect(source, contains('transaction.delete(snap.reference)'));
    expect(source, isNot(contains('.update(')));
    expect(source, isNot(contains('collection.add(')));
    expect(source, isNot(contains('.batch(')));
  });
}
