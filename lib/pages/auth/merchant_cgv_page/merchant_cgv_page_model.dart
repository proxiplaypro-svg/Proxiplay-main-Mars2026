import '/flutter_flow/flutter_flow_util.dart';
import 'merchant_cgv_page_widget.dart' show MerchantCgvPageWidget;
import 'package:flutter/material.dart';

class MerchantCgvPageModel extends FlutterFlowModel<MerchantCgvPageWidget> {
  /// Case CGV : jamais précochée.
  bool cgvAccepted = false;
  bool isSubmitting = false;
  String? errorMessage;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
