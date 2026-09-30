import 'package:flutter/material.dart';

class MerchantPrizeClaimSuccessDialog extends StatelessWidget {
  const MerchantPrizeClaimSuccessDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
        icon: const Icon(
          Icons.check_circle_rounded,
          color: Colors.green,
          size: 36,
        ),
        title: const Text('Lot validé ✓'),
        content: const Text('Le lot a bien été marqué comme retiré.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Terminer'),
          ),
        ],
      );
}
