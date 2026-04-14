
import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'add_game_commercant_page_widget.dart' show AddGameCommercantPageWidget;
import 'package:flutter/material.dart';

class AddGameCommercantPageModel
    extends FlutterFlowModel<AddGameCommercantPageWidget> {
  ///  State fields for stateful widgets in this page.

  final formKey = GlobalKey<FormState>();
  bool mainPrizeEnabled = true;
  // State field(s) for TextField widget.
  FocusNode? textFieldFocusNode1;
  TextEditingController? textController1;
  String? Function(BuildContext, String?)? textController1Validator;
  String? _textController1Validator(BuildContext context, String? val) {
    return null;
  }

  // State field(s) for TextField widget.
  FocusNode? textFieldFocusNode2;
  TextEditingController? textController2;
  String? Function(BuildContext, String?)? textController2Validator;
  String? _textController2Validator(BuildContext context, String? val) {
    return null;
  }

  bool isDataUploading_uploadGameData5ir = false;
  FFUploadedFile uploadedLocalFile_uploadGameData5ir =
      FFUploadedFile(bytes: Uint8List.fromList([]), originalFilename: '');

  // State field(s) for TextField widget.
  FocusNode? textFieldFocusNode3;
  TextEditingController? textController3;
  String? Function(BuildContext, String?)? textController3Validator;
  String? _textController3Validator(BuildContext context, String? val) {
    if (val == null || val.isEmpty) return null;
    final normalized = val.replaceAll(',', '.').trim();
    if (!RegExp(r'^\d+([.]\d{1,2})?$').hasMatch(normalized)) {
      return 'Il faut un nombre';
    }
    return null;
  }

  // State field(s) for game title TextField widget.
  FocusNode? textFieldFocusNode4;
  TextEditingController? textController4;
  String? Function(BuildContext, String?)? textController4Validator;
  String? _textController4Validator(BuildContext context, String? val) {
    return null;
  }

  // Secondary prizes (optional, repeatable)
  final List<SecondaryPrizeEntry> secondaryPrizes = [];

  DateTime? startDatePicked;
  DateTime? datePicked;
  // State field(s) for Switch widget.
  bool? switchValue;
  // Stores action output result for [Backend Call - Create Document] action in Button widget.
  GamesRecord? gameResult;
  // Stores action output result for [Custom Action - setEndOfDay] action in Button widget.
  DateTime? endDateTransformCopy;
  bool isDataUploading_uploadDataNyu = false;
  FFUploadedFile uploadedLocalFile_uploadDataNyu =
      FFUploadedFile(bytes: Uint8List.fromList([]), originalFilename: '');
  String uploadedFileUrl_uploadDataNyu = '';

  @override
  void initState(BuildContext context) {
    textController1Validator = _textController1Validator;
    textController2Validator = _textController2Validator;
    textController3Validator = _textController3Validator;
    textController4Validator = _textController4Validator;
    // Start with one empty secondary prize row for convenience.
    secondaryPrizes.add(SecondaryPrizeEntry());
    startDatePicked = getCurrentTimestamp;
  }

  @override
  void dispose() {
    textFieldFocusNode1?.dispose();
    textController1?.dispose();

    textFieldFocusNode2?.dispose();
    textController2?.dispose();

    textFieldFocusNode3?.dispose();
    textController3?.dispose();
    textFieldFocusNode4?.dispose();
    textController4?.dispose();
    for (final entry in secondaryPrizes) {
      entry.dispose();
    }
  }
}

class SecondaryPrizeEntry {
  static int _nextStableId = 0;

  final int stableId = _nextStableId++;
  final FocusNode nameFocusNode = FocusNode();
  final TextEditingController nameController = TextEditingController();
  final FocusNode presentationFocusNode = FocusNode();
  final TextEditingController presentationController = TextEditingController();
  final FocusNode countFocusNode = FocusNode();
  final TextEditingController countController = TextEditingController();

  void dispose() {
    nameFocusNode.dispose();
    nameController.dispose();
    presentationFocusNode.dispose();
    presentationController.dispose();
    countFocusNode.dispose();
    countController.dispose();
  }
}
