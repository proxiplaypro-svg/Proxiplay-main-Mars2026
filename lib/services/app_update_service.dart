import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.hasUpdate,
    this.storeUrl,
    this.latestVersion,
  });

  final bool hasUpdate;
  final String? storeUrl;
  final String? latestVersion;
}

class _RemoteAppVersionConfig {
  const _RemoteAppVersionConfig({
    required this.latestAndroidVersion,
    required this.latestIosVersion,
    required this.androidStoreUrl,
    required this.iosStoreUrl,
  });

  final String latestAndroidVersion;
  final String latestIosVersion;
  final String androidStoreUrl;
  final String iosStoreUrl;

  static _RemoteAppVersionConfig? fromMap(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }

    final latestAndroidVersion = data['latest_android_version'];
    final latestIosVersion = data['latest_ios_version'];
    final androidStoreUrl = data['android_store_url'];
    final iosStoreUrl = data['ios_store_url'];

    if (latestAndroidVersion is! String ||
        latestIosVersion is! String ||
        androidStoreUrl is! String ||
        iosStoreUrl is! String) {
      return null;
    }

    return _RemoteAppVersionConfig(
      latestAndroidVersion: latestAndroidVersion.trim(),
      latestIosVersion: latestIosVersion.trim(),
      androidStoreUrl: androidStoreUrl.trim(),
      iosStoreUrl: iosStoreUrl.trim(),
    );
  }
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static bool _hasShownDialogThisSession = false;
  static bool _isDialogInProgress = false;

  Future<String?> getInstalledVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return _normalizeVersion(packageInfo.version);
    } catch (_) {
      return null;
    }
  }

  Future<_RemoteAppVersionConfig?> getRemoteConfig() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('version')
          .get();

      if (!snapshot.exists) {
        return null;
      }

      return _RemoteAppVersionConfig.fromMap(snapshot.data());
    } catch (_) {
      return null;
    }
  }

  int compareVersions(String versionA, String versionB) {
    final partsA = _normalizeVersion(versionA).split('.');
    final partsB = _normalizeVersion(versionB).split('.');
    final maxLength = partsA.length > partsB.length ? partsA.length : partsB.length;

    for (var index = 0; index < maxLength; index++) {
      final a = index < partsA.length ? int.tryParse(partsA[index]) ?? 0 : 0;
      final b = index < partsB.length ? int.tryParse(partsB[index]) ?? 0 : 0;

      if (a != b) {
        return a.compareTo(b);
      }
    }

    return 0;
  }

  Future<AppUpdateInfo> checkForUpdate() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return const AppUpdateInfo(hasUpdate: false);
    }

    final installedVersion = await getInstalledVersion();
    final remoteConfig = await getRemoteConfig();

    if (installedVersion == null || remoteConfig == null) {
      return const AppUpdateInfo(hasUpdate: false);
    }

    final latestVersion = Platform.isAndroid
        ? _normalizeVersion(remoteConfig.latestAndroidVersion)
        : _normalizeVersion(remoteConfig.latestIosVersion);
    final storeUrl =
        Platform.isAndroid ? remoteConfig.androidStoreUrl : remoteConfig.iosStoreUrl;

    if (latestVersion.isEmpty || !_isValidStoreUrl(storeUrl)) {
      return const AppUpdateInfo(hasUpdate: false);
    }

    final hasUpdate = compareVersions(installedVersion, latestVersion) < 0;
    if (!hasUpdate) {
      return const AppUpdateInfo(hasUpdate: false);
    }

    return AppUpdateInfo(
      hasUpdate: true,
      storeUrl: storeUrl,
      latestVersion: latestVersion,
    );
  }

  Future<void> openStoreUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !_isValidStoreUri(uri)) {
      return;
    }

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return;
    }
  }

  Future<void> maybeShowUpdateDialog(BuildContext context) async {
    if (_hasShownDialogThisSession || _isDialogInProgress || !context.mounted) {
      return;
    }

    _isDialogInProgress = true;

    try {
      final updateInfo = await checkForUpdate();
      if (!updateInfo.hasUpdate || !context.mounted) {
        return;
      }

      _hasShownDialogThisSession = true;

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Mise a jour disponible'),
            content: const Text(
              'Une nouvelle version de Proxiplay est disponible. '
              'Mets l\'application a jour pour profiter des dernieres ameliorations.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Plus tard'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  final storeUrl = updateInfo.storeUrl;
                  if (storeUrl != null) {
                    await openStoreUrl(storeUrl);
                  }
                },
                child: const Text('Mettre a jour'),
              ),
            ],
          );
        },
      );
    } catch (_) {
      return;
    } finally {
      _isDialogInProgress = false;
    }
  }

  String _normalizeVersion(String version) {
    final trimmed = version.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final cleaned = trimmed.split('+').first.split('-').first.trim();
    if (cleaned.isEmpty) {
      return '';
    }

    return cleaned
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .join('.');
  }

  bool _isValidStoreUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && _isValidStoreUri(uri);
  }

  bool _isValidStoreUri(Uri uri) {
    return uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}
