import '/auth/firebase_auth/auth_util.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/pages/admin/commercants_admin_page/commercants_admin_page_widget.dart';
import '/pages/admin/joueurs_admin_page/joueurs_admin_page_widget.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeAdminPageWidget extends StatefulWidget {
  const HomeAdminPageWidget({super.key});

  static String routeName = 'HomeAdminPage';
  static String routePath = 'homeAdminPage';

  @override
  State<HomeAdminPageWidget> createState() => _HomeAdminPageWidgetState();
}

class _HomeAdminPageWidgetState extends State<HomeAdminPageWidget> {
  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    logFirebaseEvent(
      'screen_view',
      parameters: {'screen_name': 'HomeAdminPage'},
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _pushAdminPage(String routeName) {
    context.pushNamed(
      routeName,
      extra: <String, dynamic>{
        kTransitionInfoKey: const TransitionInfo(
          hasTransition: true,
          transitionType: PageTransitionType.fade,
          duration: Duration(milliseconds: 0),
        ),
      },
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24.0, 0.0, 24.0, 0.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: Image.asset(
              'assets/images/Logo_(1).png',
              fit: BoxFit.contain,
            ),
          ),
          InkWell(
            splashColor: Colors.transparent,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            onTap: () async {
              FFAppState().update(() => FFAppState().isLoggingOut = true);
              GoRouter.of(context).clearRedirectLocation();
              context.go('/loginPage');
              await authManager.signOut();
              FFAppState().update(() => FFAppState().isLoggingOut = false);
            },
            child: Icon(
              Icons.logout_sharp,
              color: theme.primaryText,
              size: 24.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroSection(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Administration',
            style: theme.headlineMedium.override(
              font: GoogleFonts.interTight(
                fontWeight: FontWeight.w700,
                fontStyle: theme.headlineMedium.fontStyle,
              ),
              letterSpacing: 0.0,
              fontWeight: FontWeight.w700,
              fontStyle: theme.headlineMedium.fontStyle,
            ),
          ),
          const SizedBox(height: 6.0),
          Text(
            'Notifications, validation des comptes et pilotage des campagnes.',
            style: theme.bodyLarge.override(
              font: GoogleFonts.inter(
                fontWeight: theme.bodyLarge.fontWeight,
                fontStyle: theme.bodyLarge.fontStyle,
              ),
              color: theme.secondaryText,
              letterSpacing: 0.0,
              fontWeight: theme.bodyLarge.fontWeight,
              fontStyle: theme.bodyLarge.fontStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22.0),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: theme.primaryBackground,
            borderRadius: BorderRadius.circular(22.0),
            border: Border.all(color: accentColor.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18.0,
                offset: const Offset(0.0, 8.0),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Row(
              children: [
                Container(
                  width: 52.0,
                  height: 52.0,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  child: Icon(icon, color: accentColor),
                ),
                const SizedBox(width: 14.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.titleMedium.override(
                          font: GoogleFonts.interTight(
                            fontWeight: FontWeight.w700,
                            fontStyle: theme.titleMedium.fontStyle,
                          ),
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w700,
                          fontStyle: theme.titleMedium.fontStyle,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        subtitle,
                        style: theme.bodySmall.override(
                          font: GoogleFonts.inter(
                            fontWeight: theme.bodySmall.fontWeight,
                            fontStyle: theme.bodySmall.fontStyle,
                          ),
                          color: theme.secondaryText,
                          letterSpacing: 0.0,
                          fontWeight: theme.bodySmall.fontWeight,
                          fontStyle: theme.bodySmall.fontStyle,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16.0,
                  color: accentColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openPlayersManagement() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const JoueursAdminPageWidget(),
      ),
    );
  }

  void _openMerchantsManagement() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CommercantsAdminPageWidget(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: theme.secondaryBackground,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(86.0),
          child: AppBar(
            backgroundColor: theme.secondaryBackground,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(bottom: 12.0),
              title: _buildTopBar(context),
              centerTitle: true,
              expandedTitleScale: 1.0,
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20.0, 8.0, 20.0, 20.0),
                children: [
                  _buildIntroSection(context),
                  _buildActionCard(
                    context,
                    icon: Icons.verified_user_outlined,
                    title: 'V\u00E9rification des comptes',
                    subtitle:
                        'Valider ou refuser les inscriptions commer\u00E7ants.',
                    accentColor: const Color(0xFF2E90FA),
                    onTap: () => _pushAdminPage(
                      ValidationCommercantsAdminPageWidget.routeName,
                    ),
                  ),
                  const SizedBox(height: 14.0),
                  _buildActionCard(
                    context,
                    icon: Icons.storefront_outlined,
                    title: 'Gestion des commerçants',
                    subtitle:
                        'Accéder à la gestion des profils commerçants.',
                    accentColor: const Color(0xFFF79009),
                    onTap: _openMerchantsManagement,
                  ),
                  const SizedBox(height: 14.0),
                  _buildActionCard(
                    context,
                    icon: Icons.people_outline_rounded,
                    title: 'Gestion des comptes joueurs',
                    subtitle:
                        'Accéder à la gestion des comptes utilisateurs.',
                    accentColor: const Color(0xFFEF6820),
                    onTap: _openPlayersManagement,
                  ),
                  const SizedBox(height: 14.0),
                  _buildActionCard(
                    context,
                    icon: Icons.notifications_active_outlined,
                    title: 'Notifications',
                    subtitle:
                        'Accéder au centre de notifications administrateur.',
                    accentColor: const Color(0xFF7A5AF8),
                    onTap: () => _pushAdminPage(
                      AdminNotificationsCenterPageWidget.routeName,
                    ),
                  ),
                  const SizedBox(height: 14.0),
                  _buildActionCard(
                    context,
                    icon: Icons.campaign_outlined,
                    title: 'Partages et promo',
                    subtitle:
                        'Configurer la campagne de parrainage et ses statistiques.',
                    accentColor: const Color(0xFF12B76A),
                    onTap: () => _pushAdminPage(
                      AnimationsPromotionsAdminPageWidget.routeName,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

