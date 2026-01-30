import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/custom_cloud_functions/custom_cloud_function_response_manager.dart';
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_choice_chips.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/form_field_controller.dart';
import 'dart:ui';
import '/custom_code/actions/index.dart' as actions;
import '/index.dart';
import 'update_enseigne_commercant_page_widget.dart'
    show UpdateEnseigneCommercantPageWidget;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:provider/provider.dart';
import 'package:webviewx_plus/webviewx_plus.dart';

class UpdateEnseigneCommercantPageModel
    extends FlutterFlowModel<UpdateEnseigneCommercantPageWidget> {
  ///  State fields for stateful widgets in this page.

  final formKey = GlobalKey<FormState>();
  // State field(s) for TextFieldName widget.
  FocusNode? textFieldNameFocusNode;
  TextEditingController? textFieldNameTextController;
  String? Function(BuildContext, String?)? textFieldNameTextControllerValidator;
  String? _textFieldNameTextControllerValidator(
      BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'name is required';
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
      return 'description is required';
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
      return 'phone_number is required';
    }

    if (!RegExp('^(?:\\+33|0)[1-9](?:\\d{2}){4}\$').hasMatch(val)) {
      return 'Invalid text';
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
      return 'address is required';
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
      return 'area_code is required';
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
      return 'city is required';
    }

    if (val.length < 1) {
      return 'Requires at least 1 characters.';
    }

    return null;
  }

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
  // Stores action output result for [Cloud Function - deleteEnseigneAndGames] action in Button widget.
  DeleteEnseigneAndGamesCloudFunctionCallResponse? resultCloudFunction;

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
