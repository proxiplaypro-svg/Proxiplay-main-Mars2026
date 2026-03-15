import '/backend/backend.dart';
import '/widgets/home/home_empty_games_state_widget.dart';
import 'package:flutter/material.dart';

class HomeSearchResultsList extends StatelessWidget {
  const HomeSearchResultsList({
    super.key,
    required this.games,
    required this.itemBuilder,
  });

  final List<GamesRecord> games;
  final Widget Function(BuildContext context, GamesRecord game) itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (games.isEmpty) {
      return const HomeEmptyGamesState(
        title: 'Liste vide',
        description: 'Aucun jeux pour le moment',
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      scrollDirection: Axis.vertical,
      itemCount: games.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10.0),
      itemBuilder: (context, index) => itemBuilder(context, games[index]),
    );
  }
}
