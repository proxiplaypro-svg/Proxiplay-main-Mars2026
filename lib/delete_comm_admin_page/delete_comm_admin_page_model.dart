import '/backend/backend.dart';
import '/backend/custom_cloud_functions/custom_cloud_function_response_manager.dart';
import '/components/custom_nav_bar_admin_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'delete_comm_admin_page_widget.dart' show DeleteCommAdminPageWidget;
import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

class DeleteCommAdminPageModel
    extends FlutterFlowModel<DeleteCommAdminPageWidget> {
  ///  State fields for stateful widgets in this page.

  // State field(s) for ListView widget.

  PagingController<DocumentSnapshot?, AccountDeletionRequestsRecord>?
      listViewPagingController;
  Query? listViewPagingQuery;
  List<StreamSubscription?> listViewStreamSubscriptions = [];

  // Stores action output result for [Cloud Function - deleteCommercantAccount] action in Button widget.
  DeleteCommercantAccountCloudFunctionCallResponse? cloudFunction1qh;
  // Model for CustomNavBarAdmin component.
  late CustomNavBarAdminModel customNavBarAdminModel;

  @override
  void initState(BuildContext context) {
    customNavBarAdminModel =
        createModel(context, () => CustomNavBarAdminModel());
  }

  @override
  void dispose() {
    for (var s in listViewStreamSubscriptions) {
      s?.cancel();
    }
    listViewPagingController?.dispose();

    customNavBarAdminModel.dispose();
  }

  /// Additional helper methods.
  PagingController<DocumentSnapshot?, AccountDeletionRequestsRecord>
      setListViewController(
    Query query, {
    DocumentReference<Object?>? parent,
  }) {
    listViewPagingController ??= _createListViewController(query, parent);
    if (listViewPagingQuery != query) {
      listViewPagingQuery = query;
      listViewPagingController?.refresh();
    }
    return listViewPagingController!;
  }

  PagingController<DocumentSnapshot?, AccountDeletionRequestsRecord>
      _createListViewController(
    Query query,
    DocumentReference<Object?>? parent,
  ) {
    final controller =
        PagingController<DocumentSnapshot?, AccountDeletionRequestsRecord>(
            firstPageKey: null);
    return controller
      ..addPageRequestListener(
        (nextPageMarker) => queryAccountDeletionRequestsRecordPage(
          queryBuilder: (_) => listViewPagingQuery ??= query,
          nextPageMarker: nextPageMarker,
          streamSubscriptions: listViewStreamSubscriptions,
          controller: controller,
          pageSize: 20,
          isStream: true,
        ),
      );
  }
}
