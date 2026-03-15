import '/backend/backend.dart';
import '/auth/firebase_auth/auth_util.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webviewx_plus/webviewx_plus.dart';
import 'profil_joueur_page_model.dart';
export 'profil_joueur_page_model.dart';

class ProfilJoueurPageWidget extends StatefulWidget {
  const ProfilJoueurPageWidget({super.key});

  static String routeName = 'ProfilJoueurPage';
  static String routePath = 'profilJoueurPage';

  @override
  State<ProfilJoueurPageWidget> createState() => _ProfilJoueurPageWidgetState();
}

class _ProfilJoueurPageWidgetState extends State<ProfilJoueurPageWidget> {
  static const Color _navy = Color(0xFF2E2A68);
  static const Color _navyTint = Color(0xFFF4F5FB);
  static const Color _raspberry = Color(0xFFA0134D);
  static const Color _raspberryTint = Color(0xFFFFF1F6);

  late ProfilJoueurPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  Future<int> _loadLotsToClaimCount(List<MyLotsRecord> myLots) async {
    final recordsWithPrizeRef =
        myLots.where((record) => record.prizeId != null).toList();
    if (recordsWithPrizeRef.isEmpty) {
      return 0;
    }

    final snapshots = await Future.wait(
      recordsWithPrizeRef.map((record) => record.prizeId!.get()),
    );

    var lotsToClaim = 0;
    for (final snapshot in snapshots) {
      if (!snapshot.exists) {
        continue;
      }
      final prize = PrizesRecord.fromSnapshot(snapshot);
      if (!prize.claimed) {
        lotsToClaim += 1;
      }
    }

    return lotsToClaim;
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(2.0, 0.0, 0.0, 0.0),
      child: Text(
        title,
        style: FlutterFlowTheme.of(context).labelLarge.override(
              font: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontStyle: FlutterFlowTheme.of(context).labelLarge.fontStyle,
              ),
              color: _navy.withValues(alpha: 0.72),
              fontSize: 14.0,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required String title,
    required Future<void> Function() onTap,
    String? trailingLabel,
    bool isPrimary = false,
    bool isDanger = false,
    bool compactLabel = false,
  }) {
    final iconTint = isDanger
        ? _raspberryTint
        : (isPrimary ? _raspberryTint : _navyTint);
    final iconColor = isDanger
        ? _raspberry
        : (isPrimary ? _raspberry : _navy);
    final titleColor = isDanger ? _raspberry : _navy;

    return InkWell(
      splashColor: Colors.transparent,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: () async {
        await onTap();
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(18.0),
          border: Border.all(
            color: isPrimary
                ? _raspberry.withValues(alpha: 0.22)
                : _navy.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: (isPrimary ? _raspberry : Colors.black)
                  .withValues(alpha: isPrimary ? 0.08 : 0.035),
              blurRadius: isPrimary ? 22.0 : 16.0,
              offset: const Offset(0.0, 8.0),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16.0, 16.0, 16.0, 16.0),
          child: Row(
            children: [
              Container(
                width: 36.0,
                height: 36.0,
                decoration: BoxDecoration(
                  color: iconTint,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 18.0,
                ),
              ),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsetsDirectional.fromSTEB(14.0, 0.0, 12.0, 0.0),
                  child: Text(
                    title,
                    style: FlutterFlowTheme.of(context).bodyLarge.override(
                          font: GoogleFonts.inter(
                            fontWeight: isPrimary ? FontWeight.w700 : FontWeight.w600,
                            fontStyle:
                                FlutterFlowTheme.of(context).bodyLarge.fontStyle,
                          ),
                          color: titleColor,
                          fontSize: compactLabel ? 15.0 : 16.0,
                          letterSpacing: 0.0,
                          fontWeight:
                              isPrimary ? FontWeight.w700 : FontWeight.w600,
                        ),
                  ),
                ),
              ),
              if (trailingLabel != null)
                Container(
                  decoration: BoxDecoration(
                    color: _raspberry,
                    borderRadius: BorderRadius.circular(999.0),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        10.0, 6.0, 10.0, 6.0),
                    child: Text(
                      trailingLabel,
                      style: FlutterFlowTheme.of(context).labelSmall.override(
                            font: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontStyle:
                                  FlutterFlowTheme.of(context).labelSmall.fontStyle,
                            ),
                            color: Colors.white,
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => ProfilJoueurPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'ProfilJoueurPage'});
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
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
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            elevation: 0.0,
            title: const SizedBox.shrink(),
            flexibleSpace: FlexibleSpaceBar(
              background: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Image.asset(
                  'assets/images/Background.png',
                  fit: BoxFit.cover,
                  alignment: const Alignment(1.0, -1.0),
                ),
              ),
            ),
            centerTitle: true,
          ),
          body: SafeArea(
            top: true,
            child: Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  fit: BoxFit.cover,
                  image: Image.asset(
                    'assets/images/Background.png',
                  ).image,
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          20.0, 24.0, 20.0, 0.0),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color:
                                    FlutterFlowTheme.of(context).secondaryBackground,
                                borderRadius: BorderRadius.circular(24.0),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 20.0,
                                    offset: const Offset(0.0, 10.0),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    20.0, 24.0, 20.0, 24.0),
                                child: AuthUserStreamWidget(
                                  builder: (context) {
                                    final firstName = valueOrDefault(
                                        currentUserDocument?.firstName, '');
                                    final lastName = valueOrDefault(
                                        currentUserDocument?.lastName, '');
                                    final displayName = firstName.trim().isNotEmpty
                                        ? firstName.trim()
                                        : '$firstName $lastName'.trim();

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Bonjour ${displayName.isNotEmpty ? displayName : 'joueur'}',
                                          style: FlutterFlowTheme.of(context)
                                              .headlineMedium
                                              .override(
                                                font: GoogleFonts.interTight(
                                                  fontWeight: FontWeight.w700,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(context)
                                                          .headlineMedium
                                                          .fontStyle,
                                                ),
                                                color: _navy,
                                                letterSpacing: 0.0,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        Text(
                                          'Votre espace personnel ProxiPlay',
                                          style: FlutterFlowTheme.of(context)
                                              .bodyMedium
                                              .override(
                                                font: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w500,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(context)
                                                          .bodyMedium
                                                          .fontStyle,
                                                ),
                                                color: _navy.withValues(alpha: 0.65),
                                                letterSpacing: 0.0,
                                              ),
                                        ),
                                      ].divide(const SizedBox(height: 12.0)),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 24.0),
                            _buildSectionTitle('MON COMPTE'),
                            const SizedBox(height: 12.0),
                            StreamBuilder<List<MyLotsRecord>>(
                              stream: currentUserReference == null
                                  ? const Stream<List<MyLotsRecord>>.empty()
                                  : queryMyLotsRecord(parent: currentUserReference),
                              builder: (context, snapshot) {
                                final myLots = snapshot.data ?? const <MyLotsRecord>[];
                                return FutureBuilder<int>(
                                  key: ValueKey(
                                    myLots
                                        .map((lot) => lot.reference.path)
                                        .join('|'),
                                  ),
                                  future: _loadLotsToClaimCount(myLots),
                                  builder: (context, countSnapshot) {
                                    final lotsToClaim = countSnapshot.data ?? 0;
                                    final lotsLabel = lotsToClaim <= 1
                                        ? '$lotsToClaim lot \u00e0 r\u00e9cup\u00e9rer'
                                        : '$lotsToClaim lots \u00e0 r\u00e9cup\u00e9rer';
                                    return _buildMenuCard(
                                      icon: Icons.card_giftcard_rounded,
                                      title: lotsLabel,
                                      isPrimary: true,
                                      onTap: () async {
                                        context.pushNamed(
                                            LotsJoueurPageWidget.routeName);
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: 12.0),
                            _buildMenuCard(
                              icon: Icons.person_outline_rounded,
                              title: 'Mes informations',
                              onTap: () async {
                                context.pushNamed(EditJoueurPageWidget.routeName);
                              },
                            ),
                            const SizedBox(height: 12.0),
                            _buildMenuCard(
                              icon: Icons.logout_rounded,
                              title: 'Se d\u00e9connecter',
                              onTap: () async {
                                GoRouter.of(context).clearRedirectLocation();
                                FFAppState()
                                    .update(() => FFAppState().isLoggingOut = true);
                                context.go('/loginPage');
                                await authManager.signOut();
                                FFAppState().update(
                                    () => FFAppState().isLoggingOut = false);
                              },
                            ),
                            const SizedBox(height: 12.0),
                            _buildMenuCard(
                              icon: Icons.delete_forever_rounded,
                              title: 'Supprimer mon compte',
                              compactLabel: true,
                              isDanger: true,
                              onTap: () async {
                                final confirmDialogResponse =
                                    await showDialog<bool>(
                                          context: context,
                                          builder: (alertDialogContext) {
                                            return WebViewAware(
                                              child: AlertDialog(
                                                title: const Text(
                                                    'Suppression du compte'),
                                                content: const Text(
                                                    '\u00cates-vous s\u00fbr de vouloir supprimer votre compte ?'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(
                                                        alertDialogContext, false),
                                                    child: const Text('Annuler'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(
                                                        alertDialogContext, true),
                                                    child: const Text('Confirmer'),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ) ??
                                        false;
                                if (!context.mounted) return;
                                if (confirmDialogResponse) {
                                  await authManager.deleteUser(context);
                                  if (!context.mounted) return;
                                  context.pushNamed(LoginPageWidget.routeName);
                                }
                              },
                            ),
                            const SizedBox(height: 24.0),
                            _buildSectionTitle('PROXIPLAY'),
                            const SizedBox(height: 12.0),
                            _buildMenuCard(
                              icon: Icons.mail_outline_rounded,
                              title: 'Nous contacter',
                              onTap: () async {
                                context.pushNamed(ContactPageWidget.routeName);
                              },
                            ),
                            const SizedBox(height: 12.0),
                            _buildMenuCard(
                              icon: Icons.folder_outlined,
                              title: 'Mentions l\u00e9gales',
                              onTap: () async {
                                context.pushNamed(LegalPageWidget.routeName);
                              },
                            ),
                            const SizedBox(height: 24.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  wrapWithModel(
                    model: _model.customNavBarJoueurModel,
                    updateCallback: () => safeSetState(() {}),
                    child: const CustomNavBarJoueurWidget(
                      indexActive: 4,
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
