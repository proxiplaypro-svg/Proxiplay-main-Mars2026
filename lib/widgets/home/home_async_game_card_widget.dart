import '/backend/backend.dart';
import '/components/game_card_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';

class HomeAsyncGameCard extends StatelessWidget {
  const HomeAsyncGameCard({
    super.key,
    required this.game,
    required this.onTap,
    this.isHighlighted = false,
  });

  final GamesRecord game;
  final Future<void> Function() onTap;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EnseignesRecord>(
      future: EnseignesRecord.getDocumentOnce(game.enseigneId!),
      builder: (context, enseigneSnapshot) {
        final enseigne = enseigneSnapshot.data;
        return GameCardWidget(
          title: game.name,
          imageUrl: game.photo,
          storeName: enseigne?.name ?? '',
          city: enseigne?.city ?? '',
          isHighlighted: isHighlighted,
          prizeText: game.prizeValue == 0
              ? 'Gains instantan\u00E9s'
              : compactEuroAmount(game.prizeValue),
          endDateText: game.endDate != null
              ? "Jusqu'au : ${dateTimeFormat('d/M/y', game.endDate, locale: FFLocalizations.of(context).languageCode)}"
              : "Jusqu'au : -",
          onTap: () async {
            await onTap();
          },
        );
      },
    );
  }
}
