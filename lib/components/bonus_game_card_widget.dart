import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/app_styles.dart';
import '/models/monthly_challenge_models.dart';
import '/widgets/proxiplay_network_image.dart';
import '/components/monthly_challenge_banner_widget.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Carte unique "Bonus fidelite" (mecanique d'assiduite, enseigne partenaire
/// optionnelle — ce n'est plus un type de defi different). Un seul template,
/// pas de carrousel : la Home n'affiche jamais plus d'un Bonus actif a la
/// fois (regle produit + validation admin), voir
/// `_buildBonusGamesZone()` dans home_joueur_page_widget.dart pour le
/// traitement defensif du cas historique (>1 actif en base).
///
/// Hierarchie : l'objectif d'assiduite est le message principal (jouer
/// regulierement qualifie automatiquement au tirage), le lot n'est que la
/// recompense de cette assiduite — jamais presente comme le nom du jeu.
class BonusGameCardWidget extends StatelessWidget {
  const BonusGameCardWidget({
    super.key,
    required this.state,
    this.onTap,
  });

  final MonthlyChallengeStateViewModel state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final thumbnailUrl =
        state.imageUrl.isNotEmpty ? state.imageUrl : state.merchantImageUrl;
    final progress = state.targetDays <= 0
        ? 0.0
        : (state.activeDaysCount / state.targetDays).clamp(0.0, 1.0);
    final accent = state.qualified
        ? const Color(0xFF1D8348)
        : const Color(0xFFC26A1B);
    final hasMerchant = state.merchantName.isNotEmpty;
    final prizeValueText = formatChallengePrizeValue(state.prizeValue);
    final lotTitle =
        state.prizeTitle.isNotEmpty ? state.prizeTitle : 'Un lot à gagner';
    final dateText = state.drawDate != null
        ? 'Tirage le ${formatChallengeShortDate(state.drawDate!.toDate())}'
        : null;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(18.0),
        onTap: onTap ?? () => showMonthlyChallengeDetails(context, state),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16.0,
                offset: const Offset(0.0, 6.0),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (thumbnailUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18.0)),
                  child: ProxiplayNetworkImage(
                    imageUrl: thumbnailUrl,
                    width: double.infinity,
                    height: 70.0,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 14.0, 16.0, 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Jouez ${state.targetDays} jours pour participer',
                      style: theme.titleMedium.override(
                        font: GoogleFonts.interTight(fontWeight: FontWeight.w800),
                        color: const Color(0xFF2C2F5B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14.0),
                    Row(
                      children: [
                        const Text('🔥', style: TextStyle(fontSize: 15.0)),
                        const SizedBox(width: 6.0),
                        Text(
                          '${state.activeDaysCount}/${state.targetDays} jours',
                          style: theme.bodyMedium.override(
                            font: GoogleFonts.interTight(fontWeight: FontWeight.w800),
                            color: const Color(0xFF2C2F5B),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8.0),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999.0),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8.0,
                        backgroundColor: const Color(0xFFEFEFEF),
                        color: accent,
                      ),
                    ),
                    if (state.qualified) ...[
                      const SizedBox(height: 8.0),
                      Text(
                        'Vous participez au tirage 🎉',
                        style: theme.bodySmall.override(
                          font: GoogleFonts.interTight(fontWeight: FontWeight.w700),
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14.0),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text('🎁', style: TextStyle(fontSize: 15.0)),
                        const SizedBox(width: 6.0),
                        Expanded(
                          child: Text(
                            lotTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodyMedium.override(
                              font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                              color: const Color(0xFF2C2F5B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (prizeValueText.isNotEmpty) ...[
                          const SizedBox(width: 8.0),
                          Container(
                            padding: AppStyles.gameCardPriceBadgePadding,
                            decoration: BoxDecoration(
                              color: AppStyles.gameCardPriceBadgeColor,
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                            child: Text(
                              prizeValueText,
                              style: theme.bodyMedium.override(
                                font: GoogleFonts.inter(fontWeight: FontWeight.w800),
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: AppStyles.gameCardPriceBadgeSize,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (hasMerchant) ...[
                      const SizedBox(height: 4.0),
                      Text(
                        'Offert par ${state.merchantName}',
                        style: theme.bodySmall.override(
                          font: GoogleFonts.inter(fontWeight: FontWeight.w500),
                          color: const Color(0xFF5C627A),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (dateText != null) ...[
                      const SizedBox(height: 8.0),
                      Row(
                        children: [
                          const Text('📅', style: TextStyle(fontSize: 13.0)),
                          const SizedBox(width: 6.0),
                          Text(
                            dateText,
                            style: theme.bodySmall.override(
                              font: GoogleFonts.inter(fontWeight: FontWeight.w500),
                              color: const Color(0xFF5C627A),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
