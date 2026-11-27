import '/auth/firebase_auth/account_routing.dart';
import '/auth/firebase_auth/auth_util.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/utils/merchant_cgv.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'merchant_cgv_page_model.dart';
export 'merchant_cgv_page_model.dart';

/// Écran « Conditions générales de vente » : affiché une seule fois à un
/// commerçant déjà inscrit qui n'a pas encore accepté les CGV (voir
/// applyMerchantCgvRequirement). Il n'accède pas à son espace tant que la
/// case n'est pas cochée et l'acceptation enregistrée par le serveur.
class MerchantCgvPageWidget extends StatefulWidget {
  const MerchantCgvPageWidget({
    super.key,
    this.recordAcceptance,
    this.afterAccepted,
    this.openUrl,
  });

  static String routeName = 'MerchantCgvPage';
  static String routePath = 'merchantCgvPage';

  /// Injectables pour les tests ; par défaut : callable serveur, puis
  /// rafraîchissement de la fiche et routage habituel.
  final Future<void> Function()? recordAcceptance;
  final Future<void> Function(BuildContext context)? afterAccepted;
  final MerchantCgvUrlOpener? openUrl;

  @override
  State<MerchantCgvPageWidget> createState() => _MerchantCgvPageWidgetState();
}

class _MerchantCgvPageWidgetState extends State<MerchantCgvPageWidget> {
  late MerchantCgvPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => MerchantCgvPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'MerchantCgvPage'});
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  Future<void> _defaultRecordAcceptance() =>
      recordMerchantCgvAcceptance(MerchantCgvSource.login);

  Future<void> _defaultAfterAccepted(BuildContext context) async {
    await refreshCurrentUserDocument();
    final resolution = await resolveAuthenticatedHome(
      source: 'merchant_cgv',
      preferServer: true,
    );
    if (resolution.target == AuthenticatedHomeTarget.merchantCgvRequired) {
      // Fiche relue sans l'acceptation : ne pas boucler sur cet écran.
      throw StateError('cgv_not_confirmed');
    }
    if (!context.mounted) return;
    context.goNamedAuth(resolution.routeName, context.mounted,
        ignoreRedirect: true);
  }

  Future<void> _continue() async {
    if (!_model.cgvAccepted || _model.isSubmitting) return;
    safeSetState(() {
      _model.isSubmitting = true;
      _model.errorMessage = null;
    });
    try {
      await (widget.recordAcceptance ?? _defaultRecordAcceptance)();
      if (!mounted) return;
      await (widget.afterAccepted ?? _defaultAfterAccepted)(context);
    } catch (error) {
      debugPrint('[MerchantCgv][Login] failed: ${error.runtimeType}');
      if (mounted) {
        safeSetState(() {
          _model.errorMessage =
              'Votre acceptation n\'a pas pu être enregistrée. Vérifiez votre connexion puis réessayez.';
        });
      }
    } finally {
      if (mounted) {
        safeSetState(() => _model.isSubmitting = false);
      }
    }
  }

  Future<void> _signOut() async {
    GoRouter.of(context).clearRedirectLocation();
    FFAppState().update(() => FFAppState().isLoggingOut = true);
    context.go('/loginPage');
    await authManager.signOut();
    FFAppState().update(() => FFAppState().isLoggingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final bodyStyle = theme.bodyMedium.override(
      font: GoogleFonts.inter(
        fontWeight: theme.bodyMedium.fontWeight,
        fontStyle: theme.bodyMedium.fontStyle,
      ),
      letterSpacing: 0.0,
    );
    final canContinue = _model.cgvAccepted && !_model.isSubmitting;
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: theme.primaryBackground,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                decoration: BoxDecoration(
                  color: theme.secondaryBackground,
                  borderRadius: BorderRadius.circular(16.0),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Conditions générales de vente',
                      textAlign: TextAlign.center,
                      style: theme.headlineSmall.override(
                        font: GoogleFonts.interTight(
                          fontWeight: FontWeight.w600,
                          fontStyle: theme.headlineSmall.fontStyle,
                        ),
                        letterSpacing: 0.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Pour accéder à votre espace commerçant, merci de lire et d\'accepter les conditions générales de vente PROXIPLAY.',
                      textAlign: TextAlign.center,
                      style: bodyStyle,
                    ),
                    const SizedBox(height: 20),
                    MerchantCgvCheckbox(
                      value: _model.cgvAccepted,
                      enabled: !_model.isSubmitting,
                      onChanged: (value) =>
                          safeSetState(() => _model.cgvAccepted = value),
                      textStyle: bodyStyle,
                      accentColor: theme.primary,
                      openUrl: widget.openUrl,
                    ),
                    if (_model.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _model.errorMessage!,
                        key: const ValueKey('merchant_cgv_error'),
                        style: bodyStyle.copyWith(color: theme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FFButtonWidget(
                      key: const ValueKey('merchant_cgv_continue'),
                      onPressed: canContinue ? _continue : null,
                      text: _model.isSubmitting
                          ? 'Enregistrement…'
                          : (_model.errorMessage != null
                              ? 'Réessayer'
                              : 'Continuer'),
                      options: FFButtonOptions(
                        height: 48.0,
                        color: theme.primary,
                        textStyle: theme.titleSmall.override(
                          font: GoogleFonts.interTight(
                            fontWeight: theme.titleSmall.fontWeight,
                            fontStyle: theme.titleSmall.fontStyle,
                          ),
                          color: Colors.white,
                          letterSpacing: 0.0,
                        ),
                        disabledColor: theme.alternate,
                        disabledTextColor: theme.secondaryText,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _model.isSubmitting ? null : _signOut,
                      child: Text('Se déconnecter', style: bodyStyle),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
