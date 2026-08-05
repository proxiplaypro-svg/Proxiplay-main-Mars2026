import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '/auth/firebase_auth/auth_util.dart';
import '/components/game_card_widget.dart';
import '/flutter_flow/app_styles.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';

/// Carte du jeu de parrainage actif, inseree dans la liste des jeux "A la
/// une". referral_games est une collection separee de games (pas de
/// GamesRecord genere), donc ce widget lit Firestore directement plutot que
/// de forcer une fausse donnee dans le systeme de jeux existant.
class ReferralGameCard extends StatelessWidget {
  const ReferralGameCard({super.key, this.width, this.height});

  final double? width;
  final double? height;

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
          imageUrl: '',
          storeName: 'Programme de parrainage',
          city: '',
          prizeText: (gameData['prize_description'] as String?) ?? '',
          endDateText: endDate != null
              ? "Jusqu'au : ${dateTimeFormat('d/M/y', endDate, locale: FFLocalizations.of(context).languageCode)}"
              : "Jusqu'au : -",
          badgeText: 'Parrainage',
          width: width ?? AppStyles.gameCardWidth,
          height: height,
          onTap: () => _showDetails(context, gameDoc.id, gameData),
        );
      },
    );
  }

  void _showDetails(
    BuildContext context,
    String gameId,
    Map<String, dynamic> gameData,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ReferralGameDetailsSheet(
        gameId: gameId,
        title: (gameData['title'] as String?) ?? 'Jeu de parrainage',
        description: (gameData['description'] as String?) ?? '',
        prizeDescription: (gameData['prize_description'] as String?) ?? '',
        endDate: (gameData['end_date'] as Timestamp?)?.toDate(),
      ),
    );
  }
}

class _ReferralGameDetailsSheet extends StatelessWidget {
  const _ReferralGameDetailsSheet({
    required this.gameId,
    required this.title,
    required this.description,
    required this.prizeDescription,
    required this.endDate,
  });

  final String gameId;
  final String title;
  final String description;
  final String prizeDescription;
  final DateTime? endDate;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final uid = currentUserUid;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        decoration: BoxDecoration(
          color: theme.primaryBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.headlineSmall,
            ),
            const SizedBox(height: 8),
            if (description.isNotEmpty) ...[
              Text(description, style: theme.bodyMedium),
              const SizedBox(height: 12),
            ],
            if (prizeDescription.isNotEmpty) ...[
              Text('Lot a gagner', style: theme.labelMedium),
              const SizedBox(height: 4),
              Text(prizeDescription, style: theme.bodyLarge),
              const SizedBox(height: 12),
            ],
            if (endDate != null) ...[
              Text(
                "Tirage au sort le ${dateTimeFormat('d/M/y', endDate, locale: FFLocalizations.of(context).languageCode)}",
                style: theme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
            uid.isEmpty
                ? const SizedBox.shrink()
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('referral_games')
                        .doc(gameId)
                        .collection('entries')
                        .where('inviter_uid', isEqualTo: uid)
                        .snapshots(),
                    builder: (context, ticketSnapshot) {
                      final ticketCount =
                          ticketSnapshot.data?.docs.length ?? 0;
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.secondaryBackground,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Vos tickets', style: theme.bodyMedium),
                            Text(
                              '$ticketCount',
                              style: theme.headlineSmall,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            const SizedBox(height: 8),
            Text(
              'Chaque parrainage valide (votre filleul cree son compte) vous donne un ticket supplementaire, sans limite.',
              style: theme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
