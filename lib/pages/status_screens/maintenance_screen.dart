import 'package:flutter/material.dart';

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Ou ta couleur de marque
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Tu peux remplacer l'Icon par une Image.asset('assets/images/logo.png')
            const Icon(Icons.build_circle_outlined, size: 80, color: Colors.orange),
            const SizedBox(height: 20),
            const Text(
              "Maintenance en cours",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              "Nous améliorons Proxiplay pour vous. L'application sera de retour très bientôt.",
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}