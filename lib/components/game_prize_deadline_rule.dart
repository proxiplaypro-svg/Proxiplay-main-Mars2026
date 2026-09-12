import 'package:flutter/material.dart';

/// Uses only the usage deadline supplied by the already loaded game.
class GamePrizeDeadlineRule extends StatelessWidget {
  const GamePrizeDeadlineRule(
      {super.key, required this.deadline, required this.style});

  final DateTime? deadline;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final date = deadline;
    if (date == null) return const SizedBox.shrink();
    final formatted =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.calendar_today_outlined,
            size: 16, color: Color(0xFF6B7280)),
        const SizedBox(width: 8),
        Expanded(
            child: Text('Lot à utiliser avant le $formatted', style: style)),
      ]),
    );
  }
}
