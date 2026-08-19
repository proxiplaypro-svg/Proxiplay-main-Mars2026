import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../campaign_monthly_challenge_admin_page/campaign_monthly_challenge_admin_page_widget.dart';
import '../campaign_share_promo_admin_page/campaign_share_promo_admin_page_widget.dart';
import '../monthly_challenge_stats_admin_page/monthly_challenge_stats_admin_page_widget.dart';
import '../share_promo_stats_admin_page/share_promo_stats_admin_page_widget.dart';

class AnimationsPromotionsAdminPageWidget extends StatelessWidget {
  const AnimationsPromotionsAdminPageWidget({super.key});

  static String routeName = 'AnimationsPromotionsAdminPage';
  static String routePath = 'animationsPromotionsAdminPage';

  void _openPage(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color accentColor,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22.0),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18.0,
                offset: const Offset(0.0, 8.0),
              ),
            ],
            border: Border.all(
              color: accentColor.withValues(alpha: 0.18),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Row(
              children: [
                Container(
                  width: 48.0,
                  height: 48.0,
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

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.secondaryBackground,
      appBar: AppBar(
        title: Text(
          'Animations & promotions',
          style: theme.titleLarge.override(
            font: GoogleFonts.interTight(
              fontWeight: FontWeight.w700,
              fontStyle: theme.titleLarge.fontStyle,
            ),
            letterSpacing: 0.0,
            fontWeight: FontWeight.w700,
            fontStyle: theme.titleLarge.fontStyle,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          Text(
            'Acces administrateur aux outils de parrainage et de pilotage promotionnel.',
            style: theme.bodyLarge,
          ),
          const SizedBox(height: 20.0),
          _buildActionCard(
            context,
            icon: Icons.settings_suggest_rounded,
            title: 'Campagne parrainage',
            subtitle: 'Configurer la campagne share promo.',
            onTap: () => _openPage(
              context,
              const CampaignSharePromoAdminPageWidget(),
            ),
            accentColor: const Color(0xFF7A5AF8),
          ),
          const SizedBox(height: 14.0),
          _buildActionCard(
            context,
            icon: Icons.bar_chart_rounded,
            title: 'Statistiques parrainage',
            subtitle: 'Consulter les KPI, referrals et rewards.',
            onTap: () => _openPage(
              context,
              const SharePromoStatsAdminPageWidget(),
            ),
            accentColor: const Color(0xFF2E90FA),
          ),
          const SizedBox(height: 14.0),
          _buildActionCard(
            context,
            icon: Icons.emoji_events_rounded,
            title: 'Défi mensuel',
            subtitle: 'Configurer le défi d’assiduité du mois.',
            onTap: () => _openPage(
              context,
              const CampaignMonthlyChallengeAdminPageWidget(),
            ),
            accentColor: const Color(0xFFC26A1B),
          ),
          const SizedBox(height: 14.0),
          _buildActionCard(
            context,
            icon: Icons.query_stats_rounded,
            title: 'Stats défi mensuel',
            subtitle: 'Voir les qualifiés et lancer le tirage.',
            onTap: () => _openPage(
              context,
              const MonthlyChallengeStatsAdminPageWidget(),
            ),
            accentColor: const Color(0xFF1D8348),
          ),
        ],
      ),
    );
  }
}
