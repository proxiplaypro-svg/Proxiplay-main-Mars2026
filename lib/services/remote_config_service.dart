import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart'; // Pour debugPrint

class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;
  RemoteConfigService._internal();

  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;
  late PackageInfo _packageInfo;

  Future<void> initialize() async {
    try {
      _packageInfo = await PackageInfo.fromPlatform();

      await _remoteConfig.setDefaults({
        'maintenance_mode': false,
        'min_required_version': '1.0.0',
      });

      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(seconds: 10),
      ));

      await _remoteConfig.fetchAndActivate();
      
      // --- LOGS DE DIAGNOSTIC ---
      debugPrint("--- CONFIG DIAGNOSTIC ---");
      debugPrint("Version App Locale (Brute): ${_packageInfo.version}");
      debugPrint("Version Firebase requise: ${_remoteConfig.getString('min_required_version')}");
      debugPrint("Mode Maintenance: ${_remoteConfig.getBool('maintenance_mode')}");
      debugPrint("-------------------------");
      
    } catch (e) {
      debugPrint('Erreur Remote Config: $e');
    }
  }

  bool get isMaintenanceMode => _remoteConfig.getBool('maintenance_mode');
  String get minRequiredVersion => _remoteConfig.getString('min_required_version');

  bool isUpdateRequired() {
    // 1. On nettoie la version locale (ex: "1.0.0+2" devient "1.0.0")
    final currentVersion = _cleanVersion(_packageInfo.version);
    
    // 2. On récupère la version Firebase
    final minVersion = _cleanVersion(minRequiredVersion);

    debugPrint("Comparaison: App($currentVersion) vs Requis($minVersion)");

    if (currentVersion.isEmpty || minVersion.isEmpty) return false;

    return _compareVersions(currentVersion, minVersion) < 0;
  }

  // Petite méthode pour enlever le "+1" ou "-beta"
  String _cleanVersion(String v) {
    if (v.contains('+')) {
      return v.split('+')[0];
    }
    if (v.contains('-')) {
      return v.split('-')[0];
    }
    return v;
  }

  int _compareVersions(String v1, String v2) {
    try {
      var v1Parts = v1.split('.').map(int.parse).toList();
      var v2Parts = v2.split('.').map(int.parse).toList();
      
      for (var i = 0; i < 3; i++) {
        int part1 = v1Parts.length > i ? v1Parts[i] : 0;
        int part2 = v2Parts.length > i ? v2Parts[i] : 0;
        if (part1 != part2) return part1 - part2;
      }
      return 0;
    } catch (e) {
      debugPrint("Erreur comparaison versions: $e");
      return 0; 
    }
  }
}