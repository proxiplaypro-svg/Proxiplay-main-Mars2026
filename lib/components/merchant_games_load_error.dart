import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Log once per failed request, rather than on every FutureBuilder rebuild.
Future<T> logMerchantGamesFailure<T>(Future<T> request, String source) async {
  try {
    return await request;
  } catch (error) {
    if (kDebugMode) {
      final detail = error is FirebaseException
          ? '${error.code}: ${error.message}'
          : error.toString();
      debugPrint('[MerchantGames][$source] $detail');
    }
    rethrow;
  }
}

class MerchantGamesLoadError extends StatelessWidget {
  const MerchantGamesLoadError({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Impossible de charger vos jeux.',
                textAlign: TextAlign.center),
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      );
}
