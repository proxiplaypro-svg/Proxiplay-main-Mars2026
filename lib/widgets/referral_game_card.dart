import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '/components/game_card_widget.dart';
import '/flutter_flow/app_styles.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';

/// Carte du jeu de parrainage actif, inseree dans la liste des jeux "A la
/// une". referral_games est une collection separee de games (pas de
/// GamesRecord genere), donc ce widget lit Firestore directement plutot que
/// de forcer une fausse donnee dans le systeme de jeux existant.
class ReferralGameCard extends StatelessWidget {
  const ReferralGameCard({super.key, this.width, this.height});

  final double? width;
  final double? height;

  String _prizeBadgeText(Map<String, dynamic> gameData) {
    final rawValue = gameData['prize_value'] ?? gameData['prizeValue'];
    final prizeValue = rawValue is num
        ? rawValue.toDouble()
        : double.tryParse(rawValue?.toString().replaceAll(',', '.') ?? '');

    if (prizeValue != null && prizeValue > 0) {
      final decimals = prizeValue == prizeValue.roundToDouble()
          ? ''
          : prizeValue.toStringAsFixed(2).split('.').last.replaceFirst(
                RegExp(r'0+$'),
                '',
              );
      final euros = prizeValue.truncate();
      return decimals.isEmpty ? '$euros \u20AC' : '$euros,$decimals \u20AC';
    }

    final description = (gameData['prize_description'] as String?)?.trim();
    return description?.isNotEmpty == true ? description! : 'Lot \u00E0 gagner';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('referral_games')
          .where('status', isEqualTo: 'active')
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final gameDoc = snapshot.data!.docs.first;
        final gameData = gameDoc.data();
        final endDate = (gameData['end_date'] as Timestamp?)?.toDate();

        return GameCardWidget(
          title: (gameData['title'] as String?)?.trim().isNotEmpty == true
              ? gameData['title'] as String
              : 'Jeu de parrainage',
          imageUrl: (gameData['image_url'] as String?) ?? '',
          storeName: 'Programme de parrainage',
          city: '',
          prizeText: _prizeBadgeText(gameData),
          endDateText: endDate != null
              ? "Jusqu'au : ${dateTimeFormat('d/M/y', endDate, locale: FFLocalizations.of(context).languageCode)}"
              : "Jusqu'au : -",
          badgeText: 'Parrainage',
          width: width ?? AppStyles.gameCardWidth,
          height: height,
          onTap: () => context.pushNamed(
            ReferralGameDetailJoueurPageWidget.routeName,
            queryParameters: {'gameId': gameDoc.id},
            extra: <String, dynamic>{'gameId': gameDoc.id},
          ),
        );
      },
    );
  }
}
