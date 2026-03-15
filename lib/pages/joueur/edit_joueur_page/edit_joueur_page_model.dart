import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'edit_joueur_page_widget.dart' show EditJoueurPageWidget;
import 'package:flutter/material.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

class EditJoueurPageModel extends FlutterFlowModel<EditJoueurPageWidget> {
  ///  State fields for stateful widgets in this page.

  final formKey = GlobalKey<FormState>();
  // State field(s) for TextField widget.
  FocusNode? textFieldFocusNode1;
  TextEditingController? textController1;
  String? Function(BuildContext, String?)? textController1Validator;
  // State field(s) for TextField widget.
  FocusNode? textFieldFocusNode2;
  TextEditingController? textController2;
  String? Function(BuildContext, String?)? textController2Validator;
  // State field(s) for TextFieldMail widget.
  FocusNode? textFieldMailFocusNode;
  TextEditingController? textFieldMailTextController;
  String? Function(BuildContext, String?)? textFieldMailTextControllerValidator;
  // State field(s) for TextFieldPhone widget.
  FocusNode? textFieldPhoneFocusNode;
  TextEditingController? textFieldPhoneTextController;
  late MaskTextInputFormatter textFieldPhoneMask;
  String? Function(BuildContext, String?)?
      textFieldPhoneTextControllerValidator;
  // State field(s) for TextFieldCity widget.
  FocusNode? textFieldCityFocusNode;
  TextEditingController? textFieldCityTextController;
  String? Function(BuildContext, String?)? textFieldCityTextControllerValidator;
  // State field(s) for TextField widget.
  FocusNode? textFieldFocusNode4;
  TextEditingController? passwordTextController;
  late bool passwordVisibility1;
  String? Function(BuildContext, String?)? passwordTextControllerValidator;
  String? _passwordTextControllerValidator(BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Nouveau mot de passe est nécessaire';
    }

    return null;
  }

  // State field(s) for TextField widget.
  FocusNode? textFieldFocusNode5;
  TextEditingController? confirmPasswordTextController;
  late bool passwordVisibility2;
  String? Function(BuildContext, String?)?
      confirmPasswordTextControllerValidator;
  String? _confirmPasswordTextControllerValidator(
      BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Confirmer le nouveau mot de passe est nécessaire';
    }

    return null;
  }

  // Model for CustomNavBarJoueur component.
  late CustomNavBarJoueurModel customNavBarJoueurModel;

  @override
  void initState(BuildContext context) {
    passwordVisibility1 = false;
    passwordTextControllerValidator = _passwordTextControllerValidator;
    passwordVisibility2 = false;
    confirmPasswordTextControllerValidator =
        _confirmPasswordTextControllerValidator;
    customNavBarJoueurModel =
        createModel(context, () => CustomNavBarJoueurModel());
  }

  @override
  void dispose() {
    textFieldFocusNode1?.dispose();
    textController1?.dispose();

    textFieldFocusNode2?.dispose();
    textController2?.dispose();

    textFieldMailFocusNode?.dispose();
    textFieldMailTextController?.dispose();

    textFieldPhoneFocusNode?.dispose();
    textFieldPhoneTextController?.dispose();

    textFieldCityFocusNode?.dispose();
    textFieldCityTextController?.dispose();

    textFieldFocusNode4?.dispose();
    passwordTextController?.dispose();

    textFieldFocusNode5?.dispose();
    confirmPasswordTextController?.dispose();

    customNavBarJoueurModel.dispose();
  }
}
