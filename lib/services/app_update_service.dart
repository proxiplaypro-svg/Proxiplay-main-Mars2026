import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum AppUpdateStatus {
  upToDate,
  optionalUpdate,
  requiredUpdate,
  disabled,
  unavailable,
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.latestVersion,
    this.minSupportedVersion,
    this.title,
    this.message,
    this.storeUrl,
    this.remindLaterHours = 24,
    this.shouldShowDialog = false,
    this.debugReason = '',
  });

  final AppUpdateStatus status;
  final String currentVersion;
  final String? latestVersion;
  final String? minSupportedVersion;
  final String? title;
  final String? message;
  final String? storeUrl;
  final int remindLaterHours;
  final bool shouldShowDialog;
  final String debugReason;

  bool get isRequired => status == AppUpdateStatus.requiredUpdate;
  bool get isOptional => status == AppUpdateStatus.optionalUpdate;
}

class AppUpdateService {
  AppUpdateService._internal();

  static final AppUpdateService instance = AppUpdateService._internal();

  static const _collection = 'app_config';
  static const _document = 'mobile_versioning';
  static const _dismissedVersionKey = 'app_update_dismissed_version';
  static const _dismissedAtKey = 'app_update_dismissed_at_ms';

  Future<AppUpdateCheckResult> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = _normalizeVersion(packageInfo.version);
      final snapshot = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_document)
          .get();

      if (!snapshot.exists) {
        final result = AppUpdateCheckResult(
          status: AppUpdateStatus.unavailable,
          currentVersion: currentVersion,
          debugReason: 'config_absente',
        );
        _logResult(result);
        return result;
      }

      final data = snapshot.data() ?? const <String, dynamic>{};
      final enabled = data['enabled'] == true;
      final latestVersion =
          _normalizeVersion((data['latest_version'] ?? '').toString());
      final minSupportedVersion =
          _normalizeVersion((data['min_supported_version'] ?? '').toString());
      final remindLaterHours = _readRemindLaterHours(data);
      final storeUrl = _resolveStoreUrl(data);

      _log(
        'versions_lues',
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        minSupportedVersion: minSupportedVersion,
        extra:
            'enabled=$enabled storeUrl=${storeUrl ?? ''} remindLaterHours=$remindLaterHours',
      );

      if (!enabled) {
        final result = AppUpdateCheckResult(
          status: AppUpdateStatus.disabled,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          minSupportedVersion: minSupportedVersion,
          storeUrl: storeUrl,
          remindLaterHours: remindLaterHours,
          debugReason: 'disabled',
        );
        _logResult(result);
        return result;
      }

      if (latestVersion.isEmpty || minSupportedVersion.isEmpty) {
        final result = AppUpdateCheckResult(
          status: AppUpdateStatus.unavailable,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          minSupportedVersion: minSupportedVersion,
          storeUrl: storeUrl,
          remindLaterHours: remindLaterHours,
          debugReason: 'version_config_incomplete',
        );
        _logResult(result);
        return result;
      }

      final minComparison =
          compareVersions(currentVersion, minSupportedVersion);
      final latestComparison = compareVersions(currentVersion, latestVersion);

      if (minComparison < 0) {
        if (storeUrl == null || storeUrl.isEmpty) {
          final result = AppUpdateCheckResult(
            status: AppUpdateStatus.unavailable,
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            minSupportedVersion: minSupportedVersion,
            remindLaterHours: remindLaterHours,
            debugReason: 'required_update_but_store_url_missing',
          );
          _logResult(result);
          return result;
        }

        final result = AppUpdateCheckResult(
          status: AppUpdateStatus.requiredUpdate,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          minSupportedVersion: minSupportedVersion,
          title: (data['force_title'] ?? 'Mise à jour requise').toString(),
          message: (data['force_message'] ??
                  'Votre version de Proxiplay n’est plus compatible. Veuillez mettre à jour l’application pour continuer.')
              .toString(),
          storeUrl: storeUrl,
          remindLaterHours: remindLaterHours,
          shouldShowDialog: true,
          debugReason: 'required_update',
        );
        _logResult(result);
        return result;
      }

      if (latestComparison < 0) {
        final shouldShowDialog =
            await _shouldShowOptionalDialog(latestVersion, remindLaterHours);
        final result = AppUpdateCheckResult(
          status: AppUpdateStatus.optionalUpdate,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          minSupportedVersion: minSupportedVersion,
          title:
              (data['update_title'] ?? 'Mise à jour disponible').toString(),
          message: (data['update_message'] ??
                  'Une nouvelle version de Proxiplay est disponible.')
              .toString(),
          storeUrl: storeUrl,
          remindLaterHours: remindLaterHours,
          shouldShowDialog: shouldShowDialog,
          debugReason: shouldShowDialog
              ? 'optional_update'
              : 'optional_update_remind_later',
        );
        _logResult(result);
        return result;
      }

      final result = AppUpdateCheckResult(
        status: AppUpdateStatus.upToDate,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        minSupportedVersion: minSupportedVersion,
        remindLaterHours: remindLaterHours,
        debugReason: 'up_to_date',
      );
      _logResult(result);
      return result;
    } catch (error, stackTrace) {
      debugPrint('[AppUpdateService] erreur_check=$error');
      debugPrint('[AppUpdateService] stack=$stackTrace');
      String currentVersion = '';
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        currentVersion = _normalizeVersion(packageInfo.version);
      } catch (_) {}
      final result = AppUpdateCheckResult(
        status: AppUpdateStatus.unavailable,
        currentVersion: currentVersion,
        debugReason: 'exception',
      );
      _logResult(result);
      return result;
    }
  }

  Future<void> markOptionalUpdateDismissed({
    required String latestVersion,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedVersionKey, latestVersion);
    await prefs.setInt(_dismissedAtKey, DateTime.now().millisecondsSinceEpoch);
    debugPrint(
      '[AppUpdateService] remind_later_saved version=$latestVersion',
    );
  }

  Future<bool> tryStartNativeUpdate(AppUpdateCheckResult result) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      debugPrint(
        '[AppUpdateService] native_android_update_non_impl version=${result.latestVersion ?? ''}',
      );
    }
    return false;
  }

  Future<bool> openStore(AppUpdateCheckResult result) async {
    final storeUrl = result.storeUrl;
    if (storeUrl == null || storeUrl.isEmpty) {
      debugPrint('[AppUpdateService] store_url_absente');
      return false;
    }

    final uri = Uri.tryParse(storeUrl);
    if (uri == null) {
      debugPrint('[AppUpdateService] store_url_invalide value=$storeUrl');
      return false;
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    debugPrint('[AppUpdateService] store_opened=$launched url=$storeUrl');
    return launched;
  }

  int compareVersions(String a, String b) {
    final aParts = _parseVersion(a);
    final bParts = _parseVersion(b);
    final maxLength = aParts.length > bParts.length ? aParts.length : bParts.length;

    for (var index = 0; index < maxLength; index++) {
      final aPart = index < aParts.length ? aParts[index] : 0;
      final bPart = index < bParts.length ? bParts[index] : 0;
      if (aPart != bPart) {
        return aPart.compareTo(bPart);
      }
    }
    return 0;
  }

  Future<bool> _shouldShowOptionalDialog(
    String latestVersion,
    int remindLaterHours,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final dismissedVersion = prefs.getString(_dismissedVersionKey) ?? '';
    final dismissedAtMs = prefs.getInt(_dismissedAtKey) ?? 0;

    if (dismissedVersion != latestVersion || dismissedAtMs <= 0) {
      debugPrint(
        '[AppUpdateService] optional_dialog_allowed reason=nouvelle_version_ou_pas_de_refus',
      );
      return true;
    }

    final dismissedAt = DateTime.fromMillisecondsSinceEpoch(dismissedAtMs);
    final nextAllowedAt =
        dismissedAt.add(Duration(hours: remindLaterHours));
    final shouldShow = DateTime.now().isAfter(nextAllowedAt);

    debugPrint(
      '[AppUpdateService] optional_dialog_allowed=$shouldShow '
      'dismissedVersion=$dismissedVersion dismissedAt=$dismissedAt '
      'nextAllowedAt=$nextAllowedAt',
    );

    return shouldShow;
  }

  int _readRemindLaterHours(Map<String, dynamic> data) {
    final rawValue = data['remind_later_hours'];
    if (rawValue is num && rawValue > 0) {
      return rawValue.toInt();
    }
    return 24;
  }

  String? _resolveStoreUrl(Map<String, dynamic> data) {
    if (kIsWeb) {
      return (data['android_store_url'] ?? '').toString();
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return (data['ios_store_url'] ?? '').toString();
      case TargetPlatform.android:
        return (data['android_store_url'] ?? '').toString();
      default:
        return (data['android_store_url'] ?? '').toString();
    }
  }

  List<int> _parseVersion(String version) {
    final normalized = _normalizeVersion(version);
    if (normalized.isEmpty) {
      return const [0];
    }

    return normalized
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  String _normalizeVersion(String version) {
    final trimmed = version.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final withoutBuild = trimmed.split('+').first;
    final withoutPrerelease = withoutBuild.split('-').first;
    return withoutPrerelease.trim();
  }

  void _log(
    String message, {
    required String currentVersion,
    String latestVersion = '',
    String minSupportedVersion = '',
    String extra = '',
  }) {
    debugPrint(
      '[AppUpdateService] $message '
      'current=$currentVersion latest=$latestVersion min=$minSupportedVersion $extra',
    );
  }

  void _logResult(AppUpdateCheckResult result) {
    debugPrint(
      '[AppUpdateService] result=${result.status.name} '
      'current=${result.currentVersion} '
      'latest=${result.latestVersion ?? ''} '
      'min=${result.minSupportedVersion ?? ''} '
      'storeUrl=${result.storeUrl ?? ''} '
      'showDialog=${result.shouldShowDialog} '
      'reason=${result.debugReason}',
    );
  }
}
