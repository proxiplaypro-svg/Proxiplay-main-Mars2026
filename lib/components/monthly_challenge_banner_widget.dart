import '/flutter_flow/flutter_flow_theme.dart';
import '/models/monthly_challenge_models.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

    return Container(
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
              Container(
                width: 46.0,
                height: 46.0,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(14.0),
                ),
                child: Icon(
                  state.qualified ? Icons.verified_rounded : Icons.card_giftcard,
                  color: accent,
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
                              : 'Défi mensuel Proxiplay'),
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
                          : 'Lot à gagner',
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
        ],
      ),
    );
  }
}
