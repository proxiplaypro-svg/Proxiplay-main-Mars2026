import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/firebase_storage/storage.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_choice_chips.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/form_field_controller.dart';
import '/flutter_flow/upload_data.dart';
import 'dart:ui';
import '/custom_code/actions/index.dart' as actions;
import '/flutter_flow/custom_functions.dart' as functions;
import '/index.dart';
import 'add_enseigne_commercant_page_widget.dart'
    show AddEnseigneCommercantPageWidget;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:provider/provider.dart';

class AddEnseigneCommercantPageModel
    extends FlutterFlowModel<AddEnseigneCommercantPageWidget> {
  ///  Local state fields for this page.

  List<FFUploadedFile> uploadedImagesList = [];
  void addToUploadedImagesList(FFUploadedFile item) =>
      uploadedImagesList.add(item);
  void removeFromUploadedImagesList(FFUploadedFile item) =>
      uploadedImagesList.remove(item);
  void removeAtIndexFromUploadedImagesList(int index) =>
      uploadedImagesList.removeAt(index);
  void insertAtIndexInUploadedImagesList(int index, FFUploadedFile item) =>
      uploadedImagesList.insert(index, item);
  void updateUploadedImagesListAtIndex(
          int index, Function(FFUploadedFile) updateFn) =>
      uploadedImagesList[index] = updateFn(uploadedImagesList[index]);

  ///  State fields for stateful widgets in this page.

  final formKey = GlobalKey<FormState>();
  // State field(s) for TextFieldName widget.
  FocusNode? textFieldNameFocusNode;
  TextEditingController? textFieldNameTextController;
  String? Function(BuildContext, String?)? textFieldNameTextControllerValidator;
  String? _textFieldNameTextControllerValidator(
      BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Nom de l\'enseigne  requis';
    }

    if (val.length < 1) {
      return 'Requires at least 1 characters.';
    }

    return null;
  }

  // State field(s) for TextFieldDescription widget.
  FocusNode? textFieldDescriptionFocusNode;
  TextEditingController? textFieldDescriptionTextController;
  String? Function(BuildContext, String?)?
      textFieldDescriptionTextControllerValidator;
  String? _textFieldDescriptionTextControllerValidator(
      BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Description requis';
    }

    if (val.length < 1) {
      return 'Requires at least 1 characters.';
    }

    return null;
  }

  // State field(s) for TextFieldPhone widget.
  FocusNode? textFieldPhoneFocusNode;
  TextEditingController? textFieldPhoneTextController;
  late MaskTextInputFormatter textFieldPhoneMask;
  String? Function(BuildContext, String?)?
      textFieldPhoneTextControllerValidator;
  String? _textFieldPhoneTextControllerValidator(
      BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Numéro de téléphone requis';
    }

    if (val.length < 14) {
      return 'Requires at least 14 characters.';
    }

    return null;
  }

  // State field(s) for TextFieldAdresse widget.
  FocusNode? textFieldAdresseFocusNode;
  TextEditingController? textFieldAdresseTextController;
  String? Function(BuildContext, String?)?
      textFieldAdresseTextControllerValidator;
  String? _textFieldAdresseTextControllerValidator(
      BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Rue requis';
    }

    if (val.length < 1) {
      return 'Requires at least 1 characters.';
    }

    return null;
  }

  // State field(s) for TextFieldCode widget.
  FocusNode? textFieldCodeFocusNode;
  TextEditingController? textFieldCodeTextController;
  String? Function(BuildContext, String?)? textFieldCodeTextControllerValidator;
  String? _textFieldCodeTextControllerValidator(
      BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Code Postal requis';
    }

    if (val.length < 5) {
      return 'Requires at least 5 characters.';
    }

    return null;
  }

  // State field(s) for TextFieldCity widget.
  FocusNode? textFieldCityFocusNode;
  TextEditingController? textFieldCityTextController;
  String? Function(BuildContext, String?)? textFieldCityTextControllerValidator;
  String? _textFieldCityTextControllerValidator(
      BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Ville requis';
    }

    if (val.length < 1) {
      return 'Requires at least 1 characters.';
    }

    return null;
  }

  bool isDataUploading_uploadDataPhoto5lq = false;
  FFUploadedFile uploadedLocalFile_uploadDataPhoto5lq =
      FFUploadedFile(bytes: Uint8List.fromList([]), originalFilename: '');

  // State field(s) for ChoiceChips widget.
  FormFieldController<List<String>>? choiceChipsValueController;
  List<String>? get choiceChipsValues => choiceChipsValueController?.value;
  set choiceChipsValues(List<String>? val) =>
      choiceChipsValueController?.value = val;
  // State field(s) for TextFieldSiteWeb widget.
  FocusNode? textFieldSiteWebFocusNode;
  TextEditingController? textFieldSiteWebTextController;
  String? Function(BuildContext, String?)?
      textFieldSiteWebTextControllerValidator;
  // State field(s) for TextFieldInst widget.
  FocusNode? textFieldInstFocusNode;
  TextEditingController? textFieldInstTextController;
  String? Function(BuildContext, String?)? textFieldInstTextControllerValidator;
  // State field(s) for TextFieldFacebook widget.
  FocusNode? textFieldFacebookFocusNode;
  TextEditingController? textFieldFacebookTextController;
  String? Function(BuildContext, String?)?
      textFieldFacebookTextControllerValidator;
  // State field(s) for TextFieldTwitter widget.
  FocusNode? textFieldTwitterFocusNode;
  TextEditingController? textFieldTwitterTextController;
  String? Function(BuildContext, String?)?
      textFieldTwitterTextControllerValidator;
  // Stores action output result for [Backend Call - Create Document] action in Button widget.
  EnseignesRecord? enseigneResult;
  bool isDataUploading_uploadDataUnf = false;
  List<FFUploadedFile> uploadedLocalFiles_uploadDataUnf = [];
  List<String> uploadedFileUrls_uploadDataUnf = [];

  @override
  void initState(BuildContext context) {
    textFieldNameTextControllerValidator =
        _textFieldNameTextControllerValidator;
    textFieldDescriptionTextControllerValidator =
        _textFieldDescriptionTextControllerValidator;
    textFieldPhoneTextControllerValidator =
        _textFieldPhoneTextControllerValidator;
    textFieldAdresseTextControllerValidator =
        _textFieldAdresseTextControllerValidator;
    textFieldCodeTextControllerValidator =
        _textFieldCodeTextControllerValidator;
    textFieldCityTextControllerValidator =
        _textFieldCityTextControllerValidator;
  }

  @override
  void dispose() {
    textFieldNameFocusNode?.dispose();
    textFieldNameTextController?.dispose();

    textFieldDescriptionFocusNode?.dispose();
    textFieldDescriptionTextController?.dispose();

    textFieldPhoneFocusNode?.dispose();
    textFieldPhoneTextController?.dispose();

    textFieldAdresseFocusNode?.dispose();
    textFieldAdresseTextController?.dispose();

    textFieldCodeFocusNode?.dispose();
    textFieldCodeTextController?.dispose();

    textFieldCityFocusNode?.dispose();
    textFieldCityTextController?.dispose();

    textFieldSiteWebFocusNode?.dispose();
    textFieldSiteWebTextController?.dispose();

    textFieldInstFocusNode?.dispose();
    textFieldInstTextController?.dispose();

    textFieldFacebookFocusNode?.dispose();
    textFieldFacebookTextController?.dispose();

    textFieldTwitterFocusNode?.dispose();
    textFieldTwitterTextController?.dispose();
  }
}
