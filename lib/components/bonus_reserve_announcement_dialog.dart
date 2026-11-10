import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/utils/bonus_reserve_announcement.dart';

/// Annonce unique de la reserve de parties bonus (accueil joueur, 1.1.4).
class BonusReserveAnnouncementDialog extends StatelessWidget {
  const BonusReserveAnnouncementDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return AlertDialog(
      key: const ValueKey('bonus-reserve-announcement'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
      title: const Text(
        bonusReserveAnnouncementTitle,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.w800),
      ),
      content: const SingleChildScrollView(
        child: Text(
          bonusReserveAnnouncementBody,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15.0, height: 1.4),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14.0),
            ),
          ),
          child: const Text(bonusReserveAnnouncementButton),
        ),
      ],
    );
  }
}
