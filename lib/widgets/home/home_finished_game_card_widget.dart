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
    final hasSecondaryRewards = game.secondaryPrizes.isNotEmpty ||
        game.secondaryPrizeDescription.trim().isNotEmpty;
    final enseigneFuture = game.enseigneId != null
        ? EnseignesRecord.getDocumentOnce(game.enseigneId!)
        : Future<EnseignesRecord?>.value(null);
    final winnerFuture = game.mainPrizeWinner != null
        ? UsersRecord.getDocumentOnce(game.mainPrizeWinner!)
        : Future<UsersRecord?>.value(null);

    return FutureBuilder<EnseignesRecord?>(
      future: enseigneFuture,
      builder: (context, enseigneSnapshot) {
        final enseigne = enseigneSnapshot.data;
        return FutureBuilder<UsersRecord?>(
          future: winnerFuture,
          builder: (context, winnerSnapshot) {
            final winner = winnerSnapshot.data;
            final firstName = (winner?.firstName ?? '').trim();
            final city = (winner?.city ?? '').trim();
            final winnerIdentity =
                city.isNotEmpty ? '$firstName - $city' : firstName;
            final winnerLabel = winnerIdentity.isNotEmpty
                ? 'Gagn\u00E9 par $winnerIdentity'
                : '';
            final finishedInfoText = hasSecondaryRewards
                ? 'Lots secondaires attribués'
                : 'Jeu terminé';
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
              winnerText: winnerLabel.isEmpty ? null : winnerLabel,
              winnerMaxLines: 1,
              isFinished: true,
              finishedInfoText: finishedInfoText,
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
