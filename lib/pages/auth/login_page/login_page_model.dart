import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'login_page_widget.dart' show LoginPageWidget;
import 'package:flutter/material.dart';

class LoginPageModel extends FlutterFlowModel<LoginPageWidget> {
  ///  State fields for stateful widgets in this page.

  final formKey = GlobalKey<FormState>();
  // Stores action output result for [Custom Action - setEndOfDay] action in LoginPage widget.
  DateTime? refreshDate;
  // Stores action output result for [Custom Action - isMineur] action in LoginPage widget.
  bool? isMineur;
  // State field(s) for emailAddress widget.
  FocusNode? emailAddressFocusNode;
  TextEditingController? emailAddressTextController;
  String? Function(BuildContext, String?)? emailAddressTextControllerValidator;
  String? _emailAddressTextControllerValidator(
      BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Veuillez saisir une adresse mail valide';
    }

    if (!RegExp(kTextValidatorEmailRegex).hasMatch(val)) {
      return 'Veuillez saisir une adresse mail valide';
    }
    return null;
  }

  // State field(s) for password widget.
  FocusNode? passwordFocusNode;
  TextEditingController? passwordTextController;
  late bool passwordVisibility;
  String? Function(BuildContext, String?)? passwordTextControllerValidator;
  String? _passwordTextControllerValidator(BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Un mot de passe est obligatoire';
    }

    if (val.length < 5) {
      return 'Un mot de passe à minimum 5 caractères est nécessaire';
    }

    return null;
  }

  // Stores action output result for [Custom Action - setEndOfDay] action in Button widget.
  DateTime? refreshDate2;
  // Stores action output result for [Custom Action - isMineur] action in Button widget.
  bool? isMineur2;

  @override
  void initState(BuildContext context) {
    emailAddressTextControllerValidator = _emailAddressTextControllerValidator;
    passwordVisibility = false;
    passwordTextControllerValidator = _passwordTextControllerValidator;
  }

  @override
  void dispose() {
    emailAddressFocusNode?.dispose();
    emailAddressTextController?.dispose();

    passwordFocusNode?.dispose();
    passwordTextController?.dispose();
  }
}
