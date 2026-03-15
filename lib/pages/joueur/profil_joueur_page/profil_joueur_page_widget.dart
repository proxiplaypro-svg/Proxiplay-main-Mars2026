import '/backend/backend.dart';
import '/auth/firebase_auth/auth_util.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/widgets/profile/profile_header_card_widget.dart';
import '/widgets/profile/profile_menu_card_widget.dart';
import '/widgets/profile/profile_menu_section_widget.dart';
import 'package:flutter/material.dart';
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
                            AuthUserStreamWidget(
                              builder: (context) {
                                final firstName =
                                    valueOrDefault(currentUserDocument?.firstName, '');
                                final lastName =
                                    valueOrDefault(currentUserDocument?.lastName, '');
                                final displayName = firstName.trim().isNotEmpty
                                    ? firstName.trim()
                                    : '$firstName $lastName'.trim();

                                return ProfileHeaderCard(
                                  greeting:
                                      'Bonjour ${displayName.isNotEmpty ? displayName : 'joueur'}',
                                  subtitle: 'Votre espace personnel ProxiPlay',
                                  titleColor: _navy,
                                  subtitleColor: _navy.withValues(alpha: 0.65),
                                );
                              },
                            ),
                            const SizedBox(height: 24.0),
                            ProfileMenuSection(
                              title: 'MON COMPTE',
                              titleColor: _navy.withValues(alpha: 0.72),
                              children: [
                                StreamBuilder<List<MyLotsRecord>>(
                                  stream: currentUserReference == null
                                      ? const Stream<List<MyLotsRecord>>.empty()
                                      : queryMyLotsRecord(
                                          parent: currentUserReference),
                                  builder: (context, snapshot) {
                                    final myLots =
                                        snapshot.data ?? const <MyLotsRecord>[];
                                    return FutureBuilder<int>(
                                      key: ValueKey(
                                        myLots
                                            .map((lot) => lot.reference.path)
                                            .join('|'),
                                      ),
                                      future: _loadLotsToClaimCount(myLots),
                                      builder: (context, countSnapshot) {
                                        final lotsToClaim =
                                            countSnapshot.data ?? 0;
                                        final lotsLabel = lotsToClaim <= 1
                                            ? '$lotsToClaim lot \u00e0 r\u00e9cup\u00e9rer'
                                            : '$lotsToClaim lots \u00e0 r\u00e9cup\u00e9rer';
                                        return ProfileMenuCard(
                                          icon: Icons.card_giftcard_rounded,
                                          title: lotsLabel,
                                          iconTint: _raspberryTint,
                                          iconColor: _raspberry,
                                          titleColor: _navy,
                                          borderColor:
                                              _raspberry.withValues(alpha: 0.22),
                                          shadowColor: _raspberry
                                              .withValues(alpha: 0.08),
                                          onTap: () {
                                            context.pushNamed(
                                                LotsJoueurPageWidget.routeName);
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                                const SizedBox(height: 12.0),
                                ProfileMenuCard(
                                  icon: Icons.person_outline_rounded,
                                  title: 'Mes informations',
                                  iconTint: _navyTint,
                                  iconColor: _navy,
                                  titleColor: _navy,
                                  borderColor: _navy.withValues(alpha: 0.06),
                                  shadowColor:
                                      Colors.black.withValues(alpha: 0.035),
                                  onTap: () {
                                    context.pushNamed(
                                        EditJoueurPageWidget.routeName);
                                  },
                                ),
                                const SizedBox(height: 12.0),
                                ProfileMenuCard(
                                  icon: Icons.logout_rounded,
                                  title: 'Se d\u00e9connecter',
                                  iconTint: _navyTint,
                                  iconColor: _navy,
                                  titleColor: _navy,
                                  borderColor: _navy.withValues(alpha: 0.06),
                                  shadowColor:
                                      Colors.black.withValues(alpha: 0.035),
                                  onTap: () async {
                                    GoRouter.of(context)
                                        .clearRedirectLocation();
                                    FFAppState().update(
                                        () => FFAppState().isLoggingOut = true);
                                    context.go('/loginPage');
                                    await authManager.signOut();
                                    FFAppState().update(() =>
                                        FFAppState().isLoggingOut = false);
                                  },
                                ),
                                const SizedBox(height: 12.0),
                                ProfileMenuCard(
                                  icon: Icons.delete_forever_rounded,
                                  title: 'Supprimer mon compte',
                                  compactLabel: true,
                                  iconTint: _raspberryTint,
                                  iconColor: _raspberry,
                                  titleColor: _raspberry,
                                  borderColor:
                                      _navy.withValues(alpha: 0.06),
                                  shadowColor:
                                      Colors.black.withValues(alpha: 0.035),
                                  onTap: () async {
                                    final confirmDialogResponse =
                                            await showDialog<bool>(
                                                  context: context,
                                                  builder:
                                                      (alertDialogContext) {
                                                    return WebViewAware(
                                                      child: AlertDialog(
                                                        title: const Text(
                                                            'Suppression du compte'),
                                                        content: const Text(
                                                            '\u00cates-vous s\u00fbr de vouloir supprimer votre compte ?'),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () => Navigator.pop(
                                                                alertDialogContext,
                                                                false),
                                                            child: const Text(
                                                                'Annuler'),
                                                          ),
                                                          TextButton(
                                                            onPressed: () => Navigator.pop(
                                                                alertDialogContext,
                                                                true),
                                                            child: const Text(
                                                                'Confirmer'),
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
                                      context.pushNamed(
                                          LoginPageWidget.routeName);
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 24.0),
                            ProfileMenuSection(
                              title: 'PROXIPLAY',
                              titleColor: _navy.withValues(alpha: 0.72),
                              children: [
                                ProfileMenuCard(
                                  icon: Icons.mail_outline_rounded,
                                  title: 'Nous contacter',
                                  iconTint: _navyTint,
                                  iconColor: _navy,
                                  titleColor: _navy,
                                  borderColor: _navy.withValues(alpha: 0.06),
                                  shadowColor:
                                      Colors.black.withValues(alpha: 0.035),
                                  onTap: () {
                                    context.pushNamed(ContactPageWidget.routeName);
                                  },
                                ),
                                const SizedBox(height: 12.0),
                                ProfileMenuCard(
                                  icon: Icons.folder_outlined,
                                  title: 'Mentions l\u00e9gales',
                                  iconTint: _navyTint,
                                  iconColor: _navy,
                                  titleColor: _navy,
                                  borderColor: _navy.withValues(alpha: 0.06),
                                  shadowColor:
                                      Colors.black.withValues(alpha: 0.035),
                                  onTap: () {
                                    context.pushNamed(LegalPageWidget.routeName);
                                  },
                                ),
                              ],
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
