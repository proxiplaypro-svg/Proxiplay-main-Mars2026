import '/auth/firebase_auth/auth_util.dart';
import '/components/list_empty_component_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/services/merchant_referral_service.dart';
import '/utils/merchant_referral_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'parrainage_commercant_page_model.dart';
export 'parrainage_commercant_page_model.dart';

/// Page joueur : parrainer un commercant et recevoir 100 EUR s'il devient
/// client payant dans les conditions du programme. Programme distinct du
/// parrainage joueur existant (bonus de jeu, voir parrainage_joueur_page) :
/// code et suivi gérés par un espace backend séparé
/// (merchant_referral_codes / merchant_referrals), jamais mélangés.
class ParrainageCommercantPageWidget extends StatefulWidget {
  const ParrainageCommercantPageWidget({super.key});

  static String routeName = 'ParrainageCommercantPage';
  static String routePath = 'parrainageCommercantPage';

  @override
  State<ParrainageCommercantPageWidget> createState() =>
      _ParrainageCommercantPageWidgetState();
}

class _ParrainageCommercantPageWidgetState
    extends State<ParrainageCommercantPageWidget> {
  late ParrainageCommercantPageModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final _merchantReferralService = MerchantReferralService();

  static const ink = Color(0xFF2D2A72);
  static const muted = Color(0xFF6B6B8B);
  static const accent = Color(0xFFA0134D);

  String? _code;
  bool _loadingCode = true;
  String? _loadError;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => ParrainageCommercantPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'ParrainageCommercantPage'});
    _loadCode();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _loadCode() async {
    setState(() {
      _loadingCode = true;
      _loadError = null;
    });
    try {
      final code = await _merchantReferralService.generateMerchantReferralCode();
      if (!mounted) return;
      setState(() {
        _code = code;
        _loadingCode = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Impossible de récupérer votre code pour le moment.';
        _loadingCode = false;
      });
    }
  }

  Future<void> _copyCode() async {
    final code = _code;
    if (code == null || code.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Code copié'),
        backgroundColor: FlutterFlowTheme.of(context).primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareCode() async {
    final code = _code;
    if (code == null || code.isEmpty || _isSharing) return;
    setState(() => _isSharing = true);
    try {
      await Share.share(
        buildMerchantReferralShareText(code),
        subject: 'Parrainez un commerçant sur ProxiPlay',
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(24.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 18.0,
              offset: const Offset(0.0, 6.0),
            ),
          ],
        ),
        child: child,
      );

  Widget _buildStepsCard(BuildContext context) {
    const steps = [
      'Vous recommandez ProxiPlay à un commerçant.',
      'Vous lui transmettez votre code personnel.',
      'Le commerçant s\'inscrit sur Proxiplay.fr et renseigne votre code.',
      'Lorsqu\'il devient client payant dans les conditions du programme, '
          'vous pouvez recevoir 100 €.',
    ];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8.0,
            runSpacing: 2.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Parrainez un commerçant',
                style: FlutterFlowTheme.of(context).headlineSmall.override(
                      font: GoogleFonts.interTight(fontWeight: FontWeight.w800),
                      fontSize: 20.0,
                      letterSpacing: 0.0,
                      color: ink,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(width: 8.0),
              Text(
                '100 €',
                style: GoogleFonts.interTight(
                  fontWeight: FontWeight.w900,
                  fontSize: 22.0,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4.0),
          Text(
            'Recevez 100 € si le commerçant devient client dans les '
            'conditions du programme.',
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  font: GoogleFonts.inter(fontWeight: FontWeight.w400),
                  fontSize: 14.0,
                  color: muted,
                  letterSpacing: 0.0,
                ),
          ),
          const SizedBox(height: 16.0),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24.0,
                    height: 24.0,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF7E6EE),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.0,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: GoogleFonts.inter(fontSize: 13.5, color: ink),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4.0),
          InkWell(
            onTap: () => launchURL(merchantReferralConditionsUrl),
            child: Text(
              'Voir les conditions du programme',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                color: muted,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeCard(BuildContext context) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Votre code personnel',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15.0, color: ink),
          ),
          const SizedBox(height: 12.0),
          if (_loadingCode)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: SizedBox(
                  width: 22.0,
                  height: 22.0,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else if (_loadError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_loadError!, style: GoogleFonts.inter(color: muted, fontSize: 13.0)),
                const SizedBox(height: 8.0),
                OutlinedButton(
                  onPressed: _loadCode,
                  child: const Text('Réessayer'),
                ),
              ],
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F6FB),
                borderRadius: BorderRadius.circular(16.0),
                border: Border.all(color: const Color(0xFFE4E2F2)),
              ),
              child: Text(
                _code ?? '—',
                textAlign: TextAlign.center,
                style: GoogleFonts.interTight(
                  fontWeight: FontWeight.w800,
                  fontSize: 22.0,
                  letterSpacing: 2.0,
                  color: ink,
                ),
              ),
            ),
            const SizedBox(height: 14.0),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _code == null ? null : _copyCode,
                    icon: const Icon(Icons.copy_rounded, size: 18.0),
                    label: const Text('Copier le code'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ink,
                      side: const BorderSide(color: Color(0xFFE4E2F2)),
                      padding: const EdgeInsets.symmetric(vertical: 14.0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
                    ),
                  ),
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _code == null ? null : _shareCode,
                    icon: const Icon(Icons.share_rounded, size: 18.0),
                    label: Text(_isSharing ? 'Ouverture...' : 'Partager'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14.0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReferralRow(BuildContext context, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final status = data['status'] as String?;
    final label = merchantReferralStatusLabel(status);
    final description = merchantReferralStatusDescription(status);
    final isPositive = status == 'paid' || status == 'approved';
    final isNegative = status == 'rejected' || status == 'cancelled';
    final color = isPositive
        ? const Color(0xFF3B6D11)
        : isNegative
            ? const Color(0xFFA32D2D)
            : muted;
    final background = isPositive
        ? const Color(0xFFEAF3DE)
        : isNegative
            ? const Color(0xFFFCEBEB)
            : const Color(0xFFF0F0EC);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10.0),
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(18.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12.0,
            offset: const Offset(0.0, 3.0),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                  decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10.0)),
                  child: Text(
                    label,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.0, color: color),
                  ),
                ),
                const SizedBox(height: 6.0),
                Text(
                  description,
                  style: GoogleFonts.inter(fontSize: 12.5, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuiviSection(BuildContext context) {
    final userRef = currentUserReference;
    if (userRef == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('merchant_referrals')
          .where('inviter_user_id', isEqualTo: userRef)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final docs = snapshot.data!.docs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4.0, bottom: 12.0),
              child: Text(
                'Mes parrainages commerçants',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15.0, color: ink),
              ),
            ),
            if (docs.isEmpty)
              const ListEmptyComponentWidget(
                title: 'Aucun parrainage pour le moment',
                description: 'Les commerçants que vous parrainez apparaîtront ici dès qu\'ils auront utilisé votre code.',
              )
            else
              ...docs.map((doc) => _buildReferralRow(context, doc)),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          'Parrainage commerçant',
          style: FlutterFlowTheme.of(context).headlineMedium.override(
                font: GoogleFonts.interTight(
                  fontWeight: FlutterFlowTheme.of(context).headlineMedium.fontWeight,
                ),
                fontSize: 20.0,
                letterSpacing: 0.0,
                fontWeight: FlutterFlowTheme.of(context).headlineMedium.fontWeight,
              ),
        ),
        actions: const [],
        centerTitle: true,
        elevation: 0.0,
      ),
      body: SafeArea(
        top: true,
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(20.0, 18.0, 20.0, 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStepsCard(context),
              const SizedBox(height: 16.0),
              _buildCodeCard(context),
              const SizedBox(height: 24.0),
              _buildSuiviSection(context),
            ],
          ),
        ),
      ),
    );
  }
}
