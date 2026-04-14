import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  Future<void> _launchStore() async {
    final Uri url = Uri.parse('https://onelink.to/jx4ee7');

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Impossible d'ouvrir le lien OneLink");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.system_update, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              'Mise à jour requise',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Une nouvelle version de Proxiplay est disponible. Veuillez la télécharger pour continuer.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _launchStore,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Mettre à jour maintenant'),
            ),
          ],
        ),
      ),
    );
  }
}
