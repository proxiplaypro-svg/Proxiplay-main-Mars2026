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
/// Mise en page en deux colonnes (texte a gauche, image du lot/commercant
/// en bande verticale a droite) plutot qu'une bande photo en haut : la
/// carte reste large, mais l'image identifie visuellement le lot sans
/// pousser le contenu textuel vers le bas.
/// Pictogrammes vectoriels alignes sur ceux des cartes de jeux classiques
/// (meme couleur bleu nuit, meme famille outline) : `Icons.card_giftcard`
/// pour la recompense, `Icons.local_fire_department_outlined` pour la
/// progression, `Icons.calendar_today_outlined` pour le tirage (meme
/// pictogramme que "Jusqu'au" sur les cartes classiques — le texte donne
/// le contexte).
class BonusGameCardWidget extends StatelessWidget {
  const BonusGameCardWidget({
    super.key,
    required this.state,
    this.onTap,
  });

  final MonthlyChallengeStateViewModel state;
  final VoidCallback? onTap;

  static const _navy = Color(0xFF26235C);
  static const _imageColumnWidth = 110.0;

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

    final textColumn = Padding(
      padding: EdgeInsets.fromLTRB(
        16.0,
        14.0,
        thumbnailUrl.isNotEmpty ? _imageColumnWidth + 12.0 : 16.0,
        16.0,
      ),
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
              const Icon(Icons.local_fire_department_outlined,
                  size: 17.0, color: _navy),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.card_giftcard, size: 17.0, color: _navy),
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
            ],
          ),
          if (prizeValueText.isNotEmpty) ...[
            const SizedBox(height: 8.0),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
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
            ),
          ],
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
                const Icon(Icons.calendar_today_outlined,
                    size: 15.0, color: _navy),
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
    );

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
          ),
          // Stack plutot que Row+IntrinsicHeight : IntrinsicHeight doit
          // "deviner" la hauteur du texte avant la vraie passe de mise en
          // page, et ce calcul s'est avere peu fiable pour ce contenu
          // (overflow + carte visiblement surdimensionnee). Ici, le texte
          // (non positionne) determine seul la hauteur du Stack, et
          // l'image est etiree sur cette hauteur via un Positioned
          // top/right/bottom (meme principe que la photo commercant dans
          // MerchantOfferedByBubble) — sans mesure intrinseque fragile.
          child: Stack(
            children: [
              textColumn,
              if (thumbnailUrl.isNotEmpty)
                Positioned(
                  top: 0.0,
                  right: 0.0,
                  bottom: 0.0,
                  width: _imageColumnWidth,
                  child: ProxiplayNetworkImage(
                    imageUrl: thumbnailUrl,
                    width: _imageColumnWidth,
                    fit: BoxFit.cover,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(18.0),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
