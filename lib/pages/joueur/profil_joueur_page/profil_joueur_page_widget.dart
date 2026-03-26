import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
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
  late ProfilJoueurPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

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

  Future<int> _countUnclaimedLots(List<MyLotsRecord> myLots) async {
    final recordsWithPrizeRef =
        myLots.where((record) => record.prizeId != null).toList();
    if (recordsWithPrizeRef.isEmpty) {
      return 0;
    }

    final prizeSnaps = await Future.wait(
      recordsWithPrizeRef.map((record) => record.prizeId!.get()),
    );

    var unclaimedLots = 0;
    for (final prizeSnap in prizeSnaps) {
      if (!prizeSnap.exists) {
        continue;
      }
      final prize = PrizesRecord.fromSnapshot(prizeSnap);
      if (!prize.claimed) {
        unclaimedLots++;
      }
    }
    return unclaimedLots;
  }

  Future<void> _handleDeleteAccountTap() async {
    final confirmDialogResponse = await showDialog<bool>(
          context: context,
          builder: (alertDialogContext) {
            return WebViewAware(
              child: AlertDialog(
                title: const Text('Suppression du compte'),
                content: const Text(
                    'Êtes-vous sûr de vouloir supprimer votre compte ?'),
                actions: [
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(alertDialogContext, false),
                    child: const Text('Annuler'),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(alertDialogContext, true),
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
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 6.0),
      child: Text(
        title,
        style: FlutterFlowTheme.of(context).labelLarge.override(
              font: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
              ),
              fontSize: 18.0,
              color: const Color(0xFF4B5078),
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required Widget title,
    required VoidCallback onTap,
    Color iconColor = const Color(0xFF2D2A72),
    Color arrowColor = const Color(0xFF2D2A72),
    Color circleColor = const Color(0xFFF5F6FF),
    Color backgroundColor = Colors.white,
    BoxBorder? border,
  }) {
    return InkWell(
      splashColor: const Color(0x142D2A72),
      focusColor: const Color(0x0F2D2A72),
      hoverColor: const Color(0x082D2A72),
      highlightColor: const Color(0x0A2D2A72),
      borderRadius: BorderRadius.circular(24.0),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 92.0,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(24.0),
          border: border,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 16.0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17.0),
          child: Row(
            children: [
              Container(
                width: 54.0,
                height: 54.0,
                decoration: BoxDecoration(
                  color: circleColor,
                  borderRadius: BorderRadius.circular(18.0),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 25.0,
                ),
              ),
              const SizedBox(width: 16.0),
              Expanded(child: title),
              Icon(
                Icons.arrow_forward_ios,
                color: arrowColor,
                size: 17.0,
              ),
            ],
          ),
        ),
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
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
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
                      padding: const EdgeInsets.fromLTRB(20.0, 18.0, 20.0, 0.0),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.96),
                                borderRadius: BorderRadius.circular(28.0),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.055),
                                    blurRadius: 18.0,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 26.0, vertical: 26.0),
                                child: AuthUserStreamWidget(
                                  builder: (context) {
                                    final firstName = valueOrDefault(
                                      currentUserDocument?.firstName,
                                      '',
                                    );
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          firstName.isNotEmpty
                                              ? 'Bonjour $firstName'
                                              : 'Bonjour',
                                          style: FlutterFlowTheme.of(context)
                                              .headlineSmall
                                              .override(
                                                font: GoogleFonts.interTight(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                                color:
                                                    const Color(0xFF2D2A72),
                                                letterSpacing: 0.0,
                                                fontSize: 33.0,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        const SizedBox(height: 10.0),
                                        Text(
                                          'Votre espace personnel ProxiPlay',
                                          style: FlutterFlowTheme.of(context)
                                              .bodyLarge
                                              .override(
                                                font: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w400,
                                                ),
                                                color:
                                                    const Color(0xFF6B6B8B),
                                                fontSize: 15.0,
                                                letterSpacing: 0.0,
                                              ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 28.0),
                            _buildSectionTitle(context, 'MON COMPTE'),
                            const SizedBox(height: 14.0),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14.0),
                              child: StreamBuilder<List<MyLotsRecord>>(
                                stream: currentUserReference == null
                                    ? const Stream<List<MyLotsRecord>>.empty()
                                    : queryMyLotsRecord(
                                        parent: currentUserReference,
                                      ),
                                builder: (context, snapshot) {
                                  return FutureBuilder<int>(
                                    future: snapshot.hasData
                                        ? _countUnclaimedLots(
                                            snapshot.data ??
                                                const <MyLotsRecord>[])
                                        : Future<int>.value(0),
                                    builder: (context, countSnapshot) {
                                      final count = countSnapshot.data ?? 0;
                                      final label =
                                          '$count lot${count > 1 ? 's' : ''} à récupérer';
                                      return _buildMenuCard(
                                        context,
                                        icon: Icons.card_giftcard_rounded,
                                        onTap: () {
                                          context.pushNamed(
                                              LotsJoueurPageWidget.routeName);
                                        },
                                        backgroundColor:
                                            const Color(0xFFFDF5F8),
                                        circleColor: const Color(0xFFF9E4EC),
                                        iconColor: const Color(0xFFA0134D),
                                        arrowColor: const Color(0xFFA0134D),
                                        border: Border.all(
                                          color: const Color(0xFFE7B8CB),
                                          width: 1.2,
                                        ),
                                        title: Text(
                                          label,
                                          style: FlutterFlowTheme.of(context)
                                              .bodyLarge
                                              .override(
                                                font: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                fontSize: 16.0,
                                                color:
                                                    const Color(0xFF2D2A72),
                                                letterSpacing: 0.0,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14.0),
                              child: _buildMenuCard(
                                context,
                                icon: Icons.person_outline_rounded,
                                onTap: () {
                                  context.pushNamed(
                                      EditJoueurPageWidget.routeName);
                                },
                                title: Text(
                                  'Mes informations',
                                  style: FlutterFlowTheme.of(context)
                                      .bodyLarge
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                        ),
                                        fontSize: 16.0,
                                        color: const Color(0xFF2D2A72),
                                        letterSpacing: 0.0,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 28.0),
                              child: _buildMenuCard(
                                context,
                                icon: Icons.logout_rounded,
                                onTap: () async {
                                  GoRouter.of(context).clearRedirectLocation();
                                  FFAppState().update(
                                      () => FFAppState().isLoggingOut = true);
                                  context.go('/loginPage');
                                  await authManager.signOut();
                                  FFAppState().update(
                                      () => FFAppState().isLoggingOut = false);
                                },
                                title: Text(
                                  'Se déconnecter',
                                  style: FlutterFlowTheme.of(context)
                                      .bodyLarge
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                        ),
                                        fontSize: 16.0,
                                        color: const Color(0xFF2D2A72),
                                        letterSpacing: 0.0,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                            _buildSectionTitle(context, 'PROXIPLAY'),
                            const SizedBox(height: 14.0),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14.0),
                              child: _buildMenuCard(
                                context,
                                icon: Icons.mail_outline_rounded,
                                onTap: () {
                                  context.pushNamed(ContactPageWidget.routeName);
                                },
                                title: Text(
                                  'Nous contacter',
                                  style: FlutterFlowTheme.of(context)
                                      .bodyLarge
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                        ),
                                        fontSize: 16.0,
                                        color: const Color(0xFF2D2A72),
                                        letterSpacing: 0.0,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 18.0),
                              child: _buildMenuCard(
                                context,
                                icon: Icons.folder_outlined,
                                onTap: () {
                                  context.pushNamed(LegalPageWidget.routeName);
                                },
                                title: Text(
                                  'Mentions légales',
                                  style: FlutterFlowTheme.of(context)
                                      .bodyLarge
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                        ),
                                        fontSize: 16.0,
                                        color: const Color(0xFF2D2A72),
                                        letterSpacing: 0.0,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                await _handleDeleteAccountTap();
                              },
                              child: const Padding(
                                padding:
                                    EdgeInsets.only(top: 18.0, bottom: 16.0),
                                child: Center(
                                  child: Text(
                                    'Supprimer mon compte',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13.0,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
