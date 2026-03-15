import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';

Future<void> showCreateAccountToPlayDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Créer un compte pour jouer'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Plus tard'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            if (!context.mounted) {
              return;
            }
            context.pushNamed(InscriptionPageWidget.routeName);
          },
          child: const Text('Créer un compte'),
        ),
      ],
    ),
  );
}
