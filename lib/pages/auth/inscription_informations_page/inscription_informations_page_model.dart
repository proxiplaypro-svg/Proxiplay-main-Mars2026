import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'inscription_informations_page_widget.dart'
    show InscriptionInformationsPageWidget;
import 'package:flutter/material.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

class InscriptionInformationsPageModel
    extends FlutterFlowModel<InscriptionInformationsPageWidget> {
  ///  Local state fields for this page.

  FFUploadedFile? photoCarteIdentite;

  ///  State fields for stateful widgets in this page.

  final formKey = GlobalKey<FormState>();
  // State field(s) for nom widget.
  FocusNode? nomFocusNode;
  TextEditingController? nomTextController;
  String? Function(BuildContext, String?)? nomTextControllerValidator;
  String? _nomTextControllerValidator(BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Champ obligatoire';
    }

    return null;
  }

  // State field(s) for prenom widget.
  FocusNode? prenomFocusNode;
  TextEditingController? prenomTextController;
  String? Function(BuildContext, String?)? prenomTextControllerValidator;
  String? _prenomTextControllerValidator(BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Champ obligatoire';
    }

    return null;
  }

  DateTime? datePicked;
  // State field(s) for pseudo widget.
  FocusNode? pseudoFocusNode;
  TextEditingController? pseudoTextController;
  String? Function(BuildContext, String?)? pseudoTextControllerValidator;
  String? _pseudoTextControllerValidator(BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Champ obligatoire';
    }

    if (val.length < 5) {
      return 'Le pseudo doit comporter 5 caractères au minimum';
    }

    return null;
  }

  // State field(s) for ville widget.
  FocusNode? villeFocusNode;
  TextEditingController? villeTextController;
  String? Function(BuildContext, String?)? villeTextControllerValidator;
  String? _villeTextControllerValidator(BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Champ obligatoire';
    }

    return null;
  }

  // State field(s) for telephone widget.
  FocusNode? telephoneFocusNode;
  TextEditingController? telephoneTextController;
  late MaskTextInputFormatter telephoneMask;
  String? Function(BuildContext, String?)? telephoneTextControllerValidator;
  String? _telephoneTextControllerValidator(BuildContext context, String? val) {
    if (val == null || val.isEmpty) {
      return 'Numéro de téléphone obligatoire';
    }

    return null;
  }

  @override
  void initState(BuildContext context) {
    nomTextControllerValidator = _nomTextControllerValidator;
    prenomTextControllerValidator = _prenomTextControllerValidator;
    pseudoTextControllerValidator = _pseudoTextControllerValidator;
    villeTextControllerValidator = _villeTextControllerValidator;
    telephoneTextControllerValidator = _telephoneTextControllerValidator;
  }

  @override
  void dispose() {
    nomFocusNode?.dispose();
    nomTextController?.dispose();

    prenomFocusNode?.dispose();
    prenomTextController?.dispose();

    pseudoFocusNode?.dispose();
    pseudoTextController?.dispose();

    villeFocusNode?.dispose();
    villeTextController?.dispose();

    telephoneFocusNode?.dispose();
    telephoneTextController?.dispose();
  }
}


