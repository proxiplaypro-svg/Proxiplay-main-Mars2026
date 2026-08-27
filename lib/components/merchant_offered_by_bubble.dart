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
    this.showOfferedByLabel = true,
  });

  final String merchantName;
  final DocumentReference? enseigneRef;

  /// Quand false, masque la ligne "Offert par" et centre verticalement le
  /// nom seul dans la bulle (meme hauteur totale reservee, juste un
  /// contenu recentre) — utilise uniquement pour le jeu de parrainage sans
  /// commercant partenaire ("Programme de parrainage" n'est pas un nom de
  /// commercant, donc "Offert par" n'a pas de sens). Toutes les cartes
  /// classiques utilisent la valeur par defaut (true) et gardent un rendu
  /// strictement identique a avant.
  final bool showOfferedByLabel;

  /// Diametre de la photo ronde.
  static const double avatarSize = 34.0;

  /// Distance entre le haut de la bulle et le bord bas de l'image (voir
  /// `GameCard`). Volontairement inferieure a la moitie de `totalHeight`
  /// pour que la bulle repose davantage sur la zone blanche de la carte et
  /// empiete moins sur l'image du haut.
  static const double topOffsetFromImageBottom = 11.0;

  /// Estimation de la hauteur totale de la bulle, utilisee par `GameCard`
  /// uniquement pour le positionnement (chevauchement avec l'image, espace
  /// reserve avant le titre). La hauteur REELLE du cartouche est toujours
  /// calculee par Flutter lui-meme (voir le texte fantome dans build()),
  /// donc un ecart de quelques pixels ici n'a qu'un effet cosmetique mineur
  /// sur le chevauchement — jamais de risque de superposition/coupure.
  static const double totalHeight = 44.0;

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
    const capsuleLeftInset = avatarSize / 2;

    final labelStyle = theme.bodySmall.override(
      font: GoogleFonts.inter(fontWeight: FontWeight.w500),
      color: const Color(0xFF8A8A8A),
      fontWeight: FontWeight.w500,
      fontSize: 8.5,
      lineHeight: 1.1,
    );
    final nameStyle = theme.bodyMedium.override(
      font: GoogleFonts.inter(fontWeight: FontWeight.w600),
      color: const Color(0xFFA0134D),
      fontWeight: FontWeight.w600,
      fontSize: 13.0,
      lineHeight: 1.05,
    );

    // Le bloc nom reserve toujours la hauteur de 2 lignes, meme si le nom
    // tient sur 1 seule — via un texte fantome invisible mesure par
    // Flutter avec le meme style (fiable quels que soient la police/
    // l'echelle de texte, contrairement a une hauteur en pixels calculee a
    // la main). Ainsi toutes les cartes d'une meme rangee gardent un
    // cartouche de meme hauteur, quel que soit le nombre de lignes
    // reellement utilisees.
    // `width: double.infinity` : sans ca, le Stack se dimensionne sur la
    // largeur naturelle du texte fantome ("Ag" = tres etroit) et le vrai
    // nom se retrouve coince dans cette largeur minuscule au lieu de la
    // largeur disponible de la pastille.
    //
    // `centerVertically` : rendu classique (avec "Offert par" juste
    // au-dessus) garde le nom colle en haut de son propre espace reserve,
    // pour rester adjacent au label — seul le vide restant descend en bas
    // de la bulle. Rendu sans label (parrainage) centre le nom dans son
    // propre espace ET (voir plus bas) dans la bulle entiere, pour un
    // veritable centrage vertical complet.
    Widget buildNameBlock({required bool centerVertically}) {
      final nameText = Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: nameStyle,
      );
      return SizedBox(
        width: double.infinity,
        child: Stack(
          children: [
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Text('Ag\nAg', style: nameStyle),
            ),
            Positioned.fill(
              child: centerVertically
                  ? Align(alignment: Alignment.centerLeft, child: nameText)
                  : nameText,
            ),
          ],
        ),
      );
    }

    // Rendu classique (par defaut, cartes commercant) : label + nom,
    // strictement identique a avant.
    final offeredByColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Offert par', style: labelStyle),
        const SizedBox(height: 1.5),
        buildNameBlock(centerVertically: false),
      ],
    );

    // Sans label (parrainage sans commercant partenaire) : la bulle
    // reserve exactement la meme hauteur totale (texte fantome de
    // `offeredByColumn`, invisible), mais le nom seul est centre
    // verticalement dedans plutot que colle en haut sous un espace vide.
    final capsuleContent = widget.showOfferedByLabel
        ? offeredByColumn
        : Stack(
            children: [
              Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: offeredByColumn,
              ),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: buildNameBlock(centerVertically: true),
                ),
              ),
            ],
          );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Enfant non positionne : c'est lui qui determine la hauteur de la
        // bulle (le cartouche, decale a droite via sa marge gauche pour
        // laisser la place a la photo qui le chevauche).
        Container(
          margin: const EdgeInsets.only(left: capsuleLeftInset),
          padding: const EdgeInsets.fromLTRB(
            capsuleLeftInset + 6.0,
            3.0,
            10.0,
            3.0,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            // Rectangle a coins arrondis, coherent avec les pastilles de
            // prix des cartes ("195 €"...) — plus une forme pilule.
            borderRadius: BorderRadius.circular(14.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8.0,
                offset: const Offset(0.0, 2.0),
              ),
            ],
          ),
          child: capsuleContent,
        ),
        Positioned(
          left: 0.0,
          top: 0.0,
          bottom: 0.0,
          child: Center(child: _buildAvatar(avatarSize)),
        ),
      ],
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
