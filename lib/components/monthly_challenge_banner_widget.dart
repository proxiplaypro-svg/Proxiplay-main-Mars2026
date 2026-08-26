import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/app_styles.dart';
import '/models/monthly_challenge_models.dart';
import '/widgets/proxiplay_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Logique de présentation partagée pour le défi mensuel (attendance /
/// merchant / fallback legacy restaurant) : copy compacte réutilisée par les
/// cartes "Jeux bonus" de la Home, et la feuille de détail ouverte au tap.
/// Pure UI — ne lit que [MonthlyChallengeStateViewModel], déjà normalisé côté
/// service/Function.

/// Meme bleu nuit que les pictogrammes des cartes de jeux classiques
/// (`game_card_widget.dart`), pour une identite visuelle cohérente.
const _navy = Color(0xFF26235C);

const _kShortMonths = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String formatChallengeShortDate(DateTime date, {bool withYear = false}) {
  final month = _kShortMonths[date.month - 1];
  return withYear ? '${date.day} $month ${date.year}' : '${date.day} $month';
}

String formatChallengePrizeValue(int value) {
  if (value <= 0) return '';
  return '$value €';
}

bool isMerchantChallenge(MonthlyChallengeStateViewModel state) {
  return state.type == 'merchant' || state.type == 'restaurant';
}

String defaultChallengePrizeLabel(
  MonthlyChallengeStateViewModel state,
  bool isMerchant,
) {
  return isMerchant && state.merchantName.isNotEmpty
      ? 'Lot chez ${state.merchantName}'
      : 'Lot à gagner';
}

/// Titre + sous-titre courts affichés sur la carte "Jeux bonus" — pure
/// présentation, aucune donnée nouvelle n'est introduite ici.
class ChallengeCardCopy {
  const ChallengeCardCopy({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}

ChallengeCardCopy buildChallengeCardCopy(MonthlyChallengeStateViewModel state) {
  final isMerchant = isMerchantChallenge(state);
  final title = state.title.isNotEmpty
      ? state.title
      : (isMerchant ? 'Commerçant du mois' : 'Défi du mois');

  final String subtitle;
  if (isMerchant && state.merchantName.isNotEmpty) {
    subtitle = state.merchantName;
  } else {
    subtitle = state.prizeTitle.isNotEmpty
        ? state.prizeTitle
        : defaultChallengePrizeLabel(state, isMerchant);
  }

  return ChallengeCardCopy(title: title, subtitle: subtitle);
}

Future<void> showMonthlyChallengeDetails(
  BuildContext context,
  MonthlyChallengeStateViewModel state,
) {
  final theme = FlutterFlowTheme.of(context);
  final thumbnailUrl =
      state.imageUrl.isNotEmpty ? state.imageUrl : state.merchantImageUrl;
  final prizeValueText = formatChallengePrizeValue(state.prizeValue);
  final hasMerchant = state.merchantName.isNotEmpty;
  // Le titre de l'ecran est le mecanisme (Bonus fidelite), pas le lot : le
  // lot n'est que la recompense, presentee plus bas dans le bloc dedie.
  final prizeTitle =
      state.prizeTitle.isNotEmpty ? state.prizeTitle : 'Un lot à gagner';
  final progress = state.targetDays <= 0
      ? 0.0
      : (state.activeDaysCount / state.targetDays).clamp(0.0, 1.0);
  final accent = state.qualified
      ? const Color(0xFF1D8348)
      : const Color(0xFFC26A1B);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      return DraggableScrollableSheet(
        initialChildSize: 0.68,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20.0, 10.0, 20.0, 24.0),
              children: [
                Center(
                  child: Container(
                    width: 36.0,
                    height: 4.0,
                    margin: const EdgeInsets.only(bottom: 14.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(999.0),
                    ),
                  ),
                ),
                if (thumbnailUrl.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14.0),
                    child: ProxiplayNetworkImage(
                      imageUrl: thumbnailUrl,
                      width: double.infinity,
                      height: 130.0,
                    ),
                  ),
                  const SizedBox(height: 14.0),
                ],
                Text(
                  'Bonus fidélité',
                  style: theme.titleMedium.override(
                    font: GoogleFonts.interTight(fontWeight: FontWeight.w800),
                    color: const Color(0xFF2C2F5B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6.0),
                Text(
                  'Jouez ${state.targetDays} jours différents pour participer au tirage.',
                  style: theme.bodySmall.override(
                    font: GoogleFonts.inter(fontWeight: FontWeight.w500),
                    color: const Color(0xFF5C627A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16.0),
                if (state.qualified) ...[
                  Text(
                    'Votre participation est validée 🎉',
                    style: theme.bodyMedium.override(
                      font: GoogleFonts.interTight(fontWeight: FontWeight.w700),
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                ] else ...[
                  Text(
                    '${state.activeDaysCount} / ${state.targetDays} jours',
                    style: theme.bodyMedium.override(
                      font: GoogleFonts.interTight(fontWeight: FontWeight.w800),
                      color: const Color(0xFF2C2F5B),
                      fontWeight: FontWeight.w800,
                    ),
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
                  const SizedBox(height: 8.0),
                  Text(
                    state.remainingDays > 0
                        ? 'Jouez encore ${state.remainingDays} jour${state.remainingDays > 1 ? 's' : ''} pour valider votre participation.'
                        : 'Encore une participation pour valider.',
                    style: theme.bodySmall.override(
                      font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      color: const Color(0xFF5C627A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                  decoration: BoxDecoration(
                    color: theme.primaryBackground,
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(Icons.card_giftcard, size: 18.0, color: _navy),
                          const SizedBox(width: 8.0),
                          Expanded(
                            child: Text(
                              prizeTitle,
                              style: theme.bodyMedium.override(
                                font: GoogleFonts.inter(fontWeight: FontWeight.w700),
                                color: const Color(0xFF2C2F5B),
                                fontWeight: FontWeight.w700,
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
                      if (state.prizeDescription.isNotEmpty) ...[
                        const SizedBox(height: 6.0),
                        Text(
                          state.prizeDescription,
                          style: theme.bodySmall.override(
                            font: GoogleFonts.inter(fontWeight: FontWeight.w500),
                            color: const Color(0xFF5C627A),
                            fontWeight: FontWeight.w500,
                            fontSize: 12.0,
                          ),
                        ),
                      ],
                      if (hasMerchant) ...[
                        const SizedBox(height: 4.0),
                        Text(
                          'Offert par ${state.merchantName}',
                          style: theme.bodySmall.override(
                            font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                            color: const Color(0xFF5C627A),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.0,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (state.description.isNotEmpty) ...[
                  const SizedBox(height: 18.0),
                  Text(
                    'Règlement',
                    style: theme.titleSmall.override(
                      font: GoogleFonts.interTight(fontWeight: FontWeight.w800),
                      color: const Color(0xFF2C2F5B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6.0),
                  Text(
                    state.description,
                    style: theme.bodyMedium.override(
                      font: GoogleFonts.inter(fontWeight: FontWeight.w500),
                      color: const Color(0xFF3A3F5C),
                      fontWeight: FontWeight.w500,
                      lineHeight: 1.45,
                    ),
                  ),
                ],
                if (state.drawDate != null) ...[
                  const SizedBox(height: 16.0),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 15.0, color: _navy),
                      const SizedBox(width: 8.0),
                      Text(
                        'Tirage le ${formatChallengeShortDate(state.drawDate!.toDate(), withYear: true)}',
                        style: theme.bodySmall.override(
                          font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                          color: const Color(0xFF5C627A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      );
    },
  );
}
