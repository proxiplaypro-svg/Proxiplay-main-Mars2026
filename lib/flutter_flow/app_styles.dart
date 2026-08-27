import 'package:flutter/material.dart';

class AppStyles {
  const AppStyles._();

  static const double gameCardRadius = 22.0;
  static const double gameCardWidth = 206.0;
  static const double gameCardImageHeight = 108.0;
  // +4px : la bulle "Offert par" reserve la hauteur de 2 lignes pour le nom
  // du commercant (voir MerchantOfferedByBubble), meme quand il tient sur
  // 1 seule ligne, pour aligner toutes les cartes d'une rangee. Valeur
  // resserree (244 -> 230) : les cartes utilisent toutes fitContent:true
  // (leur hauteur reelle ne depend pas de cette constante), qui sert
  // uniquement de hauteur de conteneur pour les carrousels Home — la
  // reduire resserre l'espace visible sous les carrousels sans jamais
  // toucher la taille reelle des cartes elles-memes.
  static const double gameCardHeight = 230.0;
  static const double finishedGameListHeight = 304.0;
  static const double finishedGameImageHeight = 114.0;

  static const EdgeInsets gameCardContentPadding =
      EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 10.0);
  static const EdgeInsets gameCardBadgePadding =
      EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0);
  static const EdgeInsets gameCardPriceBadgePadding =
      EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0);
  static const EdgeInsets gameCardWinnerPadding =
      EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0);

  static const Color gameCardBadgeColor = Color(0xFF3E61AE);
  static const Color gameCardPriceBadgeColor = Color(0xFFA0134D);
  static const Color gameCardWinnerBackground = Color(0xFFDEF1EF);
  static const Color gameCardWinnerText = Colors.green;

  static const double gameCardTitleSize = 16.0;
  static const double gameCardBodySize = 12.0;
  static const double gameCardBadgeSize = 13.0;
  static const double gameCardPriceBadgeSize = 13.0;
}
