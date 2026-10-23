import 'package:flutter/material.dart';

class MerchantReferralConditionsDialog extends StatelessWidget {
  const MerchantReferralConditionsDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Conditions du programme'),
        content: const SingleChildScrollView(
          child: Text(
            'Le parrain est un joueur ProxiPlay. Il reçoit un bon cadeau de 50 € lorsque le commerçant parrainé souscrit un abonnement éligible et que le parrainage est validé. '
            'Le code doit être renseigné lors de la souscription. Un même compte commerçant ne peut être parrainé qu’une fois. '
            'Les modalités de remise du bon cadeau restent à préciser. '
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
