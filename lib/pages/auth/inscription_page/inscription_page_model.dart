import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'inscription_page_widget.dart' show InscriptionPageWidget;
import 'package:flutter/material.dart';

class InscriptionPageModel extends FlutterFlowModel<InscriptionPageWidget> {
  ///  Local state fields for this page.

  Roles? userType = Roles.joueur;
  bool isSubmitting = false;

  ///  State fields for stateful widgets in this page.

  final formKey2 = GlobalKey<FormState>();
  final formKey1 = GlobalKey<FormState>();
  // State field(s) for TabBar widget.
  TabController? tabBarController;
  int get tabBarCurrentIndex =>
      tabBarController != null ? tabBarController!.index : 0;
  int get tabBarPreviousIndex =>
      tabBarController != null ? tabBarController!.previousIndex : 0;

  // State field(s) for emailAddressJoueur widget.
  FocusNode? emailAddressJoueurFocusNode;
  TextEditingController? emailAddressJoueurTextController;
  String? Function(BuildContext, String?)?
      emailAddressJoueurTextControllerValidator;
  String? _emailAddressJoueurTextControllerValidator(
      BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Veuillez saisir votre mail';
    }

    if (!RegExp(kTextValidatorEmailRegex).hasMatch(val)) {
      return 'Veuillez saisir une adresse mail valide';
    }
    return null;
  }

  // State field(s) for passwordJoueur widget.
  FocusNode? passwordJoueurFocusNode;
  TextEditingController? passwordJoueurTextController;
  late bool passwordJoueurVisibility;
  String? Function(BuildContext, String?)?
      passwordJoueurTextControllerValidator;
  String? _passwordJoueurTextControllerValidator(
      BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Un mot de passe est obligatoire';
    }

    if (val.length < 5) {
      return 'Un mot de passe \u00E0 minimum 5 caract\u00E8res est n\u00E9cessaire';
    }

    return null;
  }

  // State field(s) for passwordConfirmJoueur widget.
  FocusNode? passwordConfirmJoueurFocusNode;
  TextEditingController? passwordConfirmJoueurTextController;
  late bool passwordConfirmJoueurVisibility;
  String? Function(BuildContext, String?)?
      passwordConfirmJoueurTextControllerValidator;
  String? _passwordConfirmJoueurTextControllerValidator(
      BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Ce champ est obligatoire, il doit \u00EAtre identique au mot de passe';
    }

    if (val.length < 5) {
      return 'Un mot de passe \u00E0 minimum 5 caract\u00E8res est n\u00E9cessaire';
    }

    return null;
  }

  // State field(s) for CheckboxJoueur widget.
  bool? checkboxJoueurValue;
  // State field(s) for referralCodeJoueur widget.
  FocusNode? referralCodeJoueurFocusNode;
  TextEditingController? referralCodeJoueurTextController;
  String? Function(BuildContext, String?)?
      referralCodeJoueurTextControllerValidator;
  // State field(s) for emailAddressCommercant widget.
  FocusNode? emailAddressCommercantFocusNode;
  TextEditingController? emailAddressCommercantTextController;
  String? Function(BuildContext, String?)?
      emailAddressCommercantTextControllerValidator;
  String? _emailAddressCommercantTextControllerValidator(
      BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Veuillez saisir une adresse mail valide';
    }

    return null;
  }

  // State field(s) for passwordCommercant widget.
  FocusNode? passwordCommercantFocusNode;
  TextEditingController? passwordCommercantTextController;
  late bool passwordCommercantVisibility;
  String? Function(BuildContext, String?)?
      passwordCommercantTextControllerValidator;
  String? _passwordCommercantTextControllerValidator(
      BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Un mot de passe est obligatoire';
    }

    if (val.length < 5) {
      return 'Un mot de passe \u00E0 minimum 5 caract\u00E8res est n\u00E9cessaire';
    }

    return null;
  }

  // State field(s) for passwordConfirmCommercant widget.
  FocusNode? passwordConfirmCommercantFocusNode;
  TextEditingController? passwordConfirmCommercantTextController;
  late bool passwordConfirmCommercantVisibility;
  String? Function(BuildContext, String?)?
      passwordConfirmCommercantTextControllerValidator;
  String? _passwordConfirmCommercantTextControllerValidator(
      BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Ce champ est obligatoire, il doit \u00EAtre identique au mot de passe';
    }

    if (val.length < 5) {
      return 'Un mot de passe \u00E0 minimum 5 caract\u00E8res est n\u00E9cessaire';
    }

    return null;
  }

  // State field(s) for CheckboxCommercant widget.
  bool? checkboxCommercantValue;
  // State field(s) for referralCodeCommercant widget.
  FocusNode? referralCodeCommercantFocusNode;
  TextEditingController? referralCodeCommercantTextController;
  String? Function(BuildContext, String?)?
      referralCodeCommercantTextControllerValidator;
  // State field(s) for professionalCategory widget.
  String? professionalCategoryValue;

  @override
  void initState(BuildContext context) {
    emailAddressJoueurTextControllerValidator =
        _emailAddressJoueurTextControllerValidator;
    passwordJoueurVisibility = false;
    passwordJoueurTextControllerValidator =
        _passwordJoueurTextControllerValidator;
    passwordConfirmJoueurVisibility = false;
    passwordConfirmJoueurTextControllerValidator =
        _passwordConfirmJoueurTextControllerValidator;
    emailAddressCommercantTextControllerValidator =
        _emailAddressCommercantTextControllerValidator;
    passwordCommercantVisibility = false;
    passwordCommercantTextControllerValidator =
        _passwordCommercantTextControllerValidator;
    passwordConfirmCommercantVisibility = false;
    passwordConfirmCommercantTextControllerValidator =
        _passwordConfirmCommercantTextControllerValidator;
  }

  @override
  void dispose() {
    tabBarController?.dispose();
    emailAddressJoueurFocusNode?.dispose();
    emailAddressJoueurTextController?.dispose();

    passwordJoueurFocusNode?.dispose();
    passwordJoueurTextController?.dispose();

    passwordConfirmJoueurFocusNode?.dispose();
    passwordConfirmJoueurTextController?.dispose();
    referralCodeJoueurFocusNode?.dispose();
    referralCodeJoueurTextController?.dispose();

    emailAddressCommercantFocusNode?.dispose();
    emailAddressCommercantTextController?.dispose();

    passwordCommercantFocusNode?.dispose();
    passwordCommercantTextController?.dispose();

    passwordConfirmCommercantFocusNode?.dispose();
    passwordConfirmCommercantTextController?.dispose();
    referralCodeCommercantFocusNode?.dispose();
    referralCodeCommercantTextController?.dispose();
  }
}
