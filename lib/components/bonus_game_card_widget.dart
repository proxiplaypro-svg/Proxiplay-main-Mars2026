import '/flutter_flow/flutter_flow_theme.dart';
import '/models/monthly_challenge_models.dart';
import '/widgets/proxiplay_network_image.dart';
import '/components/monthly_challenge_banner_widget.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Carte unique "Bonus du mois" (mecanique d'assiduite, enseigne partenaire
/// optionnelle — ce n'est plus un type de defi different). Un seul template,
/// pas de carrousel : la Home n'affiche jamais plus d'un Bonus actif a la
/// fois (regle produit + validation admin), voir
/// `_buildBonusGamesZone()` dans home_joueur_page_widget.dart pour le
/// traitement defensif du cas historique (>1 actif en base).
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
    // Le titre de carte est le nom du lot (jamais le nom de l'enseigne
    // partenaire) : c'est le lot qui identifie le Bonus, l'enseigne n'est
    // qu'une information secondaire optionnelle.
    final lotTitle =
        state.prizeTitle.isNotEmpty ? state.prizeTitle : 'Un lot à gagner';
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
    // Le montant s'affiche toujours quand il est disponible, avec ou sans
    // enseigne associée — l'enseigne n'est qu'une mention secondaire ajoutée
    // au montant, jamais une condition pour l'afficher.
    final amountText = prizeValueText.isNotEmpty
        ? (hasMerchant
            ? '$prizeValueText · Offert par ${state.merchantName}'
            : prizeValueText)
        : (hasMerchant ? 'Offert par ${state.merchantName}' : 'Un lot à gagner');
    final dateText = state.drawDate != null
        ? 'Tirage le ${formatChallengeShortDate(state.drawDate!.toDate(), withYear: true)}'
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
                      lotTitle,
                      style: theme.titleMedium.override(
                        font: GoogleFonts.interTight(fontWeight: FontWeight.w800),
                        color: const Color(0xFF2C2F5B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      'Jouez ${state.targetDays} jours pour participer',
                      style: theme.bodySmall.override(
                        font: GoogleFonts.inter(fontWeight: FontWeight.w500),
                        color: const Color(0xFF5C627A),
                        fontWeight: FontWeight.w500,
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
                    const SizedBox(height: 14.0),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🎁', style: TextStyle(fontSize: 15.0)),
                        const SizedBox(width: 6.0),
                        Expanded(
                          child: Text(
                            amountText,
                            style: theme.bodyMedium.override(
                              font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                              color: const Color(0xFF2C2F5B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
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
