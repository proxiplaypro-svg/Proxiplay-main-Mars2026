import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_animations.dart';
import '/flutter_flow/flutter_flow_button_tabbar.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:math';
import 'dart:ui';
import '/index.dart';
import 'inscription_page_widget.dart' show InscriptionPageWidget;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class InscriptionPageModel extends FlutterFlowModel<InscriptionPageWidget> {
  ///  Local state fields for this page.

  Roles? userType = Roles.joueur;

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
      return 'Un mot de passe à minimum 5 caractères est nécessaire';
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
      return 'Ce champ est obligatoire, il doit être identique au mot de passe';
    }

    if (val.length < 5) {
      return 'Un mot de passe à minimum 5 caractères est nécessaire';
    }

    return null;
  }

  // State field(s) for CheckboxJoueur widget.
  bool? checkboxJoueurValue;
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
      return 'Un mot de passe à minimum 5 caractères est nécessaire';
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
      return 'Ce champ est obligatoire, il doit être identique au mot de passe';
    }

    if (val.length < 5) {
      return 'Un mot de passe à minimum 5 caractères est nécessaire';
    }

    return null;
  }

  // State field(s) for CheckboxCommercant widget.
  bool? checkboxCommercantValue;

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

    emailAddressCommercantFocusNode?.dispose();
    emailAddressCommercantTextController?.dispose();

    passwordCommercantFocusNode?.dispose();
    passwordCommercantTextController?.dispose();

    passwordConfirmCommercantFocusNode?.dispose();
    passwordConfirmCommercantTextController?.dispose();
  }
}
