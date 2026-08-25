import '/flutter_flow/flutter_flow_theme.dart';
import '/models/monthly_challenge_models.dart';
import '/widgets/proxiplay_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

String _formatChallengePrizeValue(int value) {
  if (value <= 0) return '';
  return '$value €';
}

class MonthlyChallengeBannerWidget extends StatelessWidget {
  const MonthlyChallengeBannerWidget({
    super.key,
    required this.state,
  });

  final MonthlyChallengeStateViewModel state;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final progress = state.targetDays <= 0
        ? 0.0
        : (state.activeDaysCount / state.targetDays).clamp(0.0, 1.0);
    final accent = state.qualified
        ? const Color(0xFF1D8348)
        : const Color(0xFFC26A1B);
    final isMerchant = state.type == 'merchant' || state.type == 'restaurant';
    final defaultTitle = isMerchant ? 'Commerçant du mois' : 'Défi du mois';
    final defaultPrize = isMerchant && state.merchantName.isNotEmpty
        ? 'Lot chez ${state.merchantName}'
        : 'Lot à gagner';
    final thumbnailUrl =
        state.imageUrl.isNotEmpty ? state.imageUrl : state.merchantImageUrl;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(20.0),
        onTap: () => _showMonthlyChallengeDetails(context, state),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18.0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: state.qualified
                  ? const [Color(0xFFE7F7EE), Color(0xFFD1F0DE)]
                  : const [Color(0xFFFFF4E3), Color(0xFFFFE8C2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20.0),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18.0,
                offset: const Offset(0.0, 8.0),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14.0),
                    child: SizedBox(
                      width: 46.0,
                      height: 46.0,
                      child: thumbnailUrl.isNotEmpty
                          ? ProxiplayNetworkImage(
                              imageUrl: thumbnailUrl,
                              width: 46.0,
                              height: 46.0,
                            )
                          : Container(
                              color: Colors.white.withValues(alpha: 0.72),
                              alignment: Alignment.center,
                              child: Icon(
                                state.qualified
                                    ? Icons.verified_rounded
                                    : Icons.card_giftcard,
                                color: accent,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.qualified
                              ? 'Tu es qualifié !'
                              : (state.title.isNotEmpty
                                  ? state.title
                                  : defaultTitle),
                          style: theme.titleMedium.override(
                            font: GoogleFonts.interTight(
                              fontWeight: FontWeight.w800,
                              fontStyle: theme.titleMedium.fontStyle,
                            ),
                            color: const Color(0xFF2C2F5B),
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.w800,
                            fontStyle: theme.titleMedium.fontStyle,
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        Text(
                          state.prizeTitle.isNotEmpty
                              ? state.prizeTitle
                              : defaultPrize,
                          style: theme.bodyMedium.override(
                            font: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontStyle: theme.bodyMedium.fontStyle,
                            ),
                            color: const Color(0xFF2C2F5B),
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.w600,
                            fontStyle: theme.bodyMedium.fontStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: accent.withValues(alpha: 0.7),
                  ),
                ],
              ),
              const SizedBox(height: 14.0),
              if (!state.qualified) ...[
                Text(
                  '${state.activeDaysCount} / ${state.targetDays} jours',
                  style: theme.headlineSmall.override(
                    font: GoogleFonts.interTight(
                      fontWeight: FontWeight.w800,
                      fontStyle: theme.headlineSmall.fontStyle,
                    ),
                    color: const Color(0xFF2C2F5B),
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.w800,
                    fontStyle: theme.headlineSmall.fontStyle,
                  ),
                ),
                const SizedBox(height: 10.0),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999.0),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 12.0,
                    backgroundColor: Colors.white.withValues(alpha: 0.65),
                    color: accent,
                  ),
                ),
                const SizedBox(height: 12.0),
                Text(
                  state.remainingDays > 0
                      ? 'Plus que ${state.remainingDays} jour${state.remainingDays > 1 ? 's' : ''} actif${state.remainingDays > 1 ? 's' : ''} pour participer au tirage.'
                      : 'Encore une participation validée pour finaliser la qualification.',
                  style: theme.bodySmall.override(
                    font: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontStyle: theme.bodySmall.fontStyle,
                    ),
                    color: const Color(0xFF5C627A),
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.w600,
                    fontStyle: theme.bodySmall.fontStyle,
                  ),
                ),
              ] else ...[
                Text(
                  'Tu participes au tirage pour gagner ${state.prizeTitle.toLowerCase()}.',
                  style: theme.bodyMedium.override(
                    font: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontStyle: theme.bodyMedium.fontStyle,
                    ),
                    color: const Color(0xFF2C2F5B),
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.w600,
                    fontStyle: theme.bodyMedium.fontStyle,
                  ),
                ),
              ],
              if (state.drawDate != null) ...[
                const SizedBox(height: 12.0),
                Row(
                  children: [
                    Icon(
                      Icons.event_available_rounded,
                      size: 18.0,
                      color: accent,
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Text(
                        'Tirage le ${state.drawDate!.toDate().day}/${state.drawDate!.toDate().month}/${state.drawDate!.toDate().year}.',
                        style: theme.bodySmall.override(
                          font: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontStyle: theme.bodySmall.fontStyle,
                          ),
                          color: const Color(0xFF5C627A),
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w600,
                          fontStyle: theme.bodySmall.fontStyle,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Voir le règlement',
                    style: theme.bodySmall.override(
                      font: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontStyle: theme.bodySmall.fontStyle,
                      ),
                      color: accent,
                      letterSpacing: 0.0,
                      fontWeight: FontWeight.w700,
                      fontStyle: theme.bodySmall.fontStyle,
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 16.0, color: accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showMonthlyChallengeDetails(
  BuildContext context,
  MonthlyChallengeStateViewModel state,
) {
  final theme = FlutterFlowTheme.of(context);
  final isMerchant = state.type == 'merchant' || state.type == 'restaurant';
  final defaultTitle = isMerchant ? 'Commerçant du mois' : 'Défi du mois';
  final defaultPrize = isMerchant && state.merchantName.isNotEmpty
      ? 'Lot chez ${state.merchantName}'
      : 'Lot à gagner';
  final thumbnailUrl =
      state.imageUrl.isNotEmpty ? state.imageUrl : state.merchantImageUrl;
  final prizeValueText = _formatChallengePrizeValue(state.prizeValue);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      return DraggableScrollableSheet(
        initialChildSize: 0.7,
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
              padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 28.0),
              children: [
                Center(
                  child: Container(
                    width: 40.0,
                    height: 4.0,
                    margin: const EdgeInsets.only(bottom: 16.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(999.0),
                    ),
                  ),
                ),
                if (thumbnailUrl.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16.0),
                    child: ProxiplayNetworkImage(
                      imageUrl: thumbnailUrl,
                      width: double.infinity,
                      height: 160.0,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                ],
                Text(
                  state.title.isNotEmpty ? state.title : defaultTitle,
                  style: theme.headlineSmall.override(
                    font: GoogleFonts.interTight(fontWeight: FontWeight.w800),
                    color: const Color(0xFF2C2F5B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12.0),
                Container(
                  padding: const EdgeInsets.all(14.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4E3),
                    borderRadius: BorderRadius.circular(14.0),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.card_giftcard, color: Color(0xFFC26A1B)),
                      const SizedBox(width: 10.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.prizeTitle.isNotEmpty
                                  ? state.prizeTitle
                                  : defaultPrize,
                              style: theme.bodyLarge.override(
                                font: GoogleFonts.inter(fontWeight: FontWeight.w700),
                                color: const Color(0xFF2C2F5B),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (prizeValueText.isNotEmpty) ...[
                              const SizedBox(height: 2.0),
                              Text(
                                'Valeur : $prizeValueText',
                                style: theme.bodySmall.override(
                                  font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                                  color: const Color(0xFF5C627A),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (state.prizeDescription.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(
                                state.prizeDescription,
                                style: theme.bodySmall.override(
                                  font: GoogleFonts.inter(fontWeight: FontWeight.w500),
                                  color: const Color(0xFF5C627A),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.description.isNotEmpty) ...[
                  const SizedBox(height: 20.0),
                  Text(
                    'Règlement',
                    style: theme.titleSmall.override(
                      font: GoogleFonts.interTight(fontWeight: FontWeight.w800),
                      color: const Color(0xFF2C2F5B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    state.description,
                    style: theme.bodyMedium.override(
                      font: GoogleFonts.inter(fontWeight: FontWeight.w500),
                      color: const Color(0xFF3A3F5C),
                      fontWeight: FontWeight.w500,
                      lineHeight: 1.4,
                    ),
                  ),
                ],
                if (state.drawDate != null) ...[
                  const SizedBox(height: 20.0),
                  Row(
                    children: [
                      const Icon(Icons.event_available_rounded,
                          size: 18.0, color: Color(0xFFC26A1B)),
                      const SizedBox(width: 8.0),
                      Text(
                        'Tirage au sort le ${state.drawDate!.toDate().day}/${state.drawDate!.toDate().month}/${state.drawDate!.toDate().year}.',
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
