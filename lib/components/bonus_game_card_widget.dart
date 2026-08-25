import '/flutter_flow/app_styles.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/models/monthly_challenge_models.dart';
import '/widgets/proxiplay_network_image.dart';
import '/components/monthly_challenge_banner_widget.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Carte compacte pour la section "Jeux bonus" (défis mensuels : attendance,
/// merchant, et le fallback legacy "restaurant" — [state] est déjà normalisé
/// en amont, ce composant se contente de l'afficher).
///
/// Volontairement distinct de `GameCardWidget` : pas d'icône boutique, pas de
/// localisation, pas de date "jusqu'au" — ces informations n'ont pas de sens
/// pour un défi bonus. Réutilise seulement les constantes de style
/// (`AppStyles`) pour rester visuellement cohérent avec les cartes de jeux
/// classiques (rayon, ombre, badges).
class BonusGameCardWidget extends StatelessWidget {
  const BonusGameCardWidget({
    super.key,
    required this.state,
    this.width,
  });

  final MonthlyChallengeStateViewModel state;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final copy = buildChallengeCardCopy(state);
    final thumbnailUrl =
        state.imageUrl.isNotEmpty ? state.imageUrl : state.merchantImageUrl;
    final dateText = state.drawDate != null
        ? 'Tirage ${formatChallengeShortDate(state.drawDate!.toDate())}'
        : 'Tirage à venir';
    final badgeText = '${state.activeDaysCount}/${state.targetDays}';
    final prizeValueText = formatChallengePrizeValue(state.prizeValue);

    final cardWidth = width ?? AppStyles.gameCardWidth;
    // Meme ratio image/largeur que GameCardWidget (responsiveImageHeight).
    final imageHeight = (cardWidth * 0.50).clamp(84.0, 116.0);
    final cardRadius = BorderRadius.circular(AppStyles.gameCardRadius);

    return SizedBox(
      width: cardWidth,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: cardRadius,
          onTap: () => showMonthlyChallengeDetails(context, state),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: cardRadius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16.0,
                  offset: const Offset(0.0, 6.0),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: cardRadius,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    children: [
                      SizedBox(
                        height: imageHeight,
                        width: double.infinity,
                        child: thumbnailUrl.isNotEmpty
                            ? ProxiplayNetworkImage(
                                imageUrl: thumbnailUrl,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: const Color(0xFFEFF1F8),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.emoji_events_rounded,
                                  color: Color(0xFF3E61AE),
                                  size: 28.0,
                                ),
                              ),
                      ),
                      // Badge progression — meme style que GameCardWidget
                      // (bleu nuit, coin arrondi en bas a droite).
                      Positioned(
                        left: 0.0,
                        top: 0.0,
                        child: Container(
                          padding: AppStyles.gameCardBadgePadding,
                          decoration: const BoxDecoration(
                            color: AppStyles.gameCardBadgeColor,
                            borderRadius: BorderRadius.only(
                              bottomRight: Radius.circular(18.0),
                            ),
                          ),
                          child: Text(
                            badgeText,
                            style: theme.bodyMedium.override(
                              font: GoogleFonts.inter(fontWeight: FontWeight.w800),
                              color: Colors.white,
                              fontSize: AppStyles.gameCardBadgeSize,
                              letterSpacing: 0.0,
                            ),
                          ),
                        ),
                      ),
                      // Badge valeur du lot — meme style rose que
                      // GameCardWidget ; masque si aucune valeur.
                      if (prizeValueText.isNotEmpty)
                        Positioned(
                          left: 8.0,
                          top: imageHeight - 16.0,
                          child: Container(
                            padding: AppStyles.gameCardPriceBadgePadding,
                            decoration: BoxDecoration(
                              color: AppStyles.gameCardPriceBadgeColor,
                              borderRadius: BorderRadius.circular(16.0),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8.0,
                                  offset: const Offset(0.0, 2.0),
                                ),
                              ],
                            ),
                            child: Text(
                              prizeValueText,
                              style: theme.bodyMedium.override(
                                font: GoogleFonts.inter(fontWeight: FontWeight.w800),
                                color: Colors.white,
                                fontSize: AppStyles.gameCardPriceBadgeSize,
                                letterSpacing: 0.0,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      10.0,
                      prizeValueText.isNotEmpty ? 12.0 : 8.0,
                      10.0,
                      8.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          copy.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodyMedium.override(
                            font: GoogleFonts.inter(fontWeight: FontWeight.w700),
                            fontSize: AppStyles.gameCardTitleSize,
                            color: const Color(0xFF2C2F5B),
                            letterSpacing: 0.0,
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        Text(
                          copy.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodySmall.override(
                            font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                            color: const Color(0xFF5C627A),
                            fontSize: AppStyles.gameCardBodySize,
                            letterSpacing: 0.0,
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 1.0),
                              child: Icon(Icons.calendar_today_rounded,
                                  size: 14.0, color: Color(0xFF5C627A)),
                            ),
                            const SizedBox(width: 6.0),
                            Expanded(
                              child: Text(
                                dateText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.bodySmall.override(
                                  font: GoogleFonts.inter(fontWeight: FontWeight.w500),
                                  color: const Color(0xFF5C627A),
                                  fontSize: AppStyles.gameCardBodySize,
                                  letterSpacing: 0.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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
