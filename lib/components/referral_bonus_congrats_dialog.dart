import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/utils/referral_bonus_notice.dart';

/// Congratulation window of a granted referral bonus (player home).
class ReferralBonusCongratsDialog extends StatelessWidget {
  const ReferralBonusCongratsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return AlertDialog(
      key: const ValueKey('referral-bonus-congrats'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
      title: Text(
        referralBonusNoticeTitle,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18.0, fontWeight: FontWeight.w800),
      ),
      content: const Text(
        referralBonusNoticeBody,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15.0, height: 1.4),
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
          child: const Text(referralBonusNoticeButton),
        ),
      ],
    );
  }
}
