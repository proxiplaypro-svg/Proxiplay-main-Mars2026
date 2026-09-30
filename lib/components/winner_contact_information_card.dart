import '/components/winner_email_text.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/utils/prize_winner_contact.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum WinnerContactLoadState { loading, unavailable, resolved }

WinnerContactLoadState winnerContactLoadState({
  required ConnectionState connectionState,
  required bool hasError,
  required PrizeWinnerContact? contact,
}) {
  if (connectionState != ConnectionState.done) {
    return WinnerContactLoadState.loading;
  }
  if (hasError || contact == null) {
    return WinnerContactLoadState.unavailable;
  }
  return WinnerContactLoadState.resolved;
}

/// Keeps loading and failure distinct from a completed contact response.
/// A dash is only a value for a field which was genuinely absent.
class WinnerContactInformationCard extends StatelessWidget {
  const WinnerContactInformationCard({
    super.key,
    required this.contactFuture,
    required this.onRetry,
  });

  final Future<PrizeWinnerContact?> contactFuture;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => FutureBuilder<PrizeWinnerContact?>(
        future: contactFuture,
        builder: (context, snapshot) {
          final state = winnerContactLoadState(
            connectionState: snapshot.connectionState,
            hasError: snapshot.hasError,
            contact: snapshot.data,
          );
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context)
                  .primaryBackground
                  .withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Informations gagnant',
                  style: FlutterFlowTheme.of(context).bodyMedium.override(
                        font: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8.0),
                if (state == WinnerContactLoadState.loading)
                  const Row(children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Chargement des informations…'),
                  ])
                else if (state == WinnerContactLoadState.unavailable)
                  Row(children: [
                    const Expanded(
                      child: Text('Informations du gagnant indisponibles'),
                    ),
                    TextButton(
                        onPressed: onRetry, child: const Text('Réessayer')),
                  ])
                else
                  _WinnerContactFields(contact: snapshot.data!),
              ],
            ),
          );
        },
      );
}

class _WinnerContactFields extends StatelessWidget {
  const _WinnerContactFields({required this.contact});

  final PrizeWinnerContact contact;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _WinnerInfoRow('NOM', contact.lastName),
          const SizedBox(height: 6.0),
          _WinnerInfoRow('PRENOM', contact.firstName),
          const SizedBox(height: 6.0),
          _WinnerInfoRow('VILLE', contact.city),
          const SizedBox(height: 6.0),
          _WinnerInfoRow('MAIL', contact.email),
          const SizedBox(height: 6.0),
          _WinnerInfoRow('Téléphone', contact.phoneNumber),
        ],
      );
}

class _WinnerInfoRow extends StatelessWidget {
  const _WinnerInfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isNotEmpty ? value.trim() : '—';
    final style = GoogleFonts.inter(
      textStyle: FlutterFlowTheme.of(context).bodySmall,
      letterSpacing: 0,
    );
    final caption = Text(
      '$label :',
      style: style.copyWith(
        color: FlutterFlowTheme.of(context).secondaryText,
        fontWeight: FontWeight.w700,
      ),
    );
    if (label == 'MAIL') {
      return LayoutBuilder(builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: displayValue, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final fitsRow = painter.width <= constraints.maxWidth - 88;
        painter.dispose();
        final email = WinnerEmailText(email: displayValue, style: style);
        return fitsRow
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 88, child: caption),
                Expanded(child: email),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                caption,
                const SizedBox(height: 4),
                email,
              ]);
      });
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 88, child: caption),
      Expanded(child: Text(displayValue, style: style)),
    ]);
  }
}
