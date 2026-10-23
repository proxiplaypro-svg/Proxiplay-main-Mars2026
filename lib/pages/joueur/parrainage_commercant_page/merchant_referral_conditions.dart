import 'package:flutter/material.dart';

class MerchantReferralConditionsDialog extends StatelessWidget {
  const MerchantReferralConditionsDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Conditions du programme'),
        content: const SingleChildScrollView(
          child: Text(
            'Le parrain peut être un joueur ou un commerçant ProxiPlay. Il reçoit 50 € en bons cadeaux, jamais en espèces, lorsque le commerçant parrainé a réglé son premier abonnement et que le parrainage est validé. '
            'Le commerçant renseigne le code en créant son compte ProxiPlay. Un même compte commerçant ne peut être parrainé qu’une fois. '
            'Les modalités de remise des bons cadeaux restent à préciser. '
            'Les droits des parrainages antérieurs restent soumis aux conditions qui leur étaient applicables.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer')),
        ],
      );
}
