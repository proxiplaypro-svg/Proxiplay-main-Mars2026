import 'package:flutter/material.dart';
import '/backend/backend.dart';

const gainInk = Color(0xFF2B285F);
const gainPink = Color(0xFFA0134D);
const gainPaper = Color(0xFFFEFFFE);

/// Presentation only. All data and actions come from the existing lots screen.
class PlayerGainCard extends StatelessWidget {
  const PlayerGainCard(
      {super.key,
      required this.prize,
      required this.onOpen,
      required this.onDelete,
      this.deleting = false});
  final PrizesRecord prize;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    final available = prize.isAvailable;
    final status =
        prize.claimed ? 'Retiré' : (prize.isExpired ? 'Expiré' : 'À récupérer');
    final deadline = prize.usageDeadline;
    final conditions = prize.description.trim();
    Widget badge(String text, IconData? icon, {bool muted = false}) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
              color: muted ? const Color(0xFFF3F0F5) : const Color(0xFFFCEAF2),
              borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: muted ? gainInk : gainPink),
              const SizedBox(width: 5),
            ],
            Flexible(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: muted ? gainInk : gainPink))),
          ]),
        );
    final details =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        badge(status, available ? null : Icons.check_circle_outline,
            muted: !available),
        if (deadline != null)
          badge(
              '${available ? 'À récupérer avant le' : 'Échéance :'} ${deadline.day.toString().padLeft(2, '0')}/${deadline.month.toString().padLeft(2, '0')}/${deadline.year}',
              Icons.schedule_rounded,
              muted: !available),
      ]),
      const SizedBox(height: 10),
      Text(prize.name.trim().isEmpty ? 'Lot gagné' : prize.name.trim(),
          style: const TextStyle(
              fontSize: 18,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: gainInk)),
      if (prize.enseigneName.trim().isNotEmpty) ...[
        const SizedBox(height: 5),
        Text(prize.enseigneName.trim(),
            style: const TextStyle(fontSize: 14, color: Color(0xFF656171))),
      ],
    ]);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: gainPaper,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF0ECF1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        details,
        const SizedBox(height: 14),
        SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.qr_code_rounded, size: 20),
              label: const Text('Voir mon lot', textAlign: TextAlign.center),
              style: FilledButton.styleFrom(
                  backgroundColor: gainPink,
                  foregroundColor: gainPaper,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
            )),
        Row(children: [
          if (conditions.isNotEmpty)
            Expanded(
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                        onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            backgroundColor: gainPaper,
                            builder: (context) => SafeArea(
                                child: SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                        24, 8, 24, 32),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('Conditions',
                                              style: TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w700,
                                                  color: gainInk)),
                                          const SizedBox(height: 12),
                                          SelectableText(conditions,
                                              style: const TextStyle(
                                                  color: gainInk, height: 1.5)),
                                        ])))),
                        style: TextButton.styleFrom(foregroundColor: gainInk),
                        child: const Text('Conditions ›')))),
          if (conditions.isEmpty) const Spacer(),
          IconButton(
              onPressed: deleting ? null : onDelete,
              tooltip: 'Supprimer de ma liste',
              icon: deleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline_rounded,
                      color: gainInk, size: 20)),
        ]),
      ]),
    );
  }
}
