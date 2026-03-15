import '/backend/backend.dart';
import '/components/app_bar_joueur_widget.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'favoris_joueur_page_widget.dart' show FavorisJoueurPageWidget;
import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

class FavorisJoueurPageModel extends FlutterFlowModel<FavorisJoueurPageWidget> {
  ///  State fields for stateful widgets in this page.

  // State field(s) for TabBar widget.
  TabController? tabBarController;
  int get tabBarCurrentIndex =>
      tabBarController != null ? tabBarController!.index : 0;
  int get tabBarPreviousIndex =>
      tabBarController != null ? tabBarController!.previousIndex : 0;

  // State field(s) for ListView widget.

  PagingController<DocumentSnapshot?, FavoriteEnseignesRecord>?
      listViewPagingController1;
  Query? listViewPagingQuery1;
  List<StreamSubscription?> listViewStreamSubscriptions1 = [];

  // State field(s) for ListView widget.

  PagingController<DocumentSnapshot?, FavoriteGamesRecord>?
      listViewPagingController2;
  Query? listViewPagingQuery2;

  // Model for CustomNavBarJoueur component.
  late CustomNavBarJoueurModel customNavBarJoueurModel;
  // Model for appBarJoueur component.
  late AppBarJoueurModel appBarJoueurModel;

  @override
  void initState(BuildContext context) {
    customNavBarJoueurModel =
        createModel(context, () => CustomNavBarJoueurModel());
    appBarJoueurModel = createModel(context, () => AppBarJoueurModel());
  }

  @override
  void dispose() {
    tabBarController?.dispose();
    for (var s in listViewStreamSubscriptions1) {
      s?.cancel();
    }
    listViewPagingController1?.dispose();

    listViewPagingController2?.dispose();

    customNavBarJoueurModel.dispose();
    appBarJoueurModel.dispose();
  }

  /// Additional helper methods.
  PagingController<DocumentSnapshot?, FavoriteEnseignesRecord>
      setListViewController1(
    Query query, {
    DocumentReference<Object?>? parent,
  }) {
    listViewPagingController1 ??= _createListViewController1(query, parent);
    if (listViewPagingQuery1 != query) {
      listViewPagingQuery1 = query;
      listViewPagingController1?.refresh();
    }
    return listViewPagingController1!;
  }

  PagingController<DocumentSnapshot?, FavoriteEnseignesRecord>
      _createListViewController1(
    Query query,
    DocumentReference<Object?>? parent,
  ) {
    final controller =
        PagingController<DocumentSnapshot?, FavoriteEnseignesRecord>(
            firstPageKey: null);
    return controller
      ..addPageRequestListener(
        (nextPageMarker) => queryFavoriteEnseignesRecordPage(
          parent: parent,
          nextPageMarker: nextPageMarker,
          streamSubscriptions: listViewStreamSubscriptions1,
          controller: controller,
          pageSize: 20,
          isStream: true,
        ),
      );
  }

  PagingController<DocumentSnapshot?, FavoriteGamesRecord>
      setListViewController2(
    Query query, {
    DocumentReference<Object?>? parent,
  }) {
    listViewPagingController2 ??= _createListViewController2(query, parent);
    if (listViewPagingQuery2 != query) {
      listViewPagingQuery2 = query;
      listViewPagingController2?.refresh();
    }
    return listViewPagingController2!;
  }

  PagingController<DocumentSnapshot?, FavoriteGamesRecord>
      _createListViewController2(
    Query query,
    DocumentReference<Object?>? parent,
  ) {
    final controller = PagingController<DocumentSnapshot?, FavoriteGamesRecord>(
        firstPageKey: null);
    return controller
      ..addPageRequestListener(
        (nextPageMarker) => queryFavoriteGamesRecordPage(
          parent: parent,
          nextPageMarker: nextPageMarker,
          controller: controller,
          pageSize: 25,
          isStream: false,
        ),
      );
  }
}
