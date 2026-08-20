import '/auth/firebase_auth/auth_util.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/components/list_empty_component_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/services/share_promo_service.dart';
import '/utils/share_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'parrainage_joueur_page_model.dart';
export 'parrainage_joueur_page_model.dart';

/// Page joueur : mes envois de parrainage, mes filleuls, inviter un ami.
class ParrainageJoueurPageWidget extends StatefulWidget {
  const ParrainageJoueurPageWidget({super.key});

  static String routeName = 'ParrainageJoueurPage';
  static String routePath = 'parrainageJoueurPage';

  @override
  State<ParrainageJoueurPageWidget> createState() =>
      _ParrainageJoueurPageWidgetState();
}

class _ParrainageJoueurPageWidgetState
    extends State<ParrainageJoueurPageWidget> {
  late ParrainageJoueurPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  final _sharePromoService = SharePromoService();
  bool _isInviting = false;
  final Set<String> _relaunchingReferralIds = <String>{};

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => ParrainageJoueurPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'ParrainageJoueurPage'});
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _inviteFriend() async {
    if (_isInviting) {
      return;
    }
    setState(() => _isInviting = true);

    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 2),
            content: Text('Préparation du partage...'),
          ),
        );
    }

    try {
      final response = await _sharePromoService.createReferral(
        shareChannel: 'native_share',
      );
      final inviteCode = (response['inviteCode'] as String?)?.trim();
      final responseShareLink = (response['shareLink'] as String?)?.trim();
      final responseReferralCode =
          extractReferralCodeFromUri(Uri.tryParse(responseShareLink ?? ''));
      final shareLink =
          buildReferralShareLink(inviteCode ?? responseReferralCode);
      final shareText = buildAppShareText(
        title: 'Rejoins-moi sur ProxiPlay !',
        description:
            'Télécharge l\'app et débloque des parties supplémentaires pour nous deux.',
        referralCode: inviteCode ?? responseReferralCode,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      await Share.share(
        shareText.isNotEmpty ? shareText : shareLink,
        subject: 'Inviter un ami sur ProxiPlay',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Le partage n\'a pas pu être ouvert. Réessaie.'),
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() => _isInviting = false);
      }
    }
  }

  Future<void> _relaunchReferral(String referralId, String? inviteCode) async {
    if (_relaunchingReferralIds.contains(referralId)) {
      return;
    }
    setState(() => _relaunchingReferralIds.add(referralId));

    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 2),
            content: Text('Préparation de la relance...'),
          ),
        );
    }

    try {
      final shareLink = buildReferralShareLink(inviteCode);
      final shareText = buildAppShareText(
        title: 'Toujours partant pour ProxiPlay ?',
        description: 'Ton invitation t\'attend toujours, rejoins-moi !',
        referralCode: inviteCode,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      await Share.share(
        shareText.isNotEmpty ? shareText : shareLink,
        subject: 'Rappel — Inviter un ami sur ProxiPlay',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Le partage n\'a pas pu être ouvert. Réessaie.'),
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() => _relaunchingReferralIds.remove(referralId));
      }
    }
  }

  Widget _buildHeaderCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(28.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 22.0,
            offset: const Offset(0.0, 8.0),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Parraine tes amis',
              style: FlutterFlowTheme.of(context).headlineSmall.override(
                    font: GoogleFonts.interTight(fontWeight: FontWeight.w800),
                    fontSize: 21.0,
                    letterSpacing: 0.0,
                    color: const Color(0xFF2D2A72),
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10.0),
            Text(
              'Chaque ami qui crée son compte grâce à toi te donne un bonus, sans limite.',
              style: FlutterFlowTheme.of(context).bodyMedium.override(
                    font: GoogleFonts.inter(fontWeight: FontWeight.w400),
                    fontSize: 14.0,
                    color: const Color(0xFF6B6B8B),
                    letterSpacing: 0.0,
                  ),
            ),
            const SizedBox(height: 18.0),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isInviting ? null : _inviteFriend,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA0134D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18.0),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.share_rounded, size: 20.0),
                    const SizedBox(width: 10.0),
                    Text(
                      _isInviting ? 'Ouverture...' : 'Inviter un ami',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 6.0),
      child: Text(
        '$title ($count)',
        style: FlutterFlowTheme.of(context).labelLarge.override(
              font: GoogleFonts.inter(fontWeight: FontWeight.w700),
              fontSize: 16.0,
              color: const Color(0xFF4B5078),
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _buildPendingRow(BuildContext context, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final inviteCode = (data['inviteCode'] as String?)?.trim();
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final isRelaunching = _relaunchingReferralIds.contains(doc.id);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(20.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14.0,
            offset: const Offset(0.0, 4.0),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Invitation en attente',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.0,
                    color: const Color(0xFF2D2A72),
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  createdAt != null
                      ? 'Envoyée le ${dateTimeFormat('d/M/y', createdAt)} · code $inviteCode'
                      : 'Code $inviteCode',
                  style: GoogleFonts.inter(
                    fontSize: 12.0,
                    color: const Color(0xFF6B6B8B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12.0),
          OutlinedButton(
            onPressed: isRelaunching
                ? null
                : () => _relaunchReferral(doc.id, inviteCode),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFA0134D),
              side: const BorderSide(color: Color(0xFFE7B8CB)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14.0),
              ),
            ),
            child: Text(
              isRelaunching ? 'Ouverture...' : 'Relancer',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 13.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptedRow(BuildContext context, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final acceptedAt = (data['acceptedAt'] as Timestamp?)?.toDate();
    final rewardStatus = (data['rewardStatus'] as String?) ?? 'not_earned';
    final rewardLabel = rewardStatus == 'earned' || rewardStatus == 'granted'
        ? 'Bonus accordé'
        : 'Bonus en cours';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(20.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14.0,
            offset: const Offset(0.0, 4.0),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44.0,
            height: 44.0,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3DE),
              borderRadius: BorderRadius.circular(14.0),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Color(0xFF3B6D11),
              size: 22.0,
            ),
          ),
          const SizedBox(width: 14.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ami inscrit',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.0,
                    color: const Color(0xFF2D2A72),
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  acceptedAt != null
                      ? 'Le ${dateTimeFormat('d/M/y', acceptedAt)} · $rewardLabel'
                      : rewardLabel,
                  style: GoogleFonts.inter(
                    fontSize: 12.0,
                    color: const Color(0xFF6B6B8B),
                  ),
                ),
              ],
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
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: false,
          leading: FlutterFlowIconButton(
            borderRadius: 24.0,
            buttonSize: 48.0,
            icon: Icon(
              Icons.chevron_left_rounded,
              color: FlutterFlowTheme.of(context).primaryText,
              size: 24.0,
            ),
            onPressed: () async {
              context.safePop();
            },
          ),
          title: Text(
            'Parrainage',
            style: FlutterFlowTheme.of(context).headlineMedium.override(
                  font: GoogleFonts.interTight(
                    fontWeight:
                        FlutterFlowTheme.of(context).headlineMedium.fontWeight,
                  ),
                  fontSize: 22.0,
                  letterSpacing: 0.0,
                  fontWeight:
                      FlutterFlowTheme.of(context).headlineMedium.fontWeight,
                ),
          ),
          actions: const [],
          centerTitle: true,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFCFCFF),
                  Color(0xFFF2F4FF),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        20.0, 18.0, 20.0, 0.0),
                    child: currentUserReference == null
                        ? const SizedBox.shrink()
                        : StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('referrals')
                                .where('inviterUid', isEqualTo: currentUserUid)
                                .orderBy('createdAt', descending: true)
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: SizedBox(
                                    width: 50.0,
                                    height: 50.0,
                                    child: SizedBox.shrink(),
                                  ),
                                );
                              }

                              final docs = snapshot.data!.docs;
                              final pending = docs.where((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return data['status'] == 'pending';
                              }).toList();
                              final accepted = docs.where((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return data['status'] == 'accepted';
                              }).toList();

                              return SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildHeaderCard(context),
                                    const SizedBox(height: 24.0),
                                    _buildSectionTitle(context, 'Mes filleuls',
                                        accepted.length),
                                    const SizedBox(height: 14.0),
                                    if (accepted.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.only(bottom: 14.0),
                                        child: ListEmptyComponentWidget(
                                          title: 'Aucun filleul pour le moment',
                                          description:
                                              'Invite un ami pour qu\'il apparaisse ici dès son inscription.',
                                        ),
                                      )
                                    else
                                      ...accepted.map(
                                        (doc) => Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 12.0),
                                          child:
                                              _buildAcceptedRow(context, doc),
                                        ),
                                      ),
                                    const SizedBox(height: 10.0),
                                    _buildSectionTitle(
                                        context, 'Mes envois', pending.length),
                                    const SizedBox(height: 14.0),
                                    if (pending.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.only(bottom: 24.0),
                                        child: ListEmptyComponentWidget(
                                          title: 'Aucune invitation en attente',
                                          description:
                                              'Tes invitations envoyées mais pas encore acceptées apparaîtront ici.',
                                        ),
                                      )
                                    else
                                      ...pending.map(
                                        (doc) => Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 12.0),
                                          child: _buildPendingRow(context, doc),
                                        ),
                                      ),
                                    const SizedBox(height: 24.0),
                                  ],
                                ),
                              );
                            },
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
    );
  }
}
