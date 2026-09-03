import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/app_state.dart';
import '/auth/firebase_auth/auth_util.dart';

/// Badge "🎫 N" : nombre de tickets (participations validees) du joueur
/// connecte pour CE jeu precis -- un ticket = un document
/// games/{id}/participants filtre sur user_id == joueur connecte (voir
/// jeu_detail_joueur_page_widget.dart::_buildYourTicketsRow, meme source).
/// N'affiche jamais le nombre total de participants, uniquement ce compteur
/// personnel.
///
/// N'affiche rien tant que N <= 0 (etat par defaut d'un jeu jamais joue).
/// Joue une animation de scale-in la premiere fois que le badge apparait
/// pour un joueur sur ce jeu, et a nouveau chaque fois que N augmente
/// depuis la derniere fois qu'il a ete vu -- y compris apres un retour sur
/// un autre ecran, via une derniere valeur connue persistee (SharedPreferences,
/// FFAppState().prefs, deja initialise avant le premier rendu de l'app).
class TicketBadgeWidget extends StatefulWidget {
  const TicketBadgeWidget({super.key, required this.gameRef});

  final DocumentReference gameRef;

  @override
  State<TicketBadgeWidget> createState() => _TicketBadgeWidgetState();
}

class _TicketBadgeWidgetState extends State<TicketBadgeWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  int? _lastEvaluatedCount;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _scale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _prefsKey => 'ticket_badge_last_count_${widget.gameRef.id}';

  void _maybeAnimate(int count) {
    if (_lastEvaluatedCount == count) {
      return;
    }
    _lastEvaluatedCount = count;

    int? storedCount;
    try {
      storedCount = FFAppState().prefs.getInt(_prefsKey);
    } catch (_) {
      // Prefs pas encore prets (cas limite) : on n'anime pas, sans planter.
      storedCount = count;
    }

    final justIncremented = storedCount == null || count > storedCount;

    try {
      FFAppState().prefs.setInt(_prefsKey, count);
    } catch (_) {
      // Persistance best-effort : l'affichage du badge n'en depend pas.
    }

    if (justIncremented) {
      _controller.forward(from: 0.0);
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userRef = currentUserReference;
    if (userRef == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<QuerySnapshot>(
      stream: widget.gameRef
          .collection('participants')
          .where('user_id', isEqualTo: userRef)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        if (count <= 0) {
          return const SizedBox.shrink();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _maybeAnimate(count);
          }
        });
        return ScaleTransition(
          scale: _scale,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10.0,
              vertical: 5.0,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF5A623),
              borderRadius: BorderRadius.circular(20.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 6.0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎫', style: TextStyle(fontSize: 12.0)),
                const SizedBox(width: 4.0),
                Text(
                  '$count',
                  style: GoogleFonts.inter(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
