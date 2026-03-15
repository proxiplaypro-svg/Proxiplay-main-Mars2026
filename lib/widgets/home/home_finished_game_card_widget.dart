import '/backend/backend.dart';
import '/components/game_card_widget.dart';
import '/flutter_flow/app_styles.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';

class HomeFinishedGameCard extends StatelessWidget {
  const HomeFinishedGameCard({
    super.key,
    required this.game,
    required this.onTap,
  });

  final GamesRecord game;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EnseignesRecord>(
      future: EnseignesRecord.getDocumentOnce(game.enseigneId!),
      builder: (context, enseigneSnapshot) {
        final enseigne = enseigneSnapshot.data;
        return FutureBuilder<UsersRecord>(
          future: UsersRecord.getDocumentOnce(game.mainPrizeWinner!),
          builder: (context, winnerSnapshot) {
            final winner = winnerSnapshot.data;
            final firstName = (winner?.firstName ?? '').trim();
            final city = (winner?.city ?? '').trim();
            final winnerIdentity =
                city.isNotEmpty ? '$firstName - $city' : firstName;
            final winnerLabel = winnerIdentity.isNotEmpty
                ? 'Gagn\u00E9 par $winnerIdentity'
                : 'Gagnant annonc\u00E9';
            return GameCardWidget(
              title: game.name,
              imageUrl: game.photo,
              storeName: enseigne?.name ?? '',
              city: enseigne?.city ?? '',
              prizeText: game.prizeValue == 0
                  ? 'Gains instantan\u00E9s'
                  : '${game.prizeValue} \u20AC',
              endDateText: game.endDate != null
                  ? "Jusqu'au : ${dateTimeFormat('d/M/y', game.endDate, locale: FFLocalizations.of(context).languageCode)}"
                  : "Jusqu'au : -",
              winnerText: winnerLabel,
              winnerMaxLines: 1,
              isFinished: true,
              fitContent: false,
              height: AppStyles.finishedGameListHeight,
              imageHeight: AppStyles.finishedGameImageHeight,
              onTap: () async {
                await onTap();
              },
            );
          },
        );
      },
    );
  }
}
