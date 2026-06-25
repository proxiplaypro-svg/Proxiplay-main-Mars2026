import '/backend/backend.dart';
import '/components/app_bar_joueur_widget.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'home_joueur_page_widget.dart' show HomeJoueurPageWidget;
import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

class HomeJoueurPageModel extends FlutterFlowModel<HomeJoueurPageWidget> {
  ///  Local state fields for this page.

  bool searchActive = false;

  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Custom Action - setEndOfDay] action in HomeJoueurPage widget.
  DateTime? refreshDate;
  // State field(s) for TextField widget.
  FocusNode? textFieldFocusNode;
  TextEditingController? textController;
  String? Function(BuildContext, String?)? textControllerValidator;
  List<GamesRecord> simpleSearchResults = [];
  // State field(s) for ListView widget.

  PagingController<DocumentSnapshot?, GamesRecord>? listViewPagingController2;
  Query? listViewPagingQuery2;
  List<StreamSubscription?> listViewStreamSubscriptions2 = [];

  // Stores action output result for [Backend Call - Read Document] action in Container widget.
  EnseignesRecord? enseigneRef;
  // State field(s) for ListView widget.

  PagingController<DocumentSnapshot?, GamesRecord>? listViewPagingController3;
  Query? listViewPagingQuery3;
  List<StreamSubscription?> listViewStreamSubscriptions3 = [];

  // Stores action output result for [Backend Call - Read Document] action in Container widget.
  EnseignesRecord? enseigneRefN;
  // State field(s) for ListView widget.

  PagingController<DocumentSnapshot?, GamesRecord>? listViewPagingController4;
  Query? listViewPagingQuery4;
  List<StreamSubscription?> listViewStreamSubscriptions4 = [];

  // Stores action output result for [Backend Call - Read Document] action in Container widget.
  EnseignesRecord? enseigneRefBF;
  // State field(s) for ListView widget.

  PagingController<DocumentSnapshot?, GamesRecord>? listViewPagingController5;
  Query? listViewPagingQuery5;
  List<StreamSubscription?> listViewStreamSubscriptions5 = [];

  // Stores action output result for [Backend Call - Read Document] action in Container widget.
  EnseignesRecord? enseigne2Ref;
  // State field(s) for ListView widget.

  PagingController<DocumentSnapshot?, GamesRecord>? listViewPagingController6;
  Query? listViewPagingQuery6;
  List<StreamSubscription?> listViewStreamSubscriptions6 = [];

  // Stores action output result for [Backend Call - Read Document] action in Container widget.
  EnseignesRecord? enseigne2RefN;
  // State field(s) for ListView widget.

  PagingController<DocumentSnapshot?, GamesRecord>? listViewPagingController7;
  Query? listViewPagingQuery7;
  List<StreamSubscription?> listViewStreamSubscriptions7 = [];

  // Stores action output result for [Backend Call - Read Document] action in Container widget.
  EnseignesRecord? enseigne2RefBF;
  // State field(s) for ListView widget.

  PagingController<DocumentSnapshot?, GamesRecord>? listViewPagingController8;
  Query? listViewPagingQuery8;
  List<StreamSubscription?> listViewStreamSubscriptions8 = [];

  // Stores action output result for [Backend Call - Read Document] action in Container widget.
  EnseignesRecord? enseigneRefNoUser;
  // State field(s) for ListView widget.

  PagingController<DocumentSnapshot?, GamesRecord>? listViewPagingController9;
  Query? listViewPagingQuery9;
  List<StreamSubscription?> listViewStreamSubscriptions9 = [];

  // Stores action output result for [Backend Call - Read Document] action in Container widget.
  EnseignesRecord? enseigneRefNoUser2;
  // State field(s) for ListView widget.

  PagingController<DocumentSnapshot?, GamesRecord>? listViewPagingController10;
  Query? listViewPagingQuery10;
  List<StreamSubscription?> listViewStreamSubscriptions10 = [];

  // Stores action output result for [Backend Call - Read Document] action in Container widget.
  EnseignesRecord? enseigneRefNoUser3;
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
    textFieldFocusNode?.dispose();
    textController?.dispose();

    for (var s in listViewStreamSubscriptions2) {
      s?.cancel();
    }
    listViewPagingController2?.dispose();

    for (var s in listViewStreamSubscriptions3) {
      s?.cancel();
    }
    listViewPagingController3?.dispose();

    for (var s in listViewStreamSubscriptions4) {
      s?.cancel();
    }
    listViewPagingController4?.dispose();

    for (var s in listViewStreamSubscriptions5) {
      s?.cancel();
    }
    listViewPagingController5?.dispose();

    for (var s in listViewStreamSubscriptions6) {
      s?.cancel();
    }
    listViewPagingController6?.dispose();

    for (var s in listViewStreamSubscriptions7) {
      s?.cancel();
    }
    listViewPagingController7?.dispose();

    for (var s in listViewStreamSubscriptions8) {
      s?.cancel();
    }
    listViewPagingController8?.dispose();

    for (var s in listViewStreamSubscriptions9) {
      s?.cancel();
    }
    listViewPagingController9?.dispose();

    for (var s in listViewStreamSubscriptions10) {
      s?.cancel();
    }
    listViewPagingController10?.dispose();

    customNavBarJoueurModel.dispose();
    appBarJoueurModel.dispose();
  }

  /// Additional helper methods.
  PagingController<DocumentSnapshot?, GamesRecord> setListViewController2(
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

  PagingController<DocumentSnapshot?, GamesRecord> _createListViewController2(
    Query query,
    DocumentReference<Object?>? parent,
  ) {
    final controller =
        PagingController<DocumentSnapshot?, GamesRecord>(firstPageKey: null);
    return controller
      ..addPageRequestListener(
        (nextPageMarker) => queryGamesRecordPage(
          queryBuilder: (_) => listViewPagingQuery2 ??= query,
          nextPageMarker: nextPageMarker,
          streamSubscriptions: listViewStreamSubscriptions2,
          controller: controller,
          pageSize: 100,
          isStream: true,
        ),
      );
  }

  PagingController<DocumentSnapshot?, GamesRecord> setListViewController3(
    Query query, {
    DocumentReference<Object?>? parent,
  }) {
    listViewPagingController3 ??= _createListViewController3(query, parent);
    if (listViewPagingQuery3 != query) {
      listViewPagingQuery3 = query;
      listViewPagingController3?.refresh();
    }
    return listViewPagingController3!;
  }

  PagingController<DocumentSnapshot?, GamesRecord> _createListViewController3(
    Query query,
    DocumentReference<Object?>? parent,
  ) {
    final controller =
        PagingController<DocumentSnapshot?, GamesRecord>(firstPageKey: null);
    return controller
      ..addPageRequestListener(
        (nextPageMarker) => queryGamesRecordPage(
          queryBuilder: (_) => listViewPagingQuery3 ??= query,
          nextPageMarker: nextPageMarker,
          streamSubscriptions: listViewStreamSubscriptions3,
          controller: controller,
          pageSize: 100,
          isStream: true,
        ),
      );
  }

  PagingController<DocumentSnapshot?, GamesRecord> setListViewController4(
    Query query, {
    DocumentReference<Object?>? parent,
  }) {
    listViewPagingController4 ??= _createListViewController4(query, parent);
    if (listViewPagingQuery4 != query) {
      listViewPagingQuery4 = query;
      listViewPagingController4?.refresh();
    }
    return listViewPagingController4!;
  }

  PagingController<DocumentSnapshot?, GamesRecord> _createListViewController4(
    Query query,
    DocumentReference<Object?>? parent,
  ) {
    final controller =
        PagingController<DocumentSnapshot?, GamesRecord>(firstPageKey: null);
    return controller
      ..addPageRequestListener(
        (nextPageMarker) => queryGamesRecordPage(
          queryBuilder: (_) => listViewPagingQuery4 ??= query,
          nextPageMarker: nextPageMarker,
          streamSubscriptions: listViewStreamSubscriptions4,
          controller: controller,
          pageSize: 100,
          isStream: true,
        ),
      );
  }

  PagingController<DocumentSnapshot?, GamesRecord> setListViewController5(
    Query query, {
    DocumentReference<Object?>? parent,
  }) {
    listViewPagingController5 ??= _createListViewController5(query, parent);
    if (listViewPagingQuery5 != query) {
      listViewPagingQuery5 = query;
      listViewPagingController5?.refresh();
    }
    return listViewPagingController5!;
  }

  PagingController<DocumentSnapshot?, GamesRecord> _createListViewController5(
    Query query,
    DocumentReference<Object?>? parent,
  ) {
    final controller =
        PagingController<DocumentSnapshot?, GamesRecord>(firstPageKey: null);
    return controller
      ..addPageRequestListener(
        (nextPageMarker) => queryGamesRecordPage(
          queryBuilder: (_) => listViewPagingQuery5 ??= query,
          nextPageMarker: nextPageMarker,
          streamSubscriptions: listViewStreamSubscriptions5,
          controller: controller,
          pageSize: 100,
          isStream: true,
        ),
      );
  }

  PagingController<DocumentSnapshot?, GamesRecord> setListViewController6(
    Query query, {
    DocumentReference<Object?>? parent,
  }) {
    listViewPagingController6 ??= _createListViewController6(query, parent);
    if (listViewPagingQuery6 != query) {
      listViewPagingQuery6 = query;
      listViewPagingController6?.refresh();
    }
    return listViewPagingController6!;
  }

  PagingController<DocumentSnapshot?, GamesRecord> _createListViewController6(
    Query query,
    DocumentReference<Object?>? parent,
  ) {
    final controller =
        PagingController<DocumentSnapshot?, GamesRecord>(firstPageKey: null);
    return controller
      ..addPageRequestListener(
        (nextPageMarker) => queryGamesRecordPage(
          queryBuilder: (_) => listViewPagingQuery6 ??= query,
          nextPageMarker: nextPageMarker,
          streamSubscriptions: listViewStreamSubscriptions6,
          controller: controller,
          pageSize: 100,
          isStream: true,
        ),
      );
  }

  PagingController<DocumentSnapshot?, GamesRecord> setListViewController7(
    Query query, {
    DocumentReference<Object?>? parent,
  }) {
    listViewPagingController7 ??= _createListViewController7(query, parent);
    if (listViewPagingQuery7 != query) {
      listViewPagingQuery7 = query;
      listViewPagingController7?.refresh();
    }
    return listViewPagingController7!;
  }

  PagingController<DocumentSnapshot?, GamesRecord> _createListViewController7(
    Query query,
    DocumentReference<Object?>? parent,
  ) {
    final controller =
        PagingController<DocumentSnapshot?, GamesRecord>(firstPageKey: null);
    return controller
      ..addPageRequestListener(
        (nextPageMarker) => queryGamesRecordPage(
          queryBuilder: (_) => listViewPagingQuery7 ??= query,
          nextPageMarker: nextPageMarker,
          streamSubscriptions: listViewStreamSubscriptions7,
          controller: controller,
          pageSize: 100,
          isStream: true,
        ),
      );
  }

  PagingController<DocumentSnapshot?, GamesRecord> setListViewController8(
    Query query, {
    DocumentReference<Object?>? parent,
  }) {
    listViewPagingController8 ??= _createListViewController8(query, parent);
    if (listViewPagingQuery8 != query) {
      listViewPagingQuery8 = query;
      listViewPagingController8?.refresh();
    }
    return listViewPagingController8!;
  }

  PagingController<DocumentSnapshot?, GamesRecord> _createListViewController8(
    Query query,
    DocumentReference<Object?>? parent,
  ) {
    final controller =
        PagingController<DocumentSnapshot?, GamesRecord>(firstPageKey: null);
    return controller
      ..addPageRequestListener(
        (nextPageMarker) => queryGamesRecordPage(
          queryBuilder: (_) => listViewPagingQuery8 ??= query,
          nextPageMarker: nextPageMarker,
          streamSubscriptions: listViewStreamSubscriptions8,
          controller: controller,
          pageSize: 100,
          isStream: true,
        ),
      );
  }

  PagingController<DocumentSnapshot?, GamesRecord> setListViewController9(
    Query query, {
    DocumentReference<Object?>? parent,
  }) {
    listViewPagingController9 ??= _createListViewController9(query, parent);
    if (listViewPagingQuery9 != query) {
      listViewPagingQuery9 = query;
      listViewPagingController9?.refresh();
    }
    return listViewPagingController9!;
  }

  PagingController<DocumentSnapshot?, GamesRecord> _createListViewController9(
    Query query,
    DocumentReference<Object?>? parent,
  ) {
    final controller =
        PagingController<DocumentSnapshot?, GamesRecord>(firstPageKey: null);
    return controller
      ..addPageRequestListener(
        (nextPageMarker) => queryGamesRecordPage(
          queryBuilder: (_) => listViewPagingQuery9 ??= query,
          nextPageMarker: nextPageMarker,
          streamSubscriptions: listViewStreamSubscriptions9,
          controller: controller,
          pageSize: 100,
          isStream: true,
        ),
      );
  }

  PagingController<DocumentSnapshot?, GamesRecord> setListViewController10(
    Query query, {
    DocumentReference<Object?>? parent,
  }) {
    listViewPagingController10 ??= _createListViewController10(query, parent);
    if (listViewPagingQuery10 != query) {
      listViewPagingQuery10 = query;
      listViewPagingController10?.refresh();
    }
    return listViewPagingController10!;
  }

  PagingController<DocumentSnapshot?, GamesRecord> _createListViewController10(
    Query query,
    DocumentReference<Object?>? parent,
  ) {
    final controller =
        PagingController<DocumentSnapshot?, GamesRecord>(firstPageKey: null);
    return controller
      ..addPageRequestListener(
        (nextPageMarker) => queryGamesRecordPage(
          queryBuilder: (_) => listViewPagingQuery10 ??= query,
          nextPageMarker: nextPageMarker,
          streamSubscriptions: listViewStreamSubscriptions10,
          controller: controller,
          pageSize: 100,
          isStream: true,
        ),
      );
  }
}
