// Manual native-storage regression probe. Synthetic data only; no Firebase.
// flutter run -t tools/winner_export_storage_probe.dart -d emulator-5554
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proxi_play/utils/game_players_export.dart';

void main() => runApp(const MaterialApp(home: StorageProbe()));

class StorageProbe extends StatefulWidget {
  const StorageProbe({super.key});
  @override
  State<StorageProbe> createState() => _StorageProbeState();
}

class _StorageProbeState extends State<StorageProbe> {
  String status = 'Ready';
  bool busy = false;
  Future<void> save(bool legacy) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = 'Saving';
    });
    final bytes = utf8.encode(
        '\uFEFFPrénom;Nom;Email;Téléphone;Ville;Date du gain;Lot gagné;Code gagnant;Statut\r\nTEST;TEST;;;;25/09/2026;TEST;SYNTHETIC;À retirer\r\n');
    try {
      if (legacy) {
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/proxiplay_storage_probe.csv');
        await file.writeAsBytes(bytes, flush: true);
        await MediaStore.ensureInitialized();
        MediaStore.appFolder = 'Proxiplay';
        final info = await MediaStore()
            .saveFile(
                tempFilePath: file.path,
                dirType: DirType.download,
                dirName: DirType.download.defaults,
                relativePath: FilePath.root)
            .timeout(const Duration(seconds: 20));
        status = 'legacy=${info == null ? 'null' : 'saved'}';
      } else {
        final result = await saveGamePlayersCsv(
            GamePlayersExportResult(
                fileName: 'proxiplay_storage_probe.csv',
                bytes: bytes,
                rowCount: 1),
            shareSubject: 'Synthetic probe');
        status = 'new=${result.destination.name} bytes=${bytes.length}';
      }
      debugPrint('[StorageProbe] $status');
    } catch (error, stack) {
      // This probe contains exclusively synthetic bytes and a constant name.
      status = '${error.runtimeType}: $error';
      debugPrint('[StorageProbe] $status\n$stack');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: Column(
        children: [
          ElevatedButton(
              onPressed: busy ? null : () => save(true),
              child: const Text('Legacy MediaStore')),
          ElevatedButton(
              onPressed: busy ? null : () => save(false),
              child: const Text('Save winners')),
          Text(status),
        ],
      )));
}
