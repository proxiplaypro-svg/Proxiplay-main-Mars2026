// Automatic FlutterFlow imports
// Imports other custom widgets
// Imports custom actions
// Imports custom functions
import 'package:flutter/material.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:scratcher/scratcher.dart';

class ScratchCardWidget extends StatefulWidget {
  const ScratchCardWidget({
    super.key,
    this.width,
    this.height,
    required this.hiddenContent,
    required this.rewardText,
    required this.rewardTextBonus,
    required this.rewardImageUrl,
    required this.setCardRevealed, // ✅ Ajout de l'action FlutterFlow
    this.onScratchStart,
    this.onScratchEnd,
  });

  final double? width;
  final double? height;
  final String hiddenContent;
  final String rewardText;
  final String rewardTextBonus;
  final String rewardImageUrl;
  final Function()
      setCardRevealed; // ✅ Paramètre pour mettre à jour un Local Page State
  final VoidCallback? onScratchStart;
  final VoidCallback? onScratchEnd;

  @override
  State<ScratchCardWidget> createState() => _ScratchCardWidgetState();
}

class _ScratchCardWidgetState extends State<ScratchCardWidget> {
  bool _isRevealed = false;
  bool _hasScratchStarted = false;
  bool _hasReachedThreshold = false;

  void _revealCardIfNeeded() {
    if (!_hasScratchStarted || !_hasReachedThreshold || _isRevealed) {
      return;
    }

    setState(() {
      _isRevealed = true;
    });
    widget.setCardRevealed();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      //onVerticalDragUpdate: (_) {}, // empêche propagation du scroll
      child: Scratcher(
        brushSize: 60.0,
        threshold: 50.0, // Pourcentage de grattage requis
        image: Image.network(
          widget.rewardImageUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              Container(color: const Color(0xFFEDEDED)),
        ),
        onThreshold: () {
          if (!_hasScratchStarted) {
            return;
          }
          _hasReachedThreshold = true;
        },
        onScratchStart: () {
          if (!_hasScratchStarted) {
            setState(() {
              _hasScratchStarted = true;
            });
          }
          widget.onScratchStart?.call();
        },
        onScratchEnd: () {
          _revealCardIfNeeded();
          widget.onScratchEnd?.call();
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(20), // ✅ Coins arrondis pour le container
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(10), // ✅ Ajout de padding pour aérer le texte
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _isRevealed ? widget.rewardText : widget.hiddenContent,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              if (_isRevealed && widget.rewardTextBonus.isNotEmpty) ...[
                // ✅ Affiche seulement si non vide
                const SizedBox(height: 10), // ✅ Espacement entre les textes
                Text(
                  widget.rewardTextBonus,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.normal,
                    color: Colors.green, // ✅ Met en avant le message bonus
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
