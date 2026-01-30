// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom widgets
import '/custom_code/actions/index.dart'; // Imports custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
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
  });

  final double? width;
  final double? height;
  final String hiddenContent;
  final String rewardText;
  final String rewardTextBonus;
  final String rewardImageUrl;
  final Function()
      setCardRevealed; // ✅ Paramètre pour mettre à jour un Local Page State

  @override
  State<ScratchCardWidget> createState() => _ScratchCardWidgetState();
}

class _ScratchCardWidgetState extends State<ScratchCardWidget> {
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
        ),
        onThreshold: () {
          widget.setCardRevealed();
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(20), // ✅ Coins arrondis pour le container
          ),
          alignment: Alignment.center,
          padding: EdgeInsets.all(10), // ✅ Ajout de padding pour aérer le texte
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.rewardText,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              if (widget.rewardTextBonus.isNotEmpty) ...[
                // ✅ Affiche seulement si non vide
                SizedBox(height: 10), // ✅ Espacement entre les textes
                Text(
                  widget.rewardTextBonus,
                  style: TextStyle(
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
