import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/utils/referral_bonus_notice.dart';

/// Confirmation of a referral game ticket (player home). Distinct from the
/// classic bonus window: a ticket for the draw, never "all games".
/// Pops with true when the player asks to see the referral game.
class ReferralTicketCongratsDialog extends StatelessWidget {
  const ReferralTicketCongratsDialog({super.key, required this.notice});

  final ReferralTicketNotice notice;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return AlertDialog(
      key: const ValueKey('referral-ticket-congrats'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
      title: const Text(
        referralTicketNoticeTitle,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.w800),
      ),
      content: Text(
        referralTicketNoticeBody(notice),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 15.0, height: 1.4),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14.0),
            ),
          ),
          child: const Text(referralTicketNoticeButton),
        ),
      ],
    );
  }
}
