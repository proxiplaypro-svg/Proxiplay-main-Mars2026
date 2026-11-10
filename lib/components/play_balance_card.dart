import 'package:flutter/material.dart';

import '/utils/play_balance.dart';

/// Solde de parties du joueur : parties du jour et reserve bonus (1.1.4).
class PlayBalanceCard extends StatelessWidget {
  const PlayBalanceCard({
    super.key,
    required this.dailyRemaining,
    required this.bonusPart,
  });

  final int dailyRemaining;
  final int bonusPart;

  @override
  Widget build(BuildContext context) {
    final daily = dailyRemaining < 0 ? 0 : dailyRemaining;
    final bonus = normalizeBonusPart(bonusPart);
    final dailyLabel =
        daily <= 1 ? '$daily partie du jour' : '$daily parties du jour';
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Mes parties : $dailyLabel, ${bonusBalanceTitle(bonus)}. '
          '$kBonusBalanceExplanation',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: const Color(0xFFE6E8F5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40.0,
              height: 40.0,
              decoration: const BoxDecoration(
                color: Color(0xFFF5F6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.casino_outlined,
                  color: Color(0xFF2D2A72), size: 22.0),
            ),
            const SizedBox(width: 12.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mes parties',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF2D2A72),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4.0),
                  Text('$dailyLabel · ${bonusBalanceTitle(bonus)}'),
                  const SizedBox(height: 6.0),
                  Text(
                    kBonusBalanceExplanation,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: const Color(0xFF6B6F8A)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
