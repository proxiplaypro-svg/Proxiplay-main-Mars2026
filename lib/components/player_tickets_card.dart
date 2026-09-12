import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Presentation only; the game page retains ticket counting and date formatting.
class PlayerTicketsCard extends StatelessWidget {
  const PlayerTicketsCard({
    super.key,
    required this.title,
    required this.chances,
    required this.bodyStyle,
  });

  final String title;
  final String chances;
  final TextStyle bodyStyle;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Same ticket glyph as the Home's TicketBadgeWidget.
                const Text('🎫', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2B285F),
                      )),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(chances,
                style: bodyStyle.copyWith(color: const Color(0xFF2B285F))),
            const SizedBox(height: 6),
            Text('Rejouez chaque jour pour augmenter vos chances',
                style: bodyStyle.copyWith(
                  fontStyle: FontStyle.italic,
                  color: const Color(0xFF6B7280),
                )),
          ],
        ),
      );
}
