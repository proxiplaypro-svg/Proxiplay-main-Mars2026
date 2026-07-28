import '/auth/firebase_auth/auth_util.dart';
import '/auth/firebase_auth/account_routing.dart';
import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_animations.dart';
import '/flutter_flow/flutter_flow_button_tabbar.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/index.dart';
import '/services/share_promo_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'inscription_page_model.dart';
export 'inscription_page_model.dart';

class InscriptionPageWidget extends StatefulWidget {
  const InscriptionPageWidget({super.key});

  static String routeName = 'InscriptionPage';
  static String routePath = 'inscriptionPage';

  @override
  State<InscriptionPageWidget> createState() => _InscriptionPageWidgetState();
}

class _InscriptionPageWidgetState extends State<InscriptionPageWidget>
    with TickerProviderStateMixin {
  late InscriptionPageModel _model;
  final SharePromoService _sharePromoService = SharePromoService();
  bool _isApplyingPendingReferralCode = false;
  bool _isSubmittingPlayerSignup = false;
  bool _isSubmittingMerchantSignup = false;
  bool _showEmailForm = false;
  AutovalidateMode _playerAutovalidateMode = AutovalidateMode.disabled;
  AutovalidateMode _merchantAutovalidateMode = AutovalidateMode.disabled;
  String? _lastAppliedReferralGuardKey;
  String? _lastReferralErrorMessage;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  final animationsMap = <String, AnimationInfo>{};

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => InscriptionPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'InscriptionPage'});
    _model.tabBarController = TabController(
      vsync: this,
      length: 2,
      initialIndex: 0,
    )..addListener(() => safeSetState(() {}));

    _model.emailAddressJoueurTextController ??= TextEditingController();
    _model.emailAddressJoueurFocusNode ??= FocusNode();

    _model.passwordJoueurTextController ??= TextEditingController();
    _model.passwordJoueurFocusNode ??= FocusNode();

    _model.passwordConfirmJoueurTextController ??= TextEditingController();
    _model.passwordConfirmJoueurFocusNode ??= FocusNode();
    _model.referralCodeJoueurTextController ??= TextEditingController(
      text: _initialReferralCodeValue,
    );
    _model.referralCodeJoueurFocusNode ??= FocusNode();

    _model.emailAddressCommercantTextController ??= TextEditingController();
    _model.emailAddressCommercantFocusNode ??= FocusNode();

    _model.passwordCommercantTextController ??= TextEditingController();
    _model.passwordCommercantFocusNode ??= FocusNode();

    _model.passwordConfirmCommercantTextController ??= TextEditingController();
    _model.passwordConfirmCommercantFocusNode ??= FocusNode();
    _model.referralCodeCommercantTextController ??= TextEditingController(
      text: _initialReferralCodeValue,
    );
    _model.referralCodeCommercantFocusNode ??= FocusNode();

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
      'columnOnPageLoadAnimation1': AnimationInfo(
        trigger: AnimationTrigger.onPageLoad,
        effectsBuilder: () => [
          FadeEffect(
            curve: Curves.easeInOut,
            delay: 200.0.ms,
            duration: 400.0.ms,
            begin: 0.0,
            end: 1.0,
          ),
          MoveEffect(
            curve: Curves.easeInOut,
            delay: 200.0.ms,
            duration: 400.0.ms,
            begin: const Offset(0.0, 60.0),
            end: const Offset(0.0, 0.0),
          ),
          TiltEffect(
            curve: Curves.easeInOut,
            delay: 200.0.ms,
            duration: 400.0.ms,
            begin: const Offset(-0.349, 0),
            end: const Offset(0, 0),
          ),
        ],
      ),
      'columnOnPageLoadAnimation2': AnimationInfo(
        trigger: AnimationTrigger.onPageLoad,
        effectsBuilder: () => [
          FadeEffect(
            curve: Curves.easeInOut,
            delay: 200.0.ms,
            duration: 400.0.ms,
            begin: 0.0,
            end: 1.0,
          ),
          MoveEffect(
            curve: Curves.easeInOut,
            delay: 200.0.ms,
            duration: 400.0.ms,
            begin: const Offset(0.0, 60.0),
            end: const Offset(0.0, 0.0),
          ),
          TiltEffect(
            curve: Curves.easeInOut,
            delay: 200.0.ms,
            duration: 400.0.ms,
            begin: const Offset(-0.349, 0),
            end: const Offset(0, 0),
          ),
        ],
      ),
    });
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  void _logGoogleSignup(String message) {}

  Future<UsersRecord?> _ensureGooglePlayerProfileBootstrap() async {
    final userRef = currentUserReference;
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (userRef == null || firebaseUser == null) {
      _logGoogleSignup(
        'profileBootstrapSkipped userRefIsNull=${userRef == null} '
        'firebaseUserIsNull=${firebaseUser == null}',
      );
      return null;
    }

    _logGoogleSignup('profileBootstrapStart');
    final userDoc = await refreshCurrentUserDocument();
    final isExistingUserDoc = userDoc != null;

    await userRef.set(
      <String, dynamic>{
        ...createUsersRecordData(
          email: userDoc?.hasEmail() == true ? null : firebaseUser.email,
          displayName: userDoc?.hasDisplayName() == true
              ? null
              : firebaseUser.displayName,
          photoUrl:
              userDoc?.hasPhotoUrl() == true ? null : firebaseUser.photoURL,
          uid: isExistingUserDoc ? null : firebaseUser.uid,
          phoneNumber:
              userDoc?.hasPhoneNumber() == true ? null : firebaseUser.phoneNumber,
          userRole: isExistingUserDoc ? null : Roles.joueur,
        ),
      },
      SetOptions(merge: true),
    );

    await ensureUserDocumentInitialized(
      firebaseUser,
      roleHint: Roles.joueur,
      authProvider: 'GOOGLE',
      source: 'google_signup_bootstrap',
    );

    final refreshedUserDoc = await refreshCurrentUserDocument();
    _logGoogleSignup(
      'profileBootstrapCompleted '
      'docExists=${refreshedUserDoc != null} '
      'role=${refreshedUserDoc?.userRole?.serialize()} '
      'status=${refreshedUserDoc?.accountStatus?.serialize()}',
    );
    return refreshedUserDoc;
  }

  Future<void> _handleGooglePlayerSignup() async {
    _logGoogleSignup('startGoogleSignupFlow');
    GoRouter.of(context).prepareAuthEvent(true);
    _persistReferralCodeInput(
      _model.referralCodeJoueurTextController?.text ?? '',
    );

    final user = await authManager.signInWithGoogle(context);
    if (user == null || !context.mounted) {
      if (mounted) {
        _showGoogleSignupFailedMessage();
      }
      _logGoogleSignup(
        'googleSignupAborted userIsNull=${user == null} mounted=$mounted',
      );
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    _logGoogleSignup(
      'firebaseUserAfterGoogleSignIn '
      'userPresent=${firebaseUser != null}',
    );
    if (firebaseUser == null) {
      _logGoogleSignup('googleSignupStoppedBecauseFirebaseUserIsNull');
      return;
    }

    UsersRecord? refreshedUserDoc;
    try {
      refreshedUserDoc = await _ensureGooglePlayerProfileBootstrap();
    } catch (error) {
      debugPrint('Google signup Firestore bootstrap error: $error');
      debugPrintStack();
      if (mounted) {
        if (_isFirestoreNetworkError(error)) {
          _showFirestoreUnavailableMessage();
        } else {
          _showGoogleSignupFailedMessage();
        }
      }
      return;
    }

    final referralApplied = await _applyPendingReferralCodeIfNeeded();
    if (!referralApplied && (_lastReferralErrorMessage ?? '').isNotEmpty) {
      _showReferralErrorMessage(
        _lastReferralErrorMessage!,
      );
    }

    if (!mounted) {
      return;
    }

    final needsAdditionalInfo = refreshedUserDoc == null ||
        !refreshedUserDoc.hasFirstName() ||
        !refreshedUserDoc.hasLastName() ||
        !refreshedUserDoc.hasCity() ||
        !refreshedUserDoc.hasPhoneNumber() ||
        !refreshedUserDoc.hasBirthday();

    if (needsAdditionalInfo) {
      _logGoogleSignup('navigationAfterGoogleSignup destination=pendingInfo');
      context.goNamedAuth(
        InscriptionInformationsPageWidget.routeName,
        mounted,
        ignoreRedirect: true,
      );
      return;
    }

    final resolution = await resolveAuthenticatedHome(
      source: 'google_signup',
      preferServer: true,
    );
    _logGoogleSignup(
      'navigationAfterGoogleSignup '
      'target=${resolution.target.name} '
      'reason=${resolution.reason} '
      'firebaseUserStillPresent=${FirebaseAuth.instance.currentUser != null}',
    );

    if (!mounted) {
      return;
    }

    switch (resolution.target) {
      case AuthenticatedHomeTarget.pendingInfo:
        context.goNamedAuth(
          InscriptionInformationsPageWidget.routeName,
          mounted,
          ignoreRedirect: true,
        );
        return;
      case AuthenticatedHomeTarget.joueurHome:
        context.goNamedAuth(
          HomeJoueurPageWidget.routeName,
          mounted,
          ignoreRedirect: true,
        );
        return;
      case AuthenticatedHomeTarget.routingIssue:
        _showGoogleSignupFailedMessage();
        return;
      case AuthenticatedHomeTarget.commercantHome:
      case AuthenticatedHomeTarget.adminHome:
      case AuthenticatedHomeTarget.waitingValidation:
      case AuthenticatedHomeTarget.rejected:
      case AuthenticatedHomeTarget.login:
        context.goNamedAuth(
          resolution.routeName,
          mounted,
          ignoreRedirect: true,
        );
        return;
    }
  }

  void _showTermsRequiredMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Veuillez accepter les conditions générales d\'utilisation pour continuer.',
        ),
      ),
    );
  }

  void _showGoogleSignupFailedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'La connexion Google a échoué ou a été annulée. Veuillez réessayer.',
        ),
      ),
    );
  }

  void _showFirestoreUnavailableMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Connexion impossible. Vérifiez votre réseau puis réessayez.',
        ),
      ),
    );
  }

  // Filet de sécurité pour toute erreur pendant l'inscription qui n'est pas
  // une erreur réseau reconnue : sans ça, l'utilisateur ne voit aucun
  // message alors que son compte Auth a peut-être déjà été créé, et un
  // nouvel essai échoue avec "email déjà utilisé" sans explication.
  void _showSignupFallbackErrorMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Un problème est survenu pendant la création de votre compte. '
          'Si un nouvel essai indique que l\'email est déjà utilisé, '
          'essayez plutôt de vous connecter avec cet email : votre compte '
          'a peut-être déjà été créé.',
        ),
        duration: Duration(seconds: 8),
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

  void _showInvalidSignupFormMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Veuillez corriger les champs du formulaire avant de continuer.',
        ),
      ),
    );
  }

  bool _validatePlayerSignupForm() {
    final isValid = _model.formKey2.currentState?.validate() ?? false;
    if (!isValid) {
      safeSetState(() {
        _playerAutovalidateMode = AutovalidateMode.onUserInteraction;
      });
      _showInvalidSignupFormMessage();
    }
    return isValid;
  }

  bool _validateMerchantSignupForm() {
    final isValid = _model.formKey1.currentState?.validate() ?? false;
    if (!isValid) {
      safeSetState(() {
        _merchantAutovalidateMode = AutovalidateMode.onUserInteraction;
      });
      _showInvalidSignupFormMessage();
    }
    return isValid;
  }

  void _focusPlayerEmailForm() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _model.emailAddressJoueurFocusNode?.requestFocus();
    });
  }

  void _openPlayerEmailForm() {
    safeSetState(() {
      _showEmailForm = true;
      _playerAutovalidateMode = AutovalidateMode.disabled;
    });
    _focusPlayerEmailForm();
  }

  void _closePlayerEmailForm() {
    FocusScope.of(context).unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    safeSetState(() {
      _showEmailForm = false;
    });
  }

  void _togglePlayerTermsAcceptance() {
    safeSetState(() {
      _model.checkboxJoueurValue = !(_model.checkboxJoueurValue ?? false);
    });
  }

  void _toggleMerchantTermsAcceptance() {
    safeSetState(() {
      _model.checkboxCommercantValue = !(_model.checkboxCommercantValue ?? false);
    });
  }

  bool get _showProfessionalCategoryField => false;

  Widget _buildPlayerTermsCheckbox() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Theme(
          data: ThemeData(
            checkboxTheme: CheckboxThemeData(
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4.0),
              ),
            ),
            unselectedWidgetColor: FlutterFlowTheme.of(context).primaryText,
          ),
          child: Checkbox(
            value: _model.checkboxJoueurValue ??= false,
            onChanged: (newValue) async {
              safeSetState(() => _model.checkboxJoueurValue = newValue!);
            },
            side: BorderSide(
              width: 2,
              color: FlutterFlowTheme.of(context).primaryText,
            ),
            activeColor: FlutterFlowTheme.of(context).primary,
            checkColor: FlutterFlowTheme.of(context).info,
          ),
        ),
        Flexible(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(0.0, 5.0, 0.0, 0.0),
            child: InkWell(
              splashColor: Colors.transparent,
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onTap: _togglePlayerTermsAcceptance,
              onLongPress: () async {
                context.pushNamed(LegalPageWidget.routeName);
              },
              child: RichText(
                textScaler: MediaQuery.of(context).textScaler,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'En cochant la case, vous acceptez nos',
                      style: FlutterFlowTheme.of(context).bodyMedium.override(
                            font: GoogleFonts.inter(
                              fontWeight: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontWeight,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontStyle,
                            ),
                            letterSpacing: 0.0,
                            fontWeight: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .fontWeight,
                            fontStyle: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .fontStyle,
                          ),
                    ),
                    const TextSpan(text: ' '),
                    TextSpan(
                      text: 'conditions générales d\'utilisation',
                      style: FlutterFlowTheme.of(context).bodyMedium.override(
                            font: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontStyle,
                            ),
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.bold,
                            fontStyle: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .fontStyle,
                          ),
                    ),
                    const TextSpan(text: ' ainsi que notre '),
                    TextSpan(
                      text: 'politique de confidentialité',
                      style: FlutterFlowTheme.of(context).bodyMedium.override(
                            font: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontStyle,
                            ),
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.bold,
                            fontStyle: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .fontStyle,
                          ),
                    ),
                  ],
                  style: FlutterFlowTheme.of(context).bodyMedium.override(
                        font: GoogleFonts.inter(
                          fontWeight:
                              FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                          fontStyle:
                              FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                        ),
                        letterSpacing: 0.0,
                        fontWeight:
                            FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                      ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerEntryButtons() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 16.0),
      child: Column(
        children: [
          FFButtonWidget(
            onPressed: () async {
              if (_model.checkboxJoueurValue != true) {
                _showTermsRequiredMessage();
                return;
              }

              await _handleGooglePlayerSignup();
            },
            text: 'Continuer avec Google',
            icon: const FaIcon(
              FontAwesomeIcons.google,
              size: 18.0,
            ),
            options: FFButtonOptions(
              width: double.infinity,
              height: 52.0,
              padding:
                  const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 0.0),
              iconPadding:
                  const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 0.0),
              color: Colors.white,
              textStyle: FlutterFlowTheme.of(context).titleSmall.override(
                    font: GoogleFonts.interTight(
                      fontWeight:
                          FlutterFlowTheme.of(context).titleSmall.fontWeight,
                      fontStyle:
                          FlutterFlowTheme.of(context).titleSmall.fontStyle,
                    ),
                    color: FlutterFlowTheme.of(context).primaryText,
                    letterSpacing: 0.0,
                    fontWeight:
                        FlutterFlowTheme.of(context).titleSmall.fontWeight,
                    fontStyle:
                        FlutterFlowTheme.of(context).titleSmall.fontStyle,
                  ),
              elevation: 0.0,
              borderSide: const BorderSide(
                color: Color(0xFFDADADA),
                width: 1.0,
              ),
              borderRadius: BorderRadius.circular(12.0),
            ),
          ),
          const SizedBox(height: 12.0),
          FFButtonWidget(
            onPressed: () async {
              if (_model.checkboxJoueurValue != true) {
                _showTermsRequiredMessage();
                return;
              }
              _openPlayerEmailForm();
            },
            text: 'Continuer avec l\'e-mail',
            icon: const Icon(
              Icons.mail_outline_rounded,
              size: 22.0,
            ),
            options: FFButtonOptions(
              width: double.infinity,
              height: 52.0,
              padding:
                  const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 0.0),
              iconPadding:
                  const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 0.0),
              color: Colors.white,
              textStyle: FlutterFlowTheme.of(context).titleSmall.override(
                    font: GoogleFonts.interTight(
                      fontWeight:
                          FlutterFlowTheme.of(context).titleSmall.fontWeight,
                      fontStyle:
                          FlutterFlowTheme.of(context).titleSmall.fontStyle,
                    ),
                    color: FlutterFlowTheme.of(context).primaryText,
                    letterSpacing: 0.0,
                    fontWeight:
                        FlutterFlowTheme.of(context).titleSmall.fontWeight,
                    fontStyle:
                        FlutterFlowTheme.of(context).titleSmall.fontStyle,
                  ),
              elevation: 0.0,
              borderSide: const BorderSide(
                color: Color(0xFFDADADA),
                width: 1.0,
              ),
              borderRadius: BorderRadius.circular(12.0),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            decoration: BoxDecoration(
              image: DecorationImage(
                fit: BoxFit.cover,
                image: Image.asset(
                  'assets/images/Background.png',
                ).image,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
		              children: [
		                Container(
		                  width: double.infinity,
		                  decoration: const BoxDecoration(),
		                  child: Container(
		                    width: 100.0,
			                    height: 156.0,
		                    decoration: const BoxDecoration(),
		                    child: Stack(
		                      children: [
		                        Align(
		                          alignment: const AlignmentDirectional(-1.0, 0.0),
		                          child: Padding(
		                            padding: const EdgeInsetsDirectional.fromSTEB(
		                                16.0, 0.0, 0.0, 0.0),
		                            child: IconButton(
		                              icon: const Icon(Icons.arrow_back),
		                              color: FlutterFlowTheme.of(context).primary,
		                              onPressed: () async {
		                                context.goNamed(LoginPageWidget.routeName);
		                              },
		                            ),
		                          ),
		                        ),
			                        Padding(
				                          padding: const EdgeInsetsDirectional.fromSTEB(
				                              0.0, 36.0, 0.0, 0.0),
			                          child: Column(
			                          mainAxisSize: MainAxisSize.max,
			                          mainAxisAlignment: MainAxisAlignment.center,
			                          children: [
			                            Align(
		                              alignment: const AlignmentDirectional(0.0, 0.0),
		                              child: Container(
		                                width: 226.0,
		                                height: 80.0,
		                                decoration: BoxDecoration(
		                                  borderRadius: BorderRadius.circular(16.0),
		                                ),
		                                child: ClipRRect(
		                                  borderRadius: BorderRadius.circular(8.0),
		                                  child: SvgPicture.asset(
		                                    'assets/images/logo_D_secondaire_sans_html_avec_couleurs.svg',
		                                    width: 200.0,
		                                    height: 63.0,
		                                    fit: BoxFit.fitWidth,
		                                  ),
		                                ),
		                              ).animateOnPageLoad(
		                                  animationsMap['containerOnPageLoadAnimation']!),
		                            ),
			                          ],
			                        ),
			                        ),
		                      ],
		                    ),
		                  ),
		                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final tabContentHeight =
                          constraints.maxHeight > 560.0
                              ? 560.0
                              : constraints.maxHeight;
                      return Center(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                24.0, 0.0, 24.0, 0.0),
                            child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Align(
                          alignment: const Alignment(0.0, 0),
                          child: FlutterFlowButtonTabBar(
                            useToggleButtonStyle: true,
                            labelStyle: FlutterFlowTheme.of(context)
                                .titleMedium
                                .override(
                                  font: GoogleFonts.interTight(
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontStyle,
                                  ),
                                  fontSize: 16.0,
                                  letterSpacing: 0.0,
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .titleMedium
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .titleMedium
                                      .fontStyle,
                                ),
                            unselectedLabelStyle: FlutterFlowTheme.of(context)
                                .titleMedium
                                .override(
                                  font: GoogleFonts.interTight(
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontStyle,
                                  ),
                                  fontSize: 16.0,
                                  letterSpacing: 0.0,
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .titleMedium
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .titleMedium
                                      .fontStyle,
                                ),
                            labelColor:
                                FlutterFlowTheme.of(context).primaryBackground,
                            unselectedLabelColor:
                                FlutterFlowTheme.of(context).primaryBackground,
                            backgroundColor:
                                FlutterFlowTheme.of(context).accent1,
                            unselectedBackgroundColor:
                                FlutterFlowTheme.of(context).fieldText,
                            borderColor: FlutterFlowTheme.of(context).primary,
                            unselectedBorderColor:
                                FlutterFlowTheme.of(context).alternate,
                            borderWidth: 0.0,
                            borderRadius: 8.0,
                            elevation: 0.0,
                            buttonMargin: const EdgeInsetsDirectional.fromSTEB(
                                8.0, 0.0, 8.0, 0.0),
                            tabs: const [
                              Tab(
                                text: 'Joueur',
                              ),
                              Tab(
                                text: 'Professionnel',
                              ),
                            ],
                            controller: _model.tabBarController,
                            onTap: (i) async {
                              safeSetState(() {
                                _showEmailForm = false;
                              });
                              [
                                () async {
                                  _model.userType = Roles.joueur;
                                },
                                () async {
                                  _model.userType = Roles.commercant;
                                }
                              ][i]();
                            },
                          ),
                        ),
                        SizedBox(
                          height: tabContentHeight,
                          child: TabBarView(
                            controller: _model.tabBarController,
                            children: [
                              Align(
                                alignment: const AlignmentDirectional(0.0, 0.0),
                                child: Container(
                                  height: double.infinity,
                                  decoration: const BoxDecoration(),
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(
                                        0.0, 16.0, 0.0, 16.0),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.max,
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (!_showEmailForm) ...[
                                            _buildPlayerEntryButtons(),
                                            Padding(
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                          0.0, 0.0, 0.0, 16.0),
                                              child: _buildPlayerTermsCheckbox(),
                                            ),
                                          ],
                                          if (_showEmailForm)
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsetsDirectional
                                                        .fromSTEB(
                                                            0.0, 0.0, 0.0, 16.0),
                                                child: TextButton.icon(
                                                  onPressed: _closePlayerEmailForm,
                                                  style: TextButton.styleFrom(
                                                    foregroundColor:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .primary,
                                                    backgroundColor:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .primary
                                                            .withValues(
                                                                alpha: 0.08),
                                                    padding:
                                                        const EdgeInsetsDirectional
                                                            .fromSTEB(
                                                                12.0,
                                                                8.0,
                                                                14.0,
                                                                8.0),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              999.0),
                                                    ),
                                                  ),
                                                  icon: Icon(
                                                    Icons.arrow_back_rounded,
                                                    size: 18.0,
                                                    color:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .primary,
                                                  ),
                                                  label: Text(
                                                    'Retour',
                                                    style: FlutterFlowTheme.of(
                                                            context)
                                                        .bodyMedium
                                                        .override(
                                                          font:
                                                              GoogleFonts.inter(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .fontStyle,
                                                          ),
                                                          color:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .primary,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodyMedium
                                                                  .fontStyle,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (_showEmailForm)
                                            Form(
                                            key: _model.formKey2,
                                            autovalidateMode:
                                                _playerAutovalidateMode,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.max,
                                              children: [
                                                Padding(
                                                  padding: const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                          0.0, 0.0, 0.0, 16.0),
                                                  child: SizedBox(
                                                    width: double.infinity,
                                                    child: TextFormField(
                                                      controller: _model
                                                          .emailAddressJoueurTextController,
                                                      focusNode: _model
                                                          .emailAddressJoueurFocusNode,
                                                      autofocus: false,
                                                      autocorrect: false,
                                                      enableSuggestions: false,
                                                      autofillHints: const [
                                                        AutofillHints.email
                                                      ],
                                                      obscureText: false,
                                                      decoration:
                                                          InputDecoration(
                                                        labelText: 'Mail',
                                                        labelStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .labelMedium
                                                                .override(
                                                                  font:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .labelMedium
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .labelMedium
                                                                        .fontStyle,
                                                                  ),
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .fieldText,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelMedium
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelMedium
                                                                      .fontStyle,
                                                                ),
                                                        enabledBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              const BorderSide(
                                                            color: Color(
                                                                0x00000000),
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        focusedBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              BorderSide(
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .primary,
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        errorBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              BorderSide(
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .error,
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        focusedErrorBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              BorderSide(
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .error,
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        filled: true,
                                                        fillColor:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .fieldBg,
                                                        contentPadding:
                                                            const EdgeInsets.all(
                                                                24.0),
                                                        suffixIcon: Icon(
                                                          Icons.mail_rounded,
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .primary,
                                                          size: 22.0,
                                                        ),
                                                      ),
                                                      style:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .bodyMedium
                                                              .override(
                                                                font:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyMedium
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyMedium
                                                                      .fontStyle,
                                                                ),
                                                                color: FlutterFlowTheme.of(
                                                                        context)
                                                                    .primaryText,
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .fontWeight,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .fontStyle,
                                                              ),
                                                      keyboardType:
                                                          TextInputType
                                                              .emailAddress,
                                                      validator: _model
                                                          .emailAddressJoueurTextControllerValidator
                                                          .asValidator(context),
                                                    ),
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                          0.0, 0.0, 0.0, 16.0),
                                                  child: SizedBox(
                                                    width: double.infinity,
                                                    child: TextFormField(
                                                      controller: _model
                                                          .passwordJoueurTextController,
                                                      focusNode: _model
                                                          .passwordJoueurFocusNode,
                                                      autofocus: false,
                                                      autocorrect: false,
                                                      enableSuggestions: false,
                                                      autofillHints: const [
                                                        AutofillHints.password
                                                      ],
                                                      obscureText: !_model
                                                          .passwordJoueurVisibility,
                                                      decoration:
                                                          InputDecoration(
                                                        labelText:
                                                            'Mot de passe',
                                                        labelStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .labelMedium
                                                                .override(
                                                                  font:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .labelMedium
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .labelMedium
                                                                        .fontStyle,
                                                                  ),
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .fieldText,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelMedium
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelMedium
                                                                      .fontStyle,
                                                                ),
                                                        enabledBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              const BorderSide(
                                                            color: Color(
                                                                0x00000000),
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        focusedBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              BorderSide(
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .primary,
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        errorBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              BorderSide(
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .error,
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        focusedErrorBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              BorderSide(
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .error,
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        filled: true,
                                                        fillColor:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .fieldBg,
                                                        contentPadding:
                                                            const EdgeInsets.all(
                                                                24.0),
                                                        suffixIcon: InkWell(
                                                          onTap: () =>
                                                              safeSetState(
                                                            () => _model
                                                                    .passwordJoueurVisibility =
                                                                !_model
                                                                    .passwordJoueurVisibility,
                                                          ),
                                                          focusNode: FocusNode(
                                                              skipTraversal:
                                                                  true),
                                                          child: Icon(
                                                            _model.passwordJoueurVisibility
                                                                ? Icons
                                                                    .visibility_outlined
                                                                : Icons
                                                                    .visibility_off_outlined,
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .primary,
                                                            size: 22.0,
                                                          ),
                                                        ),
                                                      ),
                                                      style:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .bodyMedium
                                                              .override(
                                                                font:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyMedium
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyMedium
                                                                      .fontStyle,
                                                                ),
                                                                color: FlutterFlowTheme.of(
                                                                        context)
                                                                    .primaryText,
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .fontWeight,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .fontStyle,
                                                              ),
                                                      validator: _model
                                                          .passwordJoueurTextControllerValidator
                                                          .asValidator(context),
                                                    ),
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                          0.0, 0.0, 0.0, 16.0),
                                                  child: SizedBox(
                                                    width: double.infinity,
                                                    child: TextFormField(
                                                      controller: _model
                                                          .passwordConfirmJoueurTextController,
                                                      focusNode: _model
                                                          .passwordConfirmJoueurFocusNode,
                                                      autofocus: false,
                                                      autocorrect: false,
                                                      enableSuggestions: false,
                                                      autofillHints: const [
                                                        AutofillHints.password
                                                      ],
                                                      obscureText: !_model
                                                          .passwordConfirmJoueurVisibility,
                                                      decoration:
                                                          InputDecoration(
                                                        labelText:
                                                            'Confirmer le mot de passe',
                                                        labelStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .labelMedium
                                                                .override(
                                                                  font:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .labelMedium
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .labelMedium
                                                                        .fontStyle,
                                                                  ),
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .fieldText,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelMedium
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelMedium
                                                                      .fontStyle,
                                                                ),
                                                        enabledBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              const BorderSide(
                                                            color: Color(
                                                                0x00000000),
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        focusedBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              BorderSide(
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .primary,
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        errorBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              BorderSide(
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .error,
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        focusedErrorBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              BorderSide(
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .error,
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        filled: true,
                                                        fillColor:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .fieldBg,
                                                        contentPadding:
                                                            const EdgeInsets.all(
                                                                24.0),
                                                        suffixIcon: InkWell(
                                                          onTap: () =>
                                                              safeSetState(
                                                            () => _model
                                                                    .passwordConfirmJoueurVisibility =
                                                                !_model
                                                                    .passwordConfirmJoueurVisibility,
                                                          ),
                                                          focusNode: FocusNode(
                                                              skipTraversal:
                                                                  true),
                                                          child: Icon(
                                                            _model.passwordConfirmJoueurVisibility
                                                                ? Icons
                                                                    .visibility_outlined
                                                                : Icons
                                                                    .visibility_off_outlined,
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .primary,
                                                            size: 22.0,
                                                          ),
                                                        ),
                                                      ),
                                                      style:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .bodyMedium
                                                              .override(
                                                                font:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyMedium
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyMedium
                                                                      .fontStyle,
                                                                ),
                                                                color: FlutterFlowTheme.of(
                                                                        context)
                                                                    .primaryText,
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .fontWeight,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .fontStyle,
                                                              ),
                                                      validator: _model
                                                          .passwordConfirmJoueurTextControllerValidator
                                                          .asValidator(context),
                                                    ),
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                          0.0, 0.0, 0.0, 16.0),
                                                  child: SizedBox(
                                                    width: double.infinity,
                                                    child: TextFormField(
                                                      controller: _model
                                                          .referralCodeJoueurTextController,
                                                      focusNode: _model
                                                          .referralCodeJoueurFocusNode,
                                                      autofocus: false,
                                                      autocorrect: false,
                                                      enableSuggestions: false,
                                                      textCapitalization:
                                                          TextCapitalization
                                                              .characters,
                                                      decoration:
                                                          InputDecoration(
                                                        labelText:
                                                            'Code de parrainage (facultatif)',
                                                        labelStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .labelMedium
                                                                .override(
                                                                  font:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .labelMedium
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .labelMedium
                                                                        .fontStyle,
                                                                  ),
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .fieldText,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelMedium
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelMedium
                                                                      .fontStyle,
                                                                ),
                                                        enabledBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              const BorderSide(
                                                            color: Color(
                                                                0x00000000),
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        focusedBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              BorderSide(
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .primary,
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        errorBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              BorderSide(
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .error,
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        focusedErrorBorder:
                                                            OutlineInputBorder(
                                                          borderSide:
                                                              BorderSide(
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .error,
                                                            width: 2.0,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        filled: true,
                                                        fillColor:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .fieldBg,
                                                        contentPadding:
                                                            const EdgeInsets.all(
                                                                24.0),
                                                      ),
                                                      style:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .bodyMedium
                                                              .override(
                                                                font:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyMedium
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyMedium
                                                                      .fontStyle,
                                                                ),
                                                                color: FlutterFlowTheme.of(
                                                                        context)
                                                                    .primaryText,
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .fontWeight,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .fontStyle,
                                                              ),
                                                      onChanged:
                                                          _persistReferralCodeInput,
                                                      validator: _model
                                                          .referralCodeJoueurTextControllerValidator
                                                          .asValidator(context),
                                                    ),
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                          0.0, 0.0, 0.0, 16.0),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.start,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Theme(
                                                        data: ThemeData(
                                                          checkboxTheme:
                                                              CheckboxThemeData(
                                                            visualDensity:
                                                                VisualDensity
                                                                    .compact,
                                                            materialTapTargetSize:
                                                                MaterialTapTargetSize
                                                                    .shrinkWrap,
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          4.0),
                                                            ),
                                                          ),
                                                          unselectedWidgetColor:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .primaryText,
                                                        ),
                                                        child: Checkbox(
                                                          value: _model
                                                                  .checkboxJoueurValue ??=
                                                              false,
                                                          onChanged:
                                                              (newValue) async {
                                                            safeSetState(() =>
                                                                _model.checkboxJoueurValue =
                                                                    newValue!);
                                                          },
                                                          side: BorderSide(
                                                            width: 2,
                                                            color: FlutterFlowTheme.of(
                                                                    context)
                                                                .primaryText,
                                                          ),
                                                          activeColor:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .primary,
                                                          checkColor:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .info,
                                                        ),
                                                      ),
                                                      Flexible(
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsetsDirectional
                                                                  .fromSTEB(
                                                                      0.0,
                                                                      5.0,
                                                                      0.0,
                                                                      0.0),
                                                          child: InkWell(
                                                            splashColor: Colors
                                                                .transparent,
                                                            focusColor: Colors
                                                                .transparent,
                                                            hoverColor: Colors
                                                                .transparent,
                                                            highlightColor:
                                                                Colors
                                                                    .transparent,
                                                            onTap:
                                                                _togglePlayerTermsAcceptance,
                                                            onLongPress:
                                                                () async {
                                                              context.pushNamed(
                                                                  LegalPageWidget
                                                                      .routeName);
                                                            },
                                                            child: Container(
                                                              decoration:
                                                                  const BoxDecoration(),
                                                              child: RichText(
                                                                textScaler: MediaQuery.of(
                                                                        context)
                                                                    .textScaler,
                                                                text: TextSpan(
                                                                  children: [
                                                                    TextSpan(
                                                                      text:
                                                                          'En cochant la case, vous acceptez nos',
                                                                      style: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodyMedium
                                                                          .override(
                                                                            font:
                                                                                GoogleFonts.inter(
                                                                              fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                            ),
                                                                            letterSpacing:
                                                                                0.0,
                                                                            fontWeight:
                                                                                FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                                                                            fontStyle:
                                                                                FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                          ),
                                                                    ),
                                                                    const TextSpan(
                                                                      text: ' ',
                                                                      style:
                                                                          TextStyle(),
                                                                    ),
                                                                    TextSpan(
                                                                      text:
                                                                          'conditions générales d\'utilisation',
                                                                      style: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodyMedium
                                                                          .override(
                                                                            font:
                                                                                GoogleFonts.inter(
                                                                              fontWeight: FontWeight.bold,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                            ),
                                                                            letterSpacing:
                                                                                0.0,
                                                                            fontWeight:
                                                                                FontWeight.bold,
                                                                            fontStyle:
                                                                                FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                          ),
                                                                    ),
                                                                    const TextSpan(
                                                                      text: ' ',
                                                                      style:
                                                                          TextStyle(),
                                                                    ),
                                                                    const TextSpan(
                                                                      text:
                                                                          'ainsi que notre',
                                                                      style:
                                                                          TextStyle(),
                                                                    ),
                                                                    const TextSpan(
                                                                      text: ' ',
                                                                      style:
                                                                          TextStyle(),
                                                                    ),
                                                                    TextSpan(
                                                                      text:
                                                                          'politique de confidentialité',
                                                                      style: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodyMedium
                                                                          .override(
                                                                            font:
                                                                                GoogleFonts.inter(
                                                                              fontWeight: FontWeight.bold,
                                                                              fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                            ),
                                                                            letterSpacing:
                                                                                0.0,
                                                                            fontWeight:
                                                                                FontWeight.bold,
                                                                            fontStyle:
                                                                                FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                                                                          ),
                                                                    )
                                                                  ],
                                                                  style: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyMedium
                                                                      .override(
                                                                        font: GoogleFonts
                                                                            .inter(
                                                                          fontWeight: FlutterFlowTheme.of(context)
                                                                              .bodyMedium
                                                                              .fontWeight,
                                                                          fontStyle: FlutterFlowTheme.of(context)
                                                                              .bodyMedium
                                                                              .fontStyle,
                                                                        ),
                                                                        letterSpacing:
                                                                            0.0,
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .bodyMedium
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .bodyMedium
                                                                            .fontStyle,
                                                                      ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Align(
                                                  alignment:
                                                      const AlignmentDirectional(
                                                          0.0, 0.0),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsetsDirectional
                                                            .fromSTEB(0.0, 0.0,
                                                                0.0, 16.0),
                                                    child: FFButtonWidget(
                                                      onPressed: () async {
                                                        if (_isSubmittingPlayerSignup) {
                                                          return;
                                                        }
                                                        FocusScope.of(context)
                                                            .unfocus();
                                                        FocusManager.instance
                                                            .primaryFocus
                                                            ?.unfocus();
                                                        if (_model
                                                                .checkboxJoueurValue !=
                                                            true) {
                                                          _showTermsRequiredMessage();
                                                          return;
                                                        }

                                                              if (!_validatePlayerSignupForm()) {
                                                                return;
                                                              }
                                                              final router =
                                                                  GoRouter.of(
                                                                      context);
                                                              router.prepareAuthEvent(
                                                                  true);
                                                              if (_model
                                                                      .passwordJoueurTextController
                                                                      .text !=
                                                                  _model
                                                                      .passwordConfirmJoueurTextController
                                                                      .text) {
                                                                ScaffoldMessenger.of(
                                                                        context)
                                                                    .showSnackBar(
                                                                  const SnackBar(
                                                                    content:
                                                                        Text(
                                                                      'Passwords don\'t match!',
                                                                    ),
                                                                  ),
                                                                );
                                                                return;
                                                              }
                                                              _persistReferralCodeInput(
                                                                _model
                                                                    .referralCodeJoueurTextController
                                                                    ?.text ??
                                                                    '',
                                                              );

                                                              safeSetState(() {
                                                                _isSubmittingPlayerSignup = true;
                                                              });
                                                              try {
                                                                debugPrint(
                                                                  '[ReferralDebug][Signup] beforeCreateAccount '
                                                                  'role=joueur pendingReferralCode='
                                                                  '${FFAppState().pendingReferralCode.isEmpty ? '<empty>' : FFAppState().pendingReferralCode}',
                                                                );
                                                                final user =
                                                                    await authManager
                                                                        .createAccountWithEmail(
                                                                  context,
                                                                  _model
                                                                      .emailAddressJoueurTextController
                                                                      .text
                                                                      .trim(),
                                                                  _model
                                                                      .passwordJoueurTextController
                                                                      .text,
                                                                );
                                                                if (user ==
                                                                    null) {
                                                                  return;
                                                                }
                                                                assert(() {
                                                                  debugPrint(
                                                                    '[ReferralDebug][Signup] afterCreateAccount role=joueur',
                                                                  );
                                                                  return true;
                                                                }());

                                                                await UsersRecord
                                                                    .collection
                                                                    .doc(user.uid)
                                                                    .set(
                                                                        createUsersRecordData(
                                                                      uid: user.uid,
                                                                      userRole: _model
                                                                          .userType,
                                                                    ),
                                                                        SetOptions(
                                                                            merge:
                                                                                true));

                                                                await ensureUserDocumentInitialized(
                                                                  FirebaseAuth
                                                                      .instance
                                                                      .currentUser!,
                                                                  roleHint: _model
                                                                      .userType,
                                                                  authProvider:
                                                                      'EMAIL',
                                                                  source:
                                                                      'email_signup_player',
                                                                );

                                                                final referralApplied =
                                                                    await _applyPendingReferralCodeIfNeeded();
                                                                if (!referralApplied &&
                                                                    (_lastReferralErrorMessage ??
                                                                            '')
                                                                        .isNotEmpty) {
                                                                  _showReferralErrorMessage(
                                                                    _lastReferralErrorMessage!,
                                                                  );
                                                                }

                                                                if (!mounted) {
                                                                  return;
                                                                }
                                                                if (router.shouldRedirect(true)) {
                                                                  return;
                                                                }
                                                                router.goNamed(
                                                                  InscriptionInformationsPageWidget
                                                                      .routeName,
                                                                );
                                                              } catch (error) {
                                                                debugPrint(
                                                                  'Player signup Firestore error: $error',
                                                                );
                                                                debugPrintStack();
                                                                if (mounted) {
                                                                  if (_isFirestoreNetworkError(
                                                                      error)) {
                                                                    _showFirestoreUnavailableMessage();
                                                                  } else {
                                                                    _showSignupFallbackErrorMessage();
                                                                  }
                                                                }
                                                              } finally {
                                                                if (mounted) {
                                                                  safeSetState(() {
                                                                    _isSubmittingPlayerSignup = false;
                                                                  });
                                                                }
                                                              }
                                                            },
                                                      text: 'Inscription',
                                                      options: FFButtonOptions(
                                                        width: double.infinity,
                                                        height: 52.0,
                                                        padding:
                                                            const EdgeInsetsDirectional
                                                                .fromSTEB(
                                                                    0.0,
                                                                    0.0,
                                                                    0.0,
                                                                    0.0),
                                                        iconPadding:
                                                            const EdgeInsetsDirectional
                                                                .fromSTEB(
                                                                    0.0,
                                                                    0.0,
                                                                    0.0,
                                                                    0.0),
                                                        color: FlutterFlowTheme
                                                                .of(context)
                                                            .primary,
                                                        textStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .titleSmall
                                                                .override(
                                                                  font: GoogleFonts
                                                                      .interTight(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleSmall
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleSmall
                                                                        .fontStyle,
                                                                  ),
                                                                  color: Colors
                                                                      .white,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleSmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleSmall
                                                                      .fontStyle,
                                                                ),
                                                        elevation: 0.0,
                                                        borderSide: const BorderSide(
                                                          color: Colors
                                                              .transparent,
                                                          width: 1.0,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12.0),
                                                        disabledColor:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .fieldText,
                                                      ),
                                                    ),
                                                  ),
                                                ),
	                                              ],
	                                            ),
	                                          ),
                                          if (_showEmailForm)
                                            Column(
                                            mainAxisSize: MainAxisSize.max,
                                            children: [
                                              InkWell(
                                                splashColor: Colors.transparent,
                                                focusColor: Colors.transparent,
                                                hoverColor: Colors.transparent,
	                                                highlightColor:
	                                                    Colors.transparent,
	                                                onTap: () async {
	                                                  context.goNamed(
	                                                      LoginPageWidget.routeName);
	                                                },
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Align(
                                                      alignment:
                                                          const AlignmentDirectional(
                                                              0.0, 0.0),
                                                      child: Text(
                                                        'Déjà un compte ? ',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .labelMedium
                                                                .override(
                                                                  font:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .labelMedium
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .labelMedium
                                                                        .fontStyle,
                                                                  ),
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelMedium
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelMedium
                                                                      .fontStyle,
                                                                ),
                                                      ),
                                                    ),
                                                    Align(
                                                      alignment:
                                                          const AlignmentDirectional(
                                                              0.0, 0.0),
                                                      child: Text(
                                                        ' Connexion',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .labelMedium
                                                                .override(
                                                                  font:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .labelMedium
                                                                        .fontStyle,
                                                                  ),
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .primary,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelMedium
                                                                      .fontStyle,
                                                                ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ).animateOnPageLoad(animationsMap[
                                        'columnOnPageLoadAnimation1']!),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    0.0, 16.0, 0.0, 16.0),
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.max,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Form(
                                        key: _model.formKey1,
                                        autovalidateMode:
                                            _merchantAutovalidateMode,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.max,
                                          children: [
                                            Padding(
                                              padding: const EdgeInsetsDirectional
                                                  .fromSTEB(
                                                      0.0, 0.0, 0.0, 16.0),
                                              child: SizedBox(
                                                width: double.infinity,
                                                child: TextFormField(
                                                  controller: _model
                                                      .emailAddressCommercantTextController,
                                                  focusNode: _model
                                                      .emailAddressCommercantFocusNode,
                                                  autofocus: false,
                                                  autocorrect: false,
                                                  enableSuggestions: false,
                                                  autofillHints: const [
                                                    AutofillHints.email
                                                  ],
                                                  obscureText: false,
                                                  decoration: InputDecoration(
                                                    labelText: 'Mail',
                                                    labelStyle: FlutterFlowTheme
                                                            .of(context)
                                                        .labelMedium
                                                        .override(
                                                          font:
                                                              GoogleFonts.inter(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelMedium
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelMedium
                                                                    .fontStyle,
                                                          ),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .fieldText,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .labelMedium
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .labelMedium
                                                                  .fontStyle,
                                                        ),
                                                    enabledBorder:
                                                        OutlineInputBorder(
                                                      borderSide: const BorderSide(
                                                        color:
                                                            Color(0x00000000),
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    focusedBorder:
                                                        OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .primary,
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    errorBorder:
                                                        OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .error,
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    focusedErrorBorder:
                                                        OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .error,
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    filled: true,
                                                    fillColor:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .fieldBg,
                                                    contentPadding:
                                                        const EdgeInsets.all(24.0),
                                                    suffixIcon: Icon(
                                                      Icons.mail_rounded,
                                                      color:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .primary,
                                                      size: 22.0,
                                                    ),
                                                  ),
                                                  style: FlutterFlowTheme.of(
                                                          context)
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
                                                                .primaryText,
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
                                                  keyboardType: TextInputType
                                                      .emailAddress,
                                                  validator: _model
                                                      .emailAddressCommercantTextControllerValidator
                                                      .asValidator(context),
                                                ),
                                              ),
                                            ),
                                            if (_showProfessionalCategoryField) Padding(
                                              padding: const EdgeInsetsDirectional
                                                  .fromSTEB(
                                                      0.0, 0.0, 0.0, 16.0),
                                              child: DropdownButtonFormField<
                                                  String>(
                                                initialValue: _model
                                                    .professionalCategoryValue,
                                                items: FFAppConstants.Category.map(
                                                  (label) => DropdownMenuItem(
                                                    value: label,
                                                    child: Text(label),
                                                  ),
                                                ).toList(),
                                                onChanged: (val) => safeSetState(
                                                    () => _model
                                                            .professionalCategoryValue =
                                                        val),
                                                decoration: InputDecoration(
                                                  labelStyle:
                                                      FlutterFlowTheme.of(context)
                                                          .labelMedium
                                                          .override(
                                                            font:
                                                                GoogleFonts.inter(
                                                              fontWeight:
                                                                  FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelMedium
                                                                      .fontWeight,
                                                              fontStyle:
                                                                  FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelMedium
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
                                                                    .labelMedium
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelMedium
                                                                    .fontStyle,
                                                          ),
                                                  enabledBorder:
                                                      OutlineInputBorder(
                                                    borderSide: const BorderSide(
                                                      color: Color(0x00000000),
                                                      width: 2.0,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(12.0),
                                                  ),
                                                  focusedBorder:
                                                      OutlineInputBorder(
                                                    borderSide: BorderSide(
                                                      color:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .primary,
                                                      width: 2.0,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(12.0),
                                                  ),
                                                  errorBorder:
                                                      OutlineInputBorder(
                                                    borderSide: BorderSide(
                                                      color:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .error,
                                                      width: 2.0,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(12.0),
                                                  ),
                                                  focusedErrorBorder:
                                                      OutlineInputBorder(
                                                    borderSide: BorderSide(
                                                      color:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .error,
                                                      width: 2.0,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(12.0),
                                                  ),
                                                  filled: true,
                                                  fillColor:
                                                      FlutterFlowTheme.of(context)
                                                          .fieldBg,
                                                  contentPadding:
                                                      const EdgeInsets.all(24.0),
                                                ),
                                                validator: (val) {
                                                  if (_model.userType ==
                                                          Roles.commercant &&
                                                      (val == null ||
                                                          val.isEmpty)) {
                                                    return 'Veuillez sélectionner une catégorie';
                                                  }
                                                  return null;
                                                },
                                              ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsetsDirectional
                                                  .fromSTEB(
                                                      0.0, 0.0, 0.0, 16.0),
                                              child: SizedBox(
                                                width: double.infinity,
                                                child: TextFormField(
                                                  controller: _model
                                                      .passwordCommercantTextController,
                                                  focusNode: _model
                                                      .passwordCommercantFocusNode,
                                                  autofocus: false,
                                                  autocorrect: false,
                                                  enableSuggestions: false,
                                                  autofillHints: const [
                                                    AutofillHints.password
                                                  ],
                                                  obscureText: !_model
                                                      .passwordCommercantVisibility,
                                                  decoration: InputDecoration(
                                                    labelText: 'Mot de passe',
                                                    labelStyle: FlutterFlowTheme
                                                            .of(context)
                                                        .labelMedium
                                                        .override(
                                                          font:
                                                              GoogleFonts.inter(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelMedium
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelMedium
                                                                    .fontStyle,
                                                          ),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .fieldText,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .labelMedium
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .labelMedium
                                                                  .fontStyle,
                                                        ),
                                                    enabledBorder:
                                                        OutlineInputBorder(
                                                      borderSide: const BorderSide(
                                                        color:
                                                            Color(0x00000000),
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    focusedBorder:
                                                        OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .primary,
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    errorBorder:
                                                        OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .error,
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    focusedErrorBorder:
                                                        OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .error,
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    filled: true,
                                                    fillColor:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .fieldBg,
                                                    contentPadding:
                                                        const EdgeInsets.all(24.0),
                                                    suffixIcon: InkWell(
                                                      onTap: () => safeSetState(
                                                        () => _model
                                                                .passwordCommercantVisibility =
                                                            !_model
                                                                .passwordCommercantVisibility,
                                                      ),
                                                      focusNode: FocusNode(
                                                          skipTraversal: true),
                                                      child: Icon(
                                                        _model.passwordCommercantVisibility
                                                            ? Icons
                                                                .visibility_outlined
                                                            : Icons
                                                                .visibility_off_outlined,
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .primary,
                                                        size: 22.0,
                                                      ),
                                                    ),
                                                  ),
                                                  style: FlutterFlowTheme.of(
                                                          context)
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
                                                                .primaryText,
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
                                                  validator: _model
                                                      .passwordCommercantTextControllerValidator
                                                      .asValidator(context),
                                                ),
                                              ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsetsDirectional
                                                  .fromSTEB(
                                                      0.0, 0.0, 0.0, 16.0),
                                              child: SizedBox(
                                                width: double.infinity,
                                                child: TextFormField(
                                                  controller: _model
                                                      .referralCodeCommercantTextController,
                                                  focusNode: _model
                                                      .referralCodeCommercantFocusNode,
                                                  autofocus: false,
                                                  autocorrect: false,
                                                  enableSuggestions: false,
                                                  textCapitalization:
                                                      TextCapitalization
                                                          .characters,
                                                  decoration: InputDecoration(
                                                    labelText:
                                                        'Code de parrainage (facultatif)',
                                                    labelStyle: FlutterFlowTheme
                                                            .of(context)
                                                        .labelMedium
                                                        .override(
                                                          font:
                                                              GoogleFonts.inter(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelMedium
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelMedium
                                                                    .fontStyle,
                                                          ),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .fieldText,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .labelMedium
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .labelMedium
                                                                  .fontStyle,
                                                        ),
                                                    enabledBorder:
                                                        OutlineInputBorder(
                                                      borderSide:
                                                          const BorderSide(
                                                        color:
                                                            Color(0x00000000),
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    focusedBorder:
                                                        OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .primary,
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    errorBorder:
                                                        OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .error,
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    focusedErrorBorder:
                                                        OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .error,
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    filled: true,
                                                    fillColor:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .fieldBg,
                                                    contentPadding:
                                                        const EdgeInsets.all(
                                                            24.0),
                                                  ),
                                                  style: FlutterFlowTheme.of(
                                                          context)
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
                                                                .primaryText,
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
                                                  onChanged:
                                                      _persistReferralCodeInput,
                                                  validator: _model
                                                      .referralCodeCommercantTextControllerValidator
                                                      .asValidator(context),
                                                ),
                                              ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsetsDirectional
                                                  .fromSTEB(
                                                      0.0, 0.0, 0.0, 16.0),
                                              child: SizedBox(
                                                width: double.infinity,
                                                child: TextFormField(
                                                  controller: _model
                                                      .passwordConfirmCommercantTextController,
                                                  focusNode: _model
                                                      .passwordConfirmCommercantFocusNode,
                                                  autofocus: false,
                                                  autocorrect: false,
                                                  enableSuggestions: false,
                                                  autofillHints: const [
                                                    AutofillHints.password
                                                  ],
                                                  obscureText: !_model
                                                      .passwordConfirmCommercantVisibility,
                                                  decoration: InputDecoration(
                                                    labelText:
                                                        'Confirmer le mot de passe',
                                                    labelStyle: FlutterFlowTheme
                                                            .of(context)
                                                        .labelMedium
                                                        .override(
                                                          font:
                                                              GoogleFonts.inter(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelMedium
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelMedium
                                                                    .fontStyle,
                                                          ),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .fieldText,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .labelMedium
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .labelMedium
                                                                  .fontStyle,
                                                        ),
                                                    enabledBorder:
                                                        OutlineInputBorder(
                                                      borderSide: const BorderSide(
                                                        color:
                                                            Color(0x00000000),
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    focusedBorder:
                                                        OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .primary,
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    errorBorder:
                                                        OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .error,
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    focusedErrorBorder:
                                                        OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .error,
                                                        width: 2.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12.0),
                                                    ),
                                                    filled: true,
                                                    fillColor:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .fieldBg,
                                                    contentPadding:
                                                        const EdgeInsets.all(24.0),
                                                    suffixIcon: InkWell(
                                                      onTap: () => safeSetState(
                                                        () => _model
                                                                .passwordConfirmCommercantVisibility =
                                                            !_model
                                                                .passwordConfirmCommercantVisibility,
                                                      ),
                                                      focusNode: FocusNode(
                                                          skipTraversal: true),
                                                      child: Icon(
                                                        _model.passwordConfirmCommercantVisibility
                                                            ? Icons
                                                                .visibility_outlined
                                                            : Icons
                                                                .visibility_off_outlined,
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .primary,
                                                        size: 22.0,
                                                      ),
                                                    ),
                                                  ),
                                                  style: FlutterFlowTheme.of(
                                                          context)
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
                                                                .primaryText,
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
                                                  validator: _model
                                                      .passwordConfirmCommercantTextControllerValidator
                                                      .asValidator(context),
                                                ),
                                              ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsetsDirectional
                                                  .fromSTEB(
                                                      0.0, 0.0, 0.0, 16.0),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.max,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Theme(
                                                    data: ThemeData(
                                                      checkboxTheme:
                                                          CheckboxThemeData(
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      4.0),
                                                        ),
                                                      ),
                                                      unselectedWidgetColor:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .primaryText,
                                                    ),
                                                    child: Checkbox(
                                                      value: _model
                                                              .checkboxCommercantValue ??=
                                                          false,
                                                      onChanged:
                                                          (newValue) async {
                                                        safeSetState(() => _model
                                                                .checkboxCommercantValue =
                                                            newValue!);
                                                      },
                                                      side: BorderSide(
                                                        width: 2,
                                                        color: FlutterFlowTheme
                                                                .of(context)
                                                            .primaryText,
                                                      ),
                                                      activeColor:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .primary,
                                                      checkColor:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .info,
                                                    ),
                                                  ),
                                                  Flexible(
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsetsDirectional
                                                              .fromSTEB(
                                                                  0.0,
                                                                  4.0,
                                                                  0.0,
                                                                  0.0),
                                                      child: InkWell(
                                                        splashColor:
                                                            Colors.transparent,
                                                        focusColor:
                                                            Colors.transparent,
                                                        hoverColor:
                                                            Colors.transparent,
                                                        highlightColor:
                                                            Colors.transparent,
                                                        onTap:
                                                            _toggleMerchantTermsAcceptance,
                                                        onLongPress: () async {
                                                          context.pushNamed(
                                                              LegalPageWidget
                                                                  .routeName);
                                                        },
                                                        child: Container(
                                                          decoration:
                                                              const BoxDecoration(),
                                                          child: RichText(
                                                            textScaler:
                                                                MediaQuery.of(
                                                                        context)
                                                                    .textScaler,
                                                            text: TextSpan(
                                                              children: [
                                                                TextSpan(
                                                                  text:
                                                                      'En cochant la case, vous acceptez nos',
                                                                  style: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyMedium
                                                                      .override(
                                                                        font: GoogleFonts
                                                                            .inter(
                                                                          fontWeight: FlutterFlowTheme.of(context)
                                                                              .bodyMedium
                                                                              .fontWeight,
                                                                          fontStyle: FlutterFlowTheme.of(context)
                                                                              .bodyMedium
                                                                              .fontStyle,
                                                                        ),
                                                                        letterSpacing:
                                                                            0.0,
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .bodyMedium
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .bodyMedium
                                                                            .fontStyle,
                                                                      ),
                                                                ),
                                                                const TextSpan(
                                                                  text: ' ',
                                                                  style:
                                                                      TextStyle(),
                                                                ),
                                                                TextSpan(
                                                                  text:
                                                                      'conditions générales d\'utilisation',
                                                                  style: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyMedium
                                                                      .override(
                                                                        font: GoogleFonts
                                                                            .inter(
                                                                          fontWeight:
                                                                              FontWeight.bold,
                                                                          fontStyle: FlutterFlowTheme.of(context)
                                                                              .bodyMedium
                                                                              .fontStyle,
                                                                        ),
                                                                        letterSpacing:
                                                                            0.0,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .bodyMedium
                                                                            .fontStyle,
                                                                      ),
                                                                ),
                                                                const TextSpan(
                                                                  text: ' ',
                                                                  style:
                                                                      TextStyle(),
                                                                ),
                                                                const TextSpan(
                                                                  text:
                                                                      'ainsi que notre',
                                                                  style:
                                                                      TextStyle(),
                                                                ),
                                                                const TextSpan(
                                                                  text: ' ',
                                                                  style:
                                                                      TextStyle(),
                                                                ),
                                                                TextSpan(
                                                                  text:
                                                                      'politique de confidentialité',
                                                                  style: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodyMedium
                                                                      .override(
                                                                        font: GoogleFonts
                                                                            .inter(
                                                                          fontWeight:
                                                                              FontWeight.bold,
                                                                          fontStyle: FlutterFlowTheme.of(context)
                                                                              .bodyMedium
                                                                              .fontStyle,
                                                                        ),
                                                                        letterSpacing:
                                                                            0.0,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .bodyMedium
                                                                            .fontStyle,
                                                                      ),
                                                                )
                                                              ],
                                                              style: FlutterFlowTheme
                                                                      .of(context)
                                                                  .bodyMedium
                                                                  .override(
                                                                    font: GoogleFonts
                                                                        .inter(
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodyMedium
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .bodyMedium
                                                                          .fontStyle,
                                                                    ),
                                                                    letterSpacing:
                                                                        0.0,
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodyMedium
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodyMedium
                                                                        .fontStyle,
                                                                  ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Align(
                                              alignment: const AlignmentDirectional(
                                                  0.0, 0.0),
                                              child: Padding(
                                                padding: const EdgeInsetsDirectional
                                                    .fromSTEB(
                                                        0.0, 0.0, 0.0, 16.0),
                                                child: FFButtonWidget(
                                                  onPressed: () async {
                                                          if (_isSubmittingMerchantSignup) {
                                                            return;
                                                          }
                                                          FocusScope.of(context)
                                                              .unfocus();
                                                          FocusManager.instance
                                                              .primaryFocus
                                                              ?.unfocus();
                                                          if (_model
                                                                  .checkboxCommercantValue !=
                                                              true) {
                                                            _showTermsRequiredMessage();
                                                            return;
                                                          }
                                                          if (!_validateMerchantSignupForm()) {
                                                            return;
                                                          }
                                                          final router =
                                                              GoRouter.of(
                                                                  context);
                                                          router.prepareAuthEvent(
                                                              true);
                                                          if (_model
                                                                  .passwordCommercantTextController
                                                                  .text !=
                                                              _model
                                                                  .passwordConfirmCommercantTextController
                                                                  .text) {
                                                            ScaffoldMessenger
                                                                    .of(context)
                                                                .showSnackBar(
                                                              const SnackBar(
                                                                content: Text(
                                                                  'Passwords don\'t match!',
                                                                ),
                                                              ),
                                                            );
                                                            return;
                                                          }
                                                          _persistReferralCodeInput(
                                                            _model
                                                                    .referralCodeCommercantTextController
                                                                    ?.text ??
                                                                '',
                                                          );

                                                          safeSetState(() {
                                                            _isSubmittingMerchantSignup = true;
                                                          });
                                                          try {
                                                            debugPrint(
                                                              '[ReferralDebug][Signup] beforeCreateAccount '
                                                              'role=commercant pendingReferralCode='
                                                              '${FFAppState().pendingReferralCode.isEmpty ? '<empty>' : FFAppState().pendingReferralCode}',
                                                            );
                                                            final user =
                                                                await authManager
                                                                    .createAccountWithEmail(
                                                              context,
                                                              _model
                                                                  .emailAddressCommercantTextController
                                                                  .text
                                                                  .trim(),
                                                              _model
                                                                  .passwordCommercantTextController
                                                                  .text,
                                                            );
                                                            if (user == null) {
                                                              return;
                                                            }
                                                            assert(() {
                                                              debugPrint(
                                                                '[ReferralDebug][Signup] afterCreateAccount role=commercant',
                                                              );
                                                              return true;
                                                            }());

                                                            await UsersRecord
                                                                .collection
                                                                .doc(user.uid)
                                                                .set(
                                                                    createUsersRecordData(
                                                                  uid: user.uid,
                                                                  userRole: _model
                                                                      .userType,
                                                                  professionalCategory:
                                                                      _model
                                                                          .professionalCategoryValue,
                                                                ),
                                                                    SetOptions(
                                                                        merge:
                                                                            true));

                                                            await ensureUserDocumentInitialized(
                                                              FirebaseAuth
                                                                  .instance
                                                                  .currentUser!,
                                                              roleHint: _model
                                                                  .userType,
                                                              authProvider:
                                                                  'EMAIL',
                                                              source:
                                                                  'email_signup_merchant',
                                                            );

                                                            final referralApplied =
                                                                await _applyPendingReferralCodeIfNeeded();
                                                            if (!referralApplied &&
                                                                (_lastReferralErrorMessage ??
                                                                        '')
                                                                    .isNotEmpty) {
                                                              _showReferralErrorMessage(
                                                                _lastReferralErrorMessage!,
                                                              );
                                                            }

                                                            if (!mounted) {
                                                              return;
                                                            }
                                                            if (router.shouldRedirect(true)) {
                                                              return;
                                                            }
                                                            router.goNamed(
                                                              InscriptionInformationsPageWidget
                                                                  .routeName,
                                                            );
                                                          } catch (error) {
                                                            debugPrint(
                                                              'Merchant signup Firestore error: $error',
                                                            );
                                                            debugPrintStack();
                                                            if (mounted) {
                                                              if (_isFirestoreNetworkError(
                                                                  error)) {
                                                                _showFirestoreUnavailableMessage();
                                                              } else {
                                                                _showSignupFallbackErrorMessage();
                                                              }
                                                            }
                                                          } finally {
                                                            if (mounted) {
                                                              safeSetState(() {
                                                                _isSubmittingMerchantSignup = false;
                                                              });
                                                            }
                                                          }
                                                        },
                                                  text: 'Inscription',
                                                  options: FFButtonOptions(
                                                    width: double.infinity,
                                                    height: 52.0,
                                                    padding:
                                                        const EdgeInsetsDirectional
                                                            .fromSTEB(0.0, 0.0,
                                                                0.0, 0.0),
                                                    iconPadding:
                                                        const EdgeInsetsDirectional
                                                            .fromSTEB(0.0, 0.0,
                                                                0.0, 0.0),
                                                    color: FlutterFlowTheme.of(
                                                            context)
                                                        .primary,
                                                    textStyle: FlutterFlowTheme
                                                            .of(context)
                                                        .titleSmall
                                                        .override(
                                                          font: GoogleFonts
                                                              .interTight(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleSmall
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleSmall
                                                                    .fontStyle,
                                                          ),
                                                          color: Colors.white,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .titleSmall
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .titleSmall
                                                                  .fontStyle,
                                                        ),
                                                    elevation: 0.0,
                                                    borderSide: const BorderSide(
                                                      color: Colors.transparent,
                                                      width: 1.0,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12.0),
                                                    disabledColor:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .fieldText,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        mainAxisSize: MainAxisSize.max,
                                        children: [
                                          InkWell(
                                            splashColor: Colors.transparent,
                                            focusColor: Colors.transparent,
	                                            hoverColor: Colors.transparent,
	                                            highlightColor: Colors.transparent,
	                                            onTap: () async {
	                                              context.goNamed(
	                                                  LoginPageWidget.routeName);
	                                            },
                                            child: Row(
                                              mainAxisSize: MainAxisSize.max,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Align(
                                                  alignment:
                                                      const AlignmentDirectional(
                                                          0.0, 0.0),
                                                  child: Text(
                                                    'Déjà un compte ? ',
                                                    textAlign: TextAlign.center,
                                                    style: FlutterFlowTheme.of(
                                                            context)
                                                        .labelMedium
                                                        .override(
                                                          font:
                                                              GoogleFonts.inter(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelMedium
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelMedium
                                                                    .fontStyle,
                                                          ),
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .labelMedium
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .labelMedium
                                                                  .fontStyle,
                                                        ),
                                                  ),
                                                ),
                                                Align(
                                                  alignment:
                                                      const AlignmentDirectional(
                                                          0.0, 0.0),
                                                  child: Text(
                                                    ' Connexion',
                                                    textAlign: TextAlign.center,
                                                    style: FlutterFlowTheme.of(
                                                            context)
                                                        .labelMedium
                                                        .override(
                                                          font:
                                                              GoogleFonts.inter(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelMedium
                                                                    .fontStyle,
                                                          ),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .primary,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .labelMedium
                                                                  .fontStyle,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ).animateOnPageLoad(animationsMap[
                                    'columnOnPageLoadAnimation2']!),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _initialReferralCodeValue => FFAppState().pendingReferralCode;

  String _normalizedReferralCode(String? value) => value?.trim().toUpperCase() ?? '';

  void _persistReferralCodeInput(String value) {
    final normalizedValue = _normalizedReferralCode(value);
    FFAppState().update(() {
      if (normalizedValue.isEmpty) {
        FFAppState().clearPendingReferralCode();
      } else {
        FFAppState().pendingReferralCode = normalizedValue;
      }
    });
  }

  String? _errorMessageForReferralFailure(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'not-found':
        return 'Ce code de parrainage est introuvable.';
      case 'failed-precondition':
        return 'Vous ne pouvez pas utiliser votre propre code de parrainage.';
      case 'already-exists':
        return 'Ce parrainage a déjà été utilisé pour ce compte.';
      case 'invalid-argument':
        return 'Veuillez saisir un code de parrainage valide.';
      default:
        return 'Le code de parrainage n’a pas pu être appliqué pour le moment.';
    }
  }

  void _showReferralErrorMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  Future<bool> _applyPendingReferralCodeIfNeeded() async {
    final pendingReferralCode = FFAppState().pendingReferralCode.trim();
    if (pendingReferralCode.isEmpty) {
      _lastReferralErrorMessage = null;
      return true;
    }

    final currentUid = currentUserUid;
    final referralGuardKey = '$currentUid::$pendingReferralCode';
    if (_isApplyingPendingReferralCode ||
        _lastAppliedReferralGuardKey == referralGuardKey) {
      _lastReferralErrorMessage = null;
      return true;
    }

    _isApplyingPendingReferralCode = true;
    _lastReferralErrorMessage = null;
    _lastAppliedReferralGuardKey = referralGuardKey;
    try {
      await _sharePromoService.registerReferralAcceptance(
        inviteCode: pendingReferralCode,
      );
      FFAppState().update(() {
        FFAppState().clearPendingReferralCode();
      });
      return true;
    } on FirebaseFunctionsException catch (error) {
      _lastReferralErrorMessage = _errorMessageForReferralFailure(error);
      const terminalErrorCodes = <String>{
        'invalid-argument',
        'not-found',
        'already-exists',
        'failed-precondition',
      };
      if (!terminalErrorCodes.contains(error.code)) {
        debugPrint('Referral acceptance error: ${error.code}');
      }
      return false;
    } catch (error) {
      _lastReferralErrorMessage =
          'Le code de parrainage n’a pas pu être appliqué pour le moment.';
      debugPrint('Referral acceptance unexpected error: $error');
      return false;
    } finally {
      _isApplyingPendingReferralCode = false;
    }
  }
}

