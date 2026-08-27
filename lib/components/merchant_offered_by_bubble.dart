import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/widgets/proxiplay_network_image.dart';

/// Petite bulle "Offert par [enseigne]" avec photo ronde du commerçant,
/// destinée à chevaucher le bas de l'image principale d'une carte de jeu.
/// Réutilisable sur toutes les cartes de jeux (Nouveautés, Jeux actifs,
/// Jeux terminés) : `GameCard`/`GameCardWidget` la place dans son propre
/// `Stack`, ce composant se contente de savoir comment se dessiner et
/// comment récupérer sa propre photo.
///
/// Photo utilisée : la première image de la sous-collection Firestore
/// `enseignes/{id}/images` (même source et même helper
/// `queryImagesRecordOnce(parent: ..., singleRecord: true)` que sur la
/// page enseigne joueur et la page "Mes enseignes" côté commerçant —
/// aucun nouveau champ, aucun nouveau logo demandé). Récupérée une seule
/// fois par instance (dans `initState`), pas de re-requête à chaque
/// reconstruction du widget parent.
class MerchantOfferedByBubble extends StatefulWidget {
  const MerchantOfferedByBubble({
    super.key,
    required this.merchantName,
    this.enseigneRef,
  });

  final String merchantName;
  final DocumentReference? enseigneRef;

  /// Diametre de la photo ronde. Sert aussi de reference pour le
  /// chevauchement avec l'image (le centre de la photo est aligne sur le
  /// bord bas de l'image, voir `GameCard`).
  static const double avatarSize = 40.0;

  // Le nom du commerçant peut occuper jusqu'a 2 lignes (voir build()) : le
  // cartouche reserve toujours la meme hauteur, qu'il tienne sur 1 ou 2
  // lignes, pour que toutes les cartes d'une meme rangee restent alignees
  // (pas de "grille en escalier"). Il est donc desormais l'element le plus
  // haut de la bulle, devant la photo.
  static const double _nameLineHeight = 18.4; // 16px * 1.15
  static const double _capsuleHeight = 56.0;

  /// Hauteur totale reservee par le composant. Utilisee par `GameCard` pour
  /// calculer le chevauchement avec l'image et l'espace a reserver sous le
  /// titre — c'est toujours le cartouche qui domine desormais.
  static const double totalHeight = _capsuleHeight;

  @override
  State<MerchantOfferedByBubble> createState() =>
      _MerchantOfferedByBubbleState();
}

class _MerchantOfferedByBubbleState extends State<MerchantOfferedByBubble> {
  Future<List<ImagesRecord>>? _photoFuture;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  @override
  void didUpdateWidget(covariant MerchantOfferedByBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enseigneRef?.path != widget.enseigneRef?.path) {
      _loadPhoto();
    }
  }

  void _loadPhoto() {
    final ref = widget.enseigneRef;
    // Pas de commerçant identifié : aucune requête, le fallback visuel
    // s'affichera directement (jamais d'echec silencieux qui casse la carte).
    _photoFuture = ref == null
        ? Future.value(const <ImagesRecord>[])
        : queryImagesRecordOnce(parent: ref, singleRecord: true);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.merchantName.trim();
    if (name.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = FlutterFlowTheme.of(context);
    const avatarSize = MerchantOfferedByBubble.avatarSize;
    const capsuleHeight = MerchantOfferedByBubble._capsuleHeight;
    const capsuleLeftInset = avatarSize / 2;
    // L'un ou l'autre peut devenir le plus haut selon les futurs reglages :
    // on calcule la bulle a partir des deux plutot que de figer une valeur.
    const bubbleHeight = capsuleHeight > avatarSize ? capsuleHeight : avatarSize;

    return SizedBox(
      height: bubbleHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: capsuleLeftInset,
            right: 0.0,
            top: (bubbleHeight - capsuleHeight) / 2,
            height: capsuleHeight,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                capsuleLeftInset + 8.0,
                4.0,
                12.0,
                4.0,
              ),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8.0,
                    offset: const Offset(0.0, 2.0),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Offert par',
                    style: theme.bodySmall.override(
                      font: GoogleFonts.inter(fontWeight: FontWeight.w500),
                      color: const Color(0xFF8A8A8A),
                      fontWeight: FontWeight.w500,
                      fontSize: 9.0,
                      lineHeight: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2.0),
                  // Hauteur toujours reservee pour 2 lignes (meme si le nom
                  // tient sur 1 seule) afin que les cartes d'une meme
                  // rangee restent alignees.
                  SizedBox(
                    height: MerchantOfferedByBubble._nameLineHeight * 2,
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyMedium.override(
                        font: GoogleFonts.inter(fontWeight: FontWeight.w800),
                        color: const Color(0xFFA0134D),
                        fontWeight: FontWeight.w800,
                        fontSize: 16.0,
                        lineHeight: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0.0,
            top: (bubbleHeight - avatarSize) / 2,
            child: _buildAvatar(avatarSize),
          ),
        ],
      ),
    );
  }

  static const double _avatarBorderWidth = 2.0;

  Widget _buildAvatar(double size) {
    // Le fond blanc de ce conteneur agit comme bordure : le contenu
    // (photo/fallback) est clippe en cercle a l'interieur, en retrait de
    // `_avatarBorderWidth`, ce qui laisse un liseret blanc visible tout
    // autour (peindre un `border` sur ce Container serait masque par
    // l'image, puisque `decoration` est dessine derriere le `child`).
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(_avatarBorderWidth),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: FutureBuilder<List<ImagesRecord>>(
          future: _photoFuture,
          builder: (context, snapshot) {
            final photos = snapshot.data ?? const <ImagesRecord>[];
            final url = photos.isNotEmpty ? photos.first.url : '';
            if (url.isEmpty) {
              return _buildFallbackAvatar();
            }
            final innerSize = size - (2 * _avatarBorderWidth);
            return ProxiplayNetworkImage(
              imageUrl: url,
              width: innerSize,
              height: innerSize,
              fit: BoxFit.cover,
            );
          },
        ),
      ),
    );
  }

  Widget _buildFallbackAvatar() {
    // Meme style que le fallback deja utilise par ProxiplayNetworkImage en
    // cas d'echec de chargement (fond gris clair + icone), pour une seule
    // et meme identite visuelle "image commercant indisponible" partout.
    return Container(
      color: const Color(0xFFE9EAF2),
      alignment: Alignment.center,
      child: const Icon(
        Icons.storefront_outlined,
        color: Color(0xFF6B70A7),
        size: 18.0,
      ),
    );
  }
}
