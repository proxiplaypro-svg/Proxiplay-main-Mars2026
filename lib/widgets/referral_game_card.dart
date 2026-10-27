import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/backend.dart';
import '/components/game_card_widget.dart';
import '/flutter_flow/app_styles.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/widgets/proxiplay_network_image.dart';

/// Carte du jeu de parrainage actif (rubrique "LE JEU DU PARRAINAGE" de
/// l'accueil). referral_games est une collection separee de games (pas de
/// GamesRecord genere), donc ce widget lit Firestore directement plutot que
/// de forcer une fausse donnee dans le systeme de jeux existant.
class ReferralGameCard extends StatelessWidget {
  const ReferralGameCard({
    super.key,
    required this.gameSnapshot,
    this.width,
    this.height,
    this.wide = false,
  });

  /// Snapshot already observed by Home. Keeping the Firestore listener at the
  /// section level avoids subscribing twice to the same active referral game.
  final QueryDocumentSnapshot<Map<String, dynamic>> gameSnapshot;
  final double? width;
  final double? height;

  /// Wide horizontal banner, same look as the "JEUX A SCANNER" cards of the
  /// Home (_buildAnimationCard): cover image, dark gradient, white texts.
  final bool wide;

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
    final gameDoc = gameSnapshot;
    final gameData = gameDoc.data();
    final endDate = (gameData['end_date'] as Timestamp?)?.toDate();
    final title = (gameData['title'] as String?)?.trim().isNotEmpty == true
        ? gameData['title'] as String
        : 'Jeu de parrainage';
    final imageUrl = (gameData['image_url'] as String?) ?? '';
    final prizeText = _prizeBadgeText(gameData);
    final endDateText = endDate != null
        ? "Jusqu'au : ${dateTimeFormat('d/M/y', endDate, locale: FFLocalizations.of(context).languageCode)}"
        : "Jusqu'au : -";
    void onTap() => context.pushNamed(
          ReferralGameDetailJoueurPageWidget.routeName,
          queryParameters: {'gameId': gameDoc.id},
          extra: <String, dynamic>{'gameId': gameDoc.id},
        );

    // Commercant partenaire optionnel : meme convention de champ que
    // les jeux classiques (`enseigne_id`, voir GamesRecord). Aucun jeu
    // de parrainage existant n'a ce champ renseigne aujourd'hui (le
    // formulaire admin actuel ne le propose pas encore) — la carte
    // bascule alors automatiquement sur la bulle generique "Programme
    // de parrainage", sans badge "Parrainage" (redondant avec ce
    // contexte, deja affiche sur la fiche detaillee).
    final partnerEnseigneRef = gameData['enseigne_id'] as DocumentReference?;

    if (wide) {
      Widget banner(String programLabel) => _buildWideCard(
            context,
            title: title,
            imageUrl: imageUrl,
            prizeText: prizeText,
            programLabel: programLabel,
            endDate: endDate,
            onTap: onTap,
          );
      if (partnerEnseigneRef == null) {
        return banner('Programme de parrainage');
      }
      return FutureBuilder<EnseignesRecord>(
        future: EnseignesRecord.getDocumentOnce(partnerEnseigneRef),
        builder: (context, enseigneSnapshot) {
          final partnerName = enseigneSnapshot.data?.name.trim() ?? '';
          return banner(partnerName.isNotEmpty
              ? 'Offert par $partnerName'
              : 'Programme de parrainage');
        },
      );
    }

    if (partnerEnseigneRef == null) {
      return GameCardWidget(
        title: title,
        imageUrl: imageUrl,
        storeName: 'Programme de parrainage',
        city: '',
        prizeText: prizeText,
        endDateText: endDateText,
        showOfferedByLabel: false,
        width: width ?? AppStyles.gameCardWidth,
        height: height,
        onTap: onTap,
      );
    }

    // Avec partenaire : presentation strictement identique a celle
    // d'un jeu classique (photo/logo + "Offert par" + nom).
    return FutureBuilder<EnseignesRecord>(
      future: EnseignesRecord.getDocumentOnce(partnerEnseigneRef),
      builder: (context, enseigneSnapshot) {
        final partnerName = enseigneSnapshot.data?.name.trim() ?? '';
        return GameCardWidget(
          title: title,
          imageUrl: imageUrl,
          storeName:
              partnerName.isNotEmpty ? partnerName : 'Programme de parrainage',
          city: '',
          prizeText: prizeText,
          endDateText: endDateText,
          enseigneRef: partnerName.isNotEmpty ? partnerEnseigneRef : null,
          showOfferedByLabel: partnerName.isNotEmpty,
          width: width ?? AppStyles.gameCardWidth,
          height: height,
          onTap: onTap,
        );
      },
    );
  }

  Widget _buildWideCard(
    BuildContext context, {
    required String title,
    required String imageUrl,
    required String prizeText,
    required String programLabel,
    required DateTime? endDate,
    required VoidCallback onTap,
  }) {
    final theme = FlutterFlowTheme.of(context);
    final dateText = endDate != null
        ? "Jusqu'au ${dateTimeFormat('dd/MM', endDate, locale: FFLocalizations.of(context).languageCode)}"
        : "Jusqu'au -";
    return Semantics(
      button: true,
      label: '$title, $prizeText, $programLabel, $dateText',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('referral-game-wide-card'),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18.0),
          child: SizedBox(
            width: width ?? double.infinity,
            height: height ?? 160.0,
            child: Stack(
              fit: StackFit.expand,
              children: [
                imageUrl.isNotEmpty
                    ? ProxiplayNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover)
                    : Container(color: theme.fieldBg),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.04),
                        Colors.black.withValues(alpha: 0.72),
                      ],
                      stops: const [0.45, 1.0],
                    ),
                  ),
                ),
                // Prize: same pill as the other game cards.
                PositionedDirectional(
                  top: 10.0,
                  start: 10.0,
                  end: 10.0,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      padding: AppStyles.gameCardPriceBadgePadding,
                      decoration: BoxDecoration(
                        color: AppStyles.gameCardPriceBadgeColor,
                        borderRadius: BorderRadius.circular(16.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8.0,
                            offset: const Offset(0.0, 2.0),
                          ),
                        ],
                      ),
                      child: Text(
                        prizeText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyMedium.override(
                          font: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontStyle: theme.bodyMedium.fontStyle,
                          ),
                          color: Colors.white,
                          fontSize: AppStyles.gameCardPriceBadgeSize,
                          letterSpacing: 0.0,
                        ),
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 14.0,
                  end: 14.0,
                  bottom: 12.0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.titleMedium.override(
                          font: GoogleFonts.interTight(
                            fontWeight: FontWeight.w700,
                            fontStyle: theme.titleMedium.fontStyle,
                          ),
                          color: Colors.white,
                          letterSpacing: 0.0,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Row(
                        children: [
                          Icon(
                            Icons.storefront_outlined,
                            size: 14.0,
                            color: Colors.white.withValues(alpha: 0.92),
                          ),
                          const SizedBox(width: 6.0),
                          Expanded(
                            child: Text(
                              '$programLabel · $dateText',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodySmall.override(
                                font: GoogleFonts.inter(
                                  fontWeight: FontWeight.w500,
                                  fontStyle: theme.bodySmall.fontStyle,
                                ),
                                color: Colors.white.withValues(alpha: 0.92),
                                letterSpacing: 0.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
