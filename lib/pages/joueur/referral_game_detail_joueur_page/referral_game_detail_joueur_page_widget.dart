import '/auth/firebase_auth/auth_util.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/widgets/proxiplay_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

/// Fiche complete du jeu de parrainage a la une (image, lot a gagner, regles
/// du jeu, vos tickets), ouverte depuis la carte "Parrainage" de l'accueil.
/// referral_games est une collection separee de games (pas de GamesRecord
/// genere), donc cette page lit Firestore directement plutot que de
/// reutiliser JeuDetailJoueurPageWidget (conçue pour le mecanisme de
/// grattage instantane, sans rapport avec un tirage au sort par tickets).
class ReferralGameDetailJoueurPageWidget extends StatelessWidget {
  const ReferralGameDetailJoueurPageWidget({super.key, required this.gameId});

  final String gameId;

  static String routeName = 'ReferralGameDetailJoueurPage';
  static String routePath = 'referralGameDetailJoueurPage';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        // Logo plutot que le texte "Parrainage" : ce dernier est deja
        // affiche par le badge sur l'image juste en dessous, pas besoin de
        // le repeter deux fois en haut de la page.
        title: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: SvgPicture.asset(
            'assets/images/logo_D_secondaire_sans_html_avec_couleurs.svg',
            height: 36.0,
            fit: BoxFit.contain,
          ),
        ),
        centerTitle: true,
        elevation: 0.0,
      ),
      body: SafeArea(
        top: true,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('referral_games')
              .doc(gameId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox.shrink();
            }
            if (!snapshot.data!.exists) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text('Ce jeu de parrainage n\'est plus disponible.'),
                ),
              );
            }

            final data = snapshot.data!.data() ?? {};
            final title = ((data['title'] as String?)?.trim().isNotEmpty ==
                    true)
                ? data['title'] as String
                : 'Jeu de parrainage';
            final description = (data['description'] as String?)?.trim() ?? '';
            final prizeDescription =
                (data['prize_description'] as String?)?.trim() ?? '';
            final imageUrl = (data['image_url'] as String?)?.trim() ?? '';
            final endDate = (data['end_date'] as Timestamp?)?.toDate();

            return SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(20.0, 8.0, 20.0, 28.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroImage(context, imageUrl),
                  const SizedBox(height: 18.0),
                  Text(
                    title,
                    style: FlutterFlowTheme.of(context).headlineSmall.override(
                          font: GoogleFonts.interTight(
                              fontWeight: FontWeight.w800),
                          fontSize: 21.0,
                          letterSpacing: 0.0,
                          color: const Color(0xFF2D2A72),
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 8.0),
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        fontSize: 14.0,
                        color: const Color(0xFF6B6B8B),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20.0),
                  if (prizeDescription.isNotEmpty)
                    _buildInfoCard(
                      context,
                      icon: Icons.card_giftcard_rounded,
                      iconBackground: const Color(0xFFF9E4EC),
                      iconColor: const Color(0xFFA0134D),
                      title: 'Lot à gagner',
                      child: Text(
                        prizeDescription,
                        style: GoogleFonts.inter(
                          fontSize: 15.0,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF26235C),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14.0),
                  _buildTicketsCard(context),
                  const SizedBox(height: 14.0),
                  _buildInfoCard(
                    context,
                    icon: Icons.rule_rounded,
                    iconBackground: const Color(0xFFEAF3DE),
                    iconColor: const Color(0xFF3B6D11),
                    title: 'Règles du jeu',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRuleLine(
                          'Chaque ami qui crée son compte grâce à ton code te donne un ticket supplémentaire, sans limite.',
                        ),
                        const SizedBox(height: 6.0),
                        _buildRuleLine(
                          endDate != null
                              ? 'Le tirage au sort a lieu le ${dateTimeFormat('d/M/y', endDate, locale: FFLocalizations.of(context).languageCode)} parmi tous les tickets valides.'
                              : 'Le tirage au sort a lieu à la date de fin du jeu, parmi tous les tickets valides.',
                        ),
                        const SizedBox(height: 6.0),
                        _buildRuleLine(
                          'Plus tu as de tickets, plus tu augmentes tes chances d’être tiré au sort.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22.0),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        context.pushNamed(ParrainageJoueurPageWidget.routeName);
                      },
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
                            'Inviter un ami',
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroImage(BuildContext context, String imageUrl) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24.0),
          child: SizedBox(
            width: double.infinity,
            height: 190.0,
            child: imageUrl.isEmpty
                ? Container(
                    color: const Color(0xFFF2F4FF),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.image_outlined,
                      color: Color(0xFF6B70A7),
                      size: 32.0,
                    ),
                  )
                : ProxiplayNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          left: 12.0,
          top: 12.0,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2A72),
              borderRadius: BorderRadius.circular(999.0),
            ),
            child: Text(
              'Parrainage',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 11.0,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required IconData icon,
    required Color iconBackground,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40.0,
            height: 40.0,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Icon(icon, color: iconColor, size: 20.0),
          ),
          const SizedBox(width: 14.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.0,
                    color: const Color(0xFF2D2A72),
                  ),
                ),
                const SizedBox(height: 6.0),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleLine(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6.0),
          child: Icon(Icons.circle, size: 4.0, color: Color(0xFF6B6B8B)),
        ),
        const SizedBox(width: 8.0),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13.0,
              color: const Color(0xFF6B6B8B),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTicketsCard(BuildContext context) {
    final uid = currentUserUid;
    if (uid.isEmpty) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('referral_games')
          .doc(gameId)
          .collection('entries')
          .where('inviter_uid', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        final ticketCount = snapshot.data?.docs.length ?? 0;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: const Color(0xFFFDF5F8),
            borderRadius: BorderRadius.circular(20.0),
            border: Border.all(color: const Color(0xFFF3D4E1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Vos tickets',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.0,
                  color: const Color(0xFF2D2A72),
                ),
              ),
              Text(
                '$ticketCount',
                style: FlutterFlowTheme.of(context).headlineSmall.override(
                      font: GoogleFonts.interTight(fontWeight: FontWeight.w800),
                      fontSize: 22.0,
                      color: const Color(0xFFA0134D),
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}
