import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_animations.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/index.dart';
import '/services/city_autocomplete_service.dart';
import '/utils/city_compat.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'inscription_informations_page_model.dart';
export 'inscription_informations_page_model.dart';

class InscriptionInformationsPageWidget extends StatefulWidget {
  const InscriptionInformationsPageWidget({super.key});

  static String routeName = 'InscriptionInformationsPage';
  static String routePath = 'inscriptionInformationsPage';

  @override
  State<InscriptionInformationsPageWidget> createState() =>
      _InscriptionInformationsPageWidgetState();
}

class _InscriptionInformationsPageWidgetState
    extends State<InscriptionInformationsPageWidget>
    with TickerProviderStateMixin {
  late InscriptionInformationsPageModel _model;
  final CityAutocompleteService _cityAutocompleteService =
      const CityAutocompleteService();
  Timer? _citySearchDebounce;
  List<CityAutocompleteSuggestion> _citySuggestions = const [];
  bool _isCityLoading = false;
  bool _isSubmitting = false;
  bool _hasNavigatedAway = false;
  String? _citySearchError;
  bool _hasSeededInitialValues = false;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  final animationsMap = <String, AnimationInfo>{};

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => InscriptionInformationsPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'InscriptionInformationsPage'});
    _model.nomTextController ??= TextEditingController();
    _model.nomFocusNode ??= FocusNode();

    _model.prenomTextController ??= TextEditingController();
    _model.prenomFocusNode ??= FocusNode();

    _model.villeTextController ??= TextEditingController();
    _model.villeFocusNode ??= FocusNode();
    _model.villeFocusNode?.addListener(() {
      if (!(_model.villeFocusNode?.hasFocus ?? false) && mounted) {
        safeSetState(() {
          _citySuggestions = const [];
          _citySearchError = null;
        });
      }
    });

    _model.telephoneTextController ??= TextEditingController();
    _model.telephoneFocusNode ??= FocusNode();

    _model.telephoneMask = MaskTextInputFormatter(mask: '## ## ## ## ##');
    unawaited(_loadInitialUserPrefill());
    animationsMap.addAll({
      'containerOnPageLoadAnimation': AnimationInfo(
        trigger: AnimationTrigger.onPageLoad,
        effectsBuilder: () => [
          VisibilityEffect(duration: 1.ms),
          FadeEffect(
            curve: Curves.easeInOut,
            delay: 0.0.ms,
            duration: 300.0.ms,
            begin: 0.0,
            end: 1.0,
          ),
          ScaleEffect(
            curve: Curves.bounceOut,
            delay: 0.0.ms,
            duration: 300.0.ms,
            begin: const Offset(0.6, 1.0),
            end: const Offset(1.0, 1.0),
          ),
        ],
      ),
      'textOnPageLoadAnimation': AnimationInfo(
        trigger: AnimationTrigger.onPageLoad,
        effectsBuilder: () => [
          VisibilityEffect(duration: 100.ms),
          FadeEffect(
            curve: Curves.easeInOut,
            delay: 100.0.ms,
            duration: 400.0.ms,
            begin: 0.0,
            end: 1.0,
          ),
          MoveEffect(
            curve: Curves.easeInOut,
            delay: 100.0.ms,
            duration: 400.0.ms,
            begin: const Offset(0.0, 30.0),
            end: const Offset(0.0, 0.0),
          ),
        ],
      ),
    });
  }

  Future<void> _loadInitialUserPrefill() async {
    await refreshCurrentUserDocument();
    if (!mounted) {
      return;
    }
    safeSetState(_seedFormFromCurrentUserDocument);
  }

  void _seedFormFromCurrentUserDocument() {
    final userDoc = currentUserDocument;
    if (userDoc == null || _hasSeededInitialValues) {
      return;
    }

    if ((_model.nomTextController?.text ?? '').trim().isEmpty &&
        userDoc.lastName.trim().isNotEmpty) {
      _model.nomTextController?.text = userDoc.lastName;
    }
    if ((_model.prenomTextController?.text ?? '').trim().isEmpty &&
        userDoc.firstName.trim().isNotEmpty) {
      _model.prenomTextController?.text = userDoc.firstName;
    }
    if ((_model.villeTextController?.text ?? '').trim().isEmpty &&
        userDoc.city.trim().isNotEmpty) {
      _model.villeTextController?.text = userDoc.city;
      _model.selectedCityLabel = userDoc.city;
    }
    if ((_model.telephoneTextController?.text ?? '').trim().isEmpty &&
        userDoc.phoneNumber.trim().isNotEmpty) {
      _model.telephoneTextController?.text = userDoc.phoneNumber;
    }
    _model.cityInseeCode ??=
        normalizeInseeCode(userDoc.cityInseeCode).isNotEmpty
            ? normalizeInseeCode(userDoc.cityInseeCode)
            : null;
    _model.datePicked ??= userDoc.birthday;

    _hasSeededInitialValues = true;
  }

  @override
  void dispose() {
    _citySearchDebounce?.cancel();
    _model.dispose();

    super.dispose();
  }

  Future<void> _searchCities(String rawQuery) async {
    final query = rawQuery.trim();

    if (query.length < 3) {
      if (!mounted) {
        return;
      }
      safeSetState(() {
        _isCityLoading = false;
        _citySuggestions = const [];
        _citySearchError = null;
      });
      return;
    }

    safeSetState(() {
      _isCityLoading = true;
      _citySearchError = null;
    });

    try {
      final suggestions = await _cityAutocompleteService.searchCommunes(query);
      if (!mounted ||
          !(_model.villeFocusNode?.hasFocus ?? false) ||
          _model.villeTextController.text.trim() != query) {
        return;
      }

      safeSetState(() {
        _citySuggestions = suggestions;
        _isCityLoading = false;
      });
    } catch (_) {
      if (!mounted ||
          !(_model.villeFocusNode?.hasFocus ?? false) ||
          _model.villeTextController.text.trim() != query) {
        return;
      }

      safeSetState(() {
        _citySuggestions = const [];
        _isCityLoading = false;
        _citySearchError = 'Recherche indisponible pour le moment.';
      });
    }
  }

  void _onCityChanged(String value) {
    final trimmedValue = value.trim();
    final selectedLabel = (_model.selectedCityLabel ?? '').trim();

    if (trimmedValue != selectedLabel) {
      _model.cityInseeCode = null;
      _model.selectedCityLabel = null;
    }

    _citySearchDebounce?.cancel();
    _citySearchDebounce = Timer(const Duration(milliseconds: 350), () {
      _searchCities(trimmedValue);
    });
  }

  void _selectCitySuggestion(CityAutocompleteSuggestion suggestion) {
    _citySearchDebounce?.cancel();
    _model.villeTextController?.text = suggestion.name;
    _model.villeTextController?.selection = TextSelection.collapsed(
      offset: suggestion.name.length,
    );
    safeSetState(() {
      _model.cityInseeCode = suggestion.inseeCode;
      _model.selectedCityLabel = suggestion.name;
      _citySuggestions = const [];
      _citySearchError = null;
      _isCityLoading = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _showFormMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  bool _isFirestoreNetworkError(Object error) {
    final lowered = error.toString().toLowerCase();
    return lowered.contains('unable to resolve host') ||
        lowered.contains('no address associated with hostname') ||
        lowered.contains('firestore.googleapis.com') ||
        lowered.contains('socketexception') ||
        lowered.contains('network');
  }

  void _showFirestoreUnavailableMessage() {
    _showFormMessage(
      'Connexion impossible. Vérifiez votre réseau puis réessayez.',
    );
  }

  bool _validateForm(bool isMerchant) {
    final isValid = _model.formKey.currentState?.validate() ?? false;
    if (!isValid) {
      safeSetState(() {
        _autovalidateMode = AutovalidateMode.onUserInteraction;
      });
      _showFormMessage(
        'Veuillez corriger les champs du formulaire avant de continuer.',
      );
      return false;
    }

    if (!isMerchant && _model.datePicked == null) {
      safeSetState(() {
        _autovalidateMode = AutovalidateMode.onUserInteraction;
      });
      _showFormMessage('Veuillez renseigner votre date de naissance.');
      return false;
    }

    final phoneDigits = (_model.telephoneTextController?.text ?? '')
        .replaceAll(RegExp(r'\D'), '');
    if (phoneDigits.length != 10) {
      safeSetState(() {
        _autovalidateMode = AutovalidateMode.onUserInteraction;
      });
      _showFormMessage('Veuillez saisir un numéro de téléphone valide.');
      return false;
    }

    return true;
  }

  void _navigateOnce(GoRouter router, String routeName) {
    if (!mounted || _hasNavigatedAway) {
      return;
    }
    _hasNavigatedAway = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      router.goNamed(routeName);
    });
  }

  bool get _shouldShowLegacyPseudoField => false;

  bool get _shouldHandleLegacyReconnectFallback => false;

  @override
  Widget build(BuildContext context) {
    _seedFormFromCurrentUserDocument();
    final isMerchant = currentUserDocument?.userRole == Roles.commercant;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: PopScope(
        canPop: false,
        child: Scaffold(
          key: scaffoldKey,
          backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
          body: Container(
            height: double.infinity,
            decoration: BoxDecoration(
              image: DecorationImage(
                fit: BoxFit.cover,
                image: Image.asset(
                  'assets/images/Background.png',
                ).image,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        16.0, 12.0, 0.0, 0.0),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      color: FlutterFlowTheme.of(context).primary,
                      onPressed: () async {
                        if (_isSubmitting || _hasNavigatedAway) {
                          return;
                        }
                        if (Navigator.of(context).canPop()) {
                          context.pop();
                        } else {
                          context.goNamed(InscriptionPageWidget.routeName);
                        }
                      },
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(),
                    child: Container(
                      width: 100.0,
                      height: 200.0,
                      decoration: const BoxDecoration(),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                0.0, 0.0, 0.0, 16.0),
                            child: Container(
                              width: 226.0,
                              height: 76.0,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16.0),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8.0),
                                child: SvgPicture.asset(
                                  'assets/images/logo_D_secondaire_sans_html_avec_couleurs.svg',
                                  width: 200.0,
                                  height: 80.0,
                                  fit: BoxFit.fitWidth,
                                ),
                              ),
                            ).animateOnPageLoad(
                                animationsMap['containerOnPageLoadAnimation']!),
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                0.0, 16.0, 0.0, 16.0),
                            child: Text(
                              'Informations complémentaires',
                              style: FlutterFlowTheme.of(context)
                                  .headlineSmall
                                  .override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .headlineSmall
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .headlineSmall
                                          .fontStyle,
                                    ),
                                    fontSize: 20.0,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .headlineSmall
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .headlineSmall
                                        .fontStyle,
                                  ),
                            ).animateOnPageLoad(
                                animationsMap['textOnPageLoadAnimation']!),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Form(
                    key: _model.formKey,
                    autovalidateMode: _autovalidateMode,
                    child: Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(20.0, 0.0, 20.0, 0.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                0.0, 0.0, 0.0, 16.0),
                            child: SizedBox(
                              width: double.infinity,
                              child: TextFormField(
                                controller: _model.nomTextController,
                                focusNode: _model.nomFocusNode,
                                autofocus: true,
                                autofillHints: const [AutofillHints.name],
                                obscureText: false,
                                decoration: InputDecoration(
                                  labelText: 'Nom',
                                  labelStyle: FlutterFlowTheme.of(context)
                                      .labelMedium
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .labelMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .labelMedium
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .fieldText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .labelMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .labelMedium
                                            .fontStyle,
                                      ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Color(0x00000000),
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color:
                                          FlutterFlowTheme.of(context).primary,
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: FlutterFlowTheme.of(context).error,
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: FlutterFlowTheme.of(context).error,
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  filled: true,
                                  fillColor:
                                      FlutterFlowTheme.of(context).fieldBg,
                                  contentPadding: const EdgeInsets.all(24.0),
                                ),
                                style: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                      color: FlutterFlowTheme.of(context)
                                          .primaryText,
                                      letterSpacing: 0.0,
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                validator: _model.nomTextControllerValidator
                                    .asValidator(context),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                0.0, 0.0, 0.0, 16.0),
                            child: SizedBox(
                              width: double.infinity,
                              child: TextFormField(
                                controller: _model.prenomTextController,
                                focusNode: _model.prenomFocusNode,
                                autofocus: false,
                                obscureText: false,
                                decoration: InputDecoration(
                                  labelText: 'Prénom',
                                  labelStyle: FlutterFlowTheme.of(context)
                                      .labelMedium
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .labelMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .labelMedium
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .fieldText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .labelMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .labelMedium
                                            .fontStyle,
                                      ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Color(0x00000000),
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color:
                                          FlutterFlowTheme.of(context).primary,
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: FlutterFlowTheme.of(context).error,
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: FlutterFlowTheme.of(context).error,
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  filled: true,
                                  fillColor:
                                      FlutterFlowTheme.of(context).fieldBg,
                                  contentPadding: const EdgeInsets.all(24.0),
                                ),
                                style: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                      color: FlutterFlowTheme.of(context)
                                          .primaryText,
                                      letterSpacing: 0.0,
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                validator: _model.prenomTextControllerValidator
                                    .asValidator(context),
                              ),
                            ),
                          ),
                          if (!isMerchant)
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  0.0, 0.0, 0.0, 16.0),
                              child: Container(
                                height: 60.0,
                                decoration: BoxDecoration(
                                  color: FlutterFlowTheme.of(context).fieldBg,
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(
                                      24.0, 0.0, 25.0, 0.0),
                                  child: InkWell(
                                    splashColor: Colors.transparent,
                                    focusColor: Colors.transparent,
                                    hoverColor: Colors.transparent,
                                    highlightColor: Colors.transparent,
                                    onTap: () async {
                                      final datePickedDate =
                                          await showDatePicker(
                                        context: context,
                                        initialDate:
                                            _model.datePicked ?? getCurrentTimestamp,
                                        firstDate: DateTime(1900),
                                        lastDate: getCurrentTimestamp,
                                        builder: (context, child) {
                                          return wrapInMaterialDatePickerTheme(
                                            context,
                                            child!,
                                            headerBackgroundColor:
                                                FlutterFlowTheme.of(context)
                                                    .primary,
                                            headerForegroundColor:
                                                FlutterFlowTheme.of(context)
                                                    .info,
                                            headerTextStyle:
                                                FlutterFlowTheme.of(context)
                                                    .headlineLarge
                                                    .override(
                                                      font: GoogleFonts
                                                          .interTight(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .headlineLarge
                                                                .fontStyle,
                                                      ),
                                                      fontSize: 32.0,
                                                      letterSpacing: 0.0,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .headlineLarge
                                                              .fontStyle,
                                                    ),
                                            pickerBackgroundColor:
                                                FlutterFlowTheme.of(context)
                                                    .secondaryBackground,
                                            pickerForegroundColor:
                                                FlutterFlowTheme.of(context)
                                                    .primaryText,
                                            selectedDateTimeBackgroundColor:
                                                FlutterFlowTheme.of(context)
                                                    .primary,
                                            selectedDateTimeForegroundColor:
                                                FlutterFlowTheme.of(context)
                                                    .info,
                                            actionButtonForegroundColor:
                                                FlutterFlowTheme.of(context)
                                                    .primaryText,
                                            iconSize: 24.0,
                                          );
                                        },
                                      );

                                      if (datePickedDate != null) {
                                        if (!mounted) {
                                          return;
                                        }
                                        safeSetState(() {
                                          _model.datePicked = DateTime(
                                            datePickedDate.year,
                                            datePickedDate.month,
                                            datePickedDate.day,
                                          );
                                        });
                                      }
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.max,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        if (_model.datePicked == null)
                                          Text(
                                            'Date de naissance',
                                            style: FlutterFlowTheme.of(context)
                                                .bodyMedium
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontStyle,
                                                  ),
                                                  color:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .fieldText,
                                                  letterSpacing: 0.0,
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontStyle,
                                                ),
                                          ),
                                        Padding(
                                          padding:
                                              const EdgeInsetsDirectional
                                                  .fromSTEB(
                                                      0.0, 0.0, 0.0, 1.0),
                                          child: Text(
                                            dateTimeFormat(
                                              "d/M/y",
                                              _model.datePicked,
                                              locale:
                                                  FFLocalizations.of(context)
                                                      .languageCode,
                                            ),
                                            style: FlutterFlowTheme.of(context)
                                                .bodyMedium
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontStyle,
                                                  ),
                                                  letterSpacing: 0.0,
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontStyle,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (_shouldShowLegacyPseudoField)
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  0.0, 0.0, 0.0, 16.0),
                              child: SizedBox(
                                width: double.infinity,
                                child: TextFormField(
                                  controller: _model.pseudoTextController,
                                  focusNode: _model.pseudoFocusNode,
                                  autofocus: false,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                      labelText:
                                          'Pseudo (5 caractères minimum)',
                                      labelStyle: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .override(
                                            font: GoogleFonts.inter(
                                              fontWeight:
                                                  FlutterFlowTheme.of(context)
                                                      .labelMedium
                                                      .fontWeight,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .labelMedium
                                                      .fontStyle,
                                            ),
                                            color: FlutterFlowTheme.of(context)
                                                .fieldText,
                                            letterSpacing: 0.0,
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .labelMedium
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .labelMedium
                                                    .fontStyle,
                                          ),
                                      enabledBorder: OutlineInputBorder(
                                        borderSide: const BorderSide(
                                          color: Color(0x00000000),
                                          width: 2.0,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(12.0),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                          color: FlutterFlowTheme.of(context)
                                              .primary,
                                          width: 2.0,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(12.0),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                          color: FlutterFlowTheme.of(context)
                                              .error,
                                          width: 2.0,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(12.0),
                                      ),
                                      focusedErrorBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                          color: FlutterFlowTheme.of(context)
                                              .error,
                                          width: 2.0,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(12.0),
                                      ),
                                      filled: true,
                                      fillColor:
                                          FlutterFlowTheme.of(context).fieldBg,
                                      contentPadding: const EdgeInsets.all(24.0),
                                    ),
                                  style: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        letterSpacing: 0.0,
                                        fontWeight:
                                            FlutterFlowTheme.of(context)
                                                .bodyMedium
                                                .fontWeight,
                                        fontStyle:
                                            FlutterFlowTheme.of(context)
                                                .bodyMedium
                                                .fontStyle,
                                      ),
                                  validator: _model
                                      .pseudoTextControllerValidator
                                      .asValidator(context),
                                ),
                              ),
                            ),
                          if (currentUserDocument?.userRole == Roles.joueur)
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  0.0, 0.0, 0.0, 16.0),
                              child: SizedBox(
                                width: double.infinity,
                                child: TextFormField(
                                  controller: _model.villeTextController,
                                  focusNode: _model.villeFocusNode,
                                  autofocus: false,
                                  obscureText: false,
                                  onChanged: _onCityChanged,
                                  decoration: InputDecoration(
                                      labelText: 'Ville de résidence',
                                      labelStyle: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .override(
                                            font: GoogleFonts.inter(
                                              fontWeight:
                                                  FlutterFlowTheme.of(context)
                                                      .labelMedium
                                                      .fontWeight,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .labelMedium
                                                      .fontStyle,
                                            ),
                                            color: FlutterFlowTheme.of(context)
                                                .fieldText,
                                            letterSpacing: 0.0,
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .labelMedium
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .labelMedium
                                                    .fontStyle,
                                          ),
                                      enabledBorder: OutlineInputBorder(
                                        borderSide: const BorderSide(
                                          color: Color(0x00000000),
                                          width: 2.0,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(12.0),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                          color: FlutterFlowTheme.of(context)
                                              .primary,
                                          width: 2.0,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(12.0),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                          color: FlutterFlowTheme.of(context)
                                              .error,
                                          width: 2.0,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(12.0),
                                      ),
                                      focusedErrorBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                          color: FlutterFlowTheme.of(context)
                                              .error,
                                          width: 2.0,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(12.0),
                                      ),
                                      filled: true,
                                      fillColor:
                                          FlutterFlowTheme.of(context).fieldBg,
                                      contentPadding: const EdgeInsets.all(24.0),
                                    ),
                                  style: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        letterSpacing: 0.0,
                                        fontWeight:
                                            FlutterFlowTheme.of(context)
                                                .bodyMedium
                                                .fontWeight,
                                        fontStyle:
                                            FlutterFlowTheme.of(context)
                                                .bodyMedium
                                                .fontStyle,
                                      ),
                                  validator: _model
                                      .villeTextControllerValidator
                                      .asValidator(context),
                                ),
                              ),
                            ),
                          if (currentUserDocument?.userRole == Roles.joueur &&
                              (_isCityLoading ||
                                  _citySearchError != null ||
                                  _citySuggestions.isNotEmpty))
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  0.0, 0.0, 0.0, 16.0),
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryBackground,
                                  borderRadius: BorderRadius.circular(12.0),
                                  border: Border.all(
                                    color:
                                        FlutterFlowTheme.of(context).alternate,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isCityLoading)
                                      const Padding(
                                        padding: EdgeInsets.all(16.0),
                                        child: SizedBox(
                                          width: 20.0,
                                          height: 20.0,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.0,
                                          ),
                                        ),
                                      ),
                                    if (!_isCityLoading &&
                                        _citySearchError != null)
                                      Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Text(
                                          _citySearchError!,
                                          style: FlutterFlowTheme.of(context)
                                              .bodySmall,
                                        ),
                                      ),
                                    if (!_isCityLoading)
                                      ..._citySuggestions.map(
                                        (suggestion) => ListTile(
                                          dense: true,
                                          title: Text(
                                            suggestion.name,
                                            style: FlutterFlowTheme.of(context)
                                                .bodyMedium,
                                          ),
                                          subtitle: Text(
                                            suggestion.subtitle,
                                            style: FlutterFlowTheme.of(context)
                                                .bodySmall,
                                          ),
                                          onTap: () =>
                                              _selectCitySuggestion(suggestion),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                0.0, 0.0, 0.0, 16.0),
                            child: SizedBox(
                              width: double.infinity,
                              child: TextFormField(
                                controller: _model.telephoneTextController,
                                focusNode: _model.telephoneFocusNode,
                                autofocus: false,
                                autofillHints: const [AutofillHints.telephoneNumber],
                                obscureText: false,
                                decoration: InputDecoration(
                                  labelText: 'Numéro de téléphone',
                                  labelStyle: FlutterFlowTheme.of(context)
                                      .labelMedium
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .labelMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .labelMedium
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .fieldText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .labelMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .labelMedium
                                            .fontStyle,
                                      ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Color(0x00000000),
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color:
                                          FlutterFlowTheme.of(context).primary,
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: FlutterFlowTheme.of(context).error,
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: FlutterFlowTheme.of(context).error,
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  filled: true,
                                  fillColor:
                                      FlutterFlowTheme.of(context).fieldBg,
                                  contentPadding: const EdgeInsets.all(24.0),
                                ),
                                style: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                      color: FlutterFlowTheme.of(context)
                                          .primaryText,
                                      letterSpacing: 0.0,
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                keyboardType: TextInputType.phone,
                                validator: _model
                                    .telephoneTextControllerValidator
                                    .asValidator(context),
                                inputFormatters: [_model.telephoneMask],
                              ),
                            ),
                          ),
                          Align(
                            alignment: const AlignmentDirectional(0.0, 0.0),
                            child: Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  0.0, 0.0, 0.0, 20.0),
                              child: FFButtonWidget(
                                onPressed: () async {
                                  if (_isSubmitting || _hasNavigatedAway) {
                                    return;
                                  }
                                  final router = GoRouter.of(context);
                                  FocusScope.of(context).unfocus();
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  _citySearchDebounce?.cancel();
                                  if (!_validateForm(isMerchant)) {
                                    return;
                                  }

                                  // This page assumes an authenticated user (it updates the current user's doc).
                                  // Guard against edge cases where auth state/doc isn't ready yet.
                                  if (currentUserReference == null) {
                                    _showFormMessage(
                                      'Veuillez vous reconnecter (session expirée).',
                                    );
                                    _navigateOnce(
                                      router,
                                      LoginPageWidget.routeName,
                                    );
                                    return;
                                  }

                                  if (_shouldHandleLegacyReconnectFallback &&
                                      currentUserReference == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "Veuillez vous reconnecter (session expirée).",
                                        ),
                                      ),
                                    );
                                    router.goNamed(LoginPageWidget.routeName);
                                    return;
                                  }

                                  final normalizedCityInseeCode =
                                      normalizeInseeCode(_model.cityInseeCode);

                                  safeSetState(() {
                                    _isSubmitting = true;
                                  });
                                  try {
                                    await currentUserReference!.set(
                                        createUsersRecordData(
                                      phoneNumber: _model
                                          .telephoneTextController.text
                                          .trim(),
                                      firstName:
                                          _model.prenomTextController.text.trim(),
                                      lastName:
                                          _model.nomTextController.text.trim(),
                                      city:
                                          _model.villeTextController.text.trim(),
                                      cityInseeCode:
                                          normalizedCityInseeCode.isNotEmpty
                                              ? normalizedCityInseeCode
                                              : null,
                                      birthday:
                                          isMerchant ? null : _model.datePicked,
                                    ),
                                        SetOptions(merge: true));
                                    await refreshCurrentUserDocument();
                                    if (!mounted) {
                                      return;
                                    }
                                    final destination = isMerchant
                                        ? WaitingValidationPageWidget.routeName
                                        : HomeJoueurPageWidget.routeName;
                                    _navigateOnce(router, destination);
                                  } catch (error) {
                                    debugPrint(
                                      'Signup completion error: $error',
                                    );
                                    debugPrintStack();
                                    if (_isFirestoreNetworkError(error)) {
                                      _showFirestoreUnavailableMessage();
                                    } else {
                                      _showFormMessage(
                                        'Une erreur est survenue pendant la finalisation de votre inscription.',
                                      );
                                    }
                                  } finally {
                                    if (mounted && !_hasNavigatedAway) {
                                      safeSetState(() {
                                        _isSubmitting = false;
                                      });
                                    }
                                  }
                                  return;
                                },
                                text: 'Suivant',
                                options: FFButtonOptions(
                                  width: double.infinity,
                                  height: 52.0,
                                  padding: const EdgeInsetsDirectional.fromSTEB(
                                      0.0, 0.0, 0.0, 0.0),
                                  iconPadding: const EdgeInsetsDirectional.fromSTEB(
                                      0.0, 0.0, 0.0, 0.0),
                                  color: FlutterFlowTheme.of(context).primary,
                                  textStyle: FlutterFlowTheme.of(context)
                                      .titleSmall
                                      .override(
                                        font: GoogleFonts.interTight(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .titleSmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .titleSmall
                                                  .fontStyle,
                                        ),
                                        color: Colors.white,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .titleSmall
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .titleSmall
                                            .fontStyle,
                                      ),
                                  elevation: 0.0,
                                  borderSide: const BorderSide(
                                    color: Colors.transparent,
                                    width: 1.0,
                                  ),
                                  borderRadius: BorderRadius.circular(12.0),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
