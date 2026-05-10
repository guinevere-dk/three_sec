import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const String kAppUpdateConfigUrl = String.fromEnvironment(
  'APP_UPDATE_CONFIG_URL',
  defaultValue: '',
);

enum AppUpdateType { none, optional, forced }

@immutable
class SemanticVersion implements Comparable<SemanticVersion> {
  final int major;
  final int minor;
  final int patch;

  const SemanticVersion({
    required this.major,
    required this.minor,
    required this.patch,
  });

  factory SemanticVersion.parse(String value) {
    final normalized = value.trim().split('+').first;
    final parts = normalized.split('.');
    if (parts.length != 3) {
      throw FormatException(
        'semantic version must be major.minor.patch: $value',
      );
    }
    return SemanticVersion(
      major: int.parse(parts[0]),
      minor: int.parse(parts[1]),
      patch: int.parse(parts[2]),
    );
  }

  @override
  int compareTo(SemanticVersion other) {
    final majorCompare = major.compareTo(other.major);
    if (majorCompare != 0) return majorCompare;
    final minorCompare = minor.compareTo(other.minor);
    if (minorCompare != 0) return minorCompare;
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

@immutable
class AppUpdateConfig {
  final SemanticVersion? latestVersion;
  final SemanticVersion? minimumRequiredVersion;
  final String? playStoreUrl;
  final String? message;

  const AppUpdateConfig({
    this.latestVersion,
    this.minimumRequiredVersion,
    this.playStoreUrl,
    this.message,
  });

  factory AppUpdateConfig.fromJson(Map<String, dynamic> json) {
    final latest = _stringValue(
      json['latestVersion'] ?? json['latest_version'],
    );
    final minimum = _stringValue(
      json['minimumRequiredVersion'] ?? json['minimum_required_version'],
    );
    return AppUpdateConfig(
      latestVersion: _parseNullableVersion(latest, 'latestVersion'),
      minimumRequiredVersion: _parseNullableVersion(
        minimum,
        'minimumRequiredVersion',
      ),
      playStoreUrl: _stringValue(
        json['playStoreUrl'] ?? json['play_store_url'],
      ),
      message: _stringValue(json['message']),
    );
  }

  static String? _stringValue(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static SemanticVersion? _parseNullableVersion(String? value, String field) {
    if (value == null) return null;
    try {
      return SemanticVersion.parse(value);
    } catch (e) {
      debugPrint('[AppUpdate] ignored invalid $field=$value: $e');
      return null;
    }
  }
}

@immutable
class AppUpdateStatus {
  final AppUpdateType type;
  final SemanticVersion currentVersion;
  final AppUpdateConfig? config;

  const AppUpdateStatus({
    required this.type,
    required this.currentVersion,
    this.config,
  });

  bool get hasUpdate => type != AppUpdateType.none;
  bool get isForced => type == AppUpdateType.forced;
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  AppUpdateStatus? _lastStatus;
  String? _lastOptionalPromptVersion;
  bool _isDialogShowing = false;

  AppUpdateStatus classifyUpdate({
    required SemanticVersion currentVersion,
    required AppUpdateConfig config,
  }) {
    final type = _resolveUpdateType(
      currentVersion: currentVersion,
      latestVersion: config.latestVersion,
      minimumRequiredVersion: config.minimumRequiredVersion,
    );
    return AppUpdateStatus(
      type: type,
      currentVersion: currentVersion,
      config: config,
    );
  }

  AppUpdateType _resolveUpdateType({
    required SemanticVersion currentVersion,
    required SemanticVersion? latestVersion,
    required SemanticVersion? minimumRequiredVersion,
  }) {
    if (minimumRequiredVersion != null &&
        currentVersion.compareTo(minimumRequiredVersion) < 0) {
      return AppUpdateType.forced;
    }
    if (latestVersion != null && currentVersion.compareTo(latestVersion) < 0) {
      return AppUpdateType.optional;
    }
    return AppUpdateType.none;
  }

  Future<AppUpdateStatus?> checkForUpdate({bool forceRefresh = false}) async {
    if (!forceRefresh && _lastStatus != null) return _lastStatus;

    final info = await PackageInfo.fromPlatform();
    final currentVersion = SemanticVersion.parse(info.version);

    if (kAppUpdateConfigUrl.isEmpty) {
      debugPrint(
        '[AppUpdate] APP_UPDATE_CONFIG_URL is empty. update check skipped.',
      );
      _lastStatus = AppUpdateStatus(
        type: AppUpdateType.none,
        currentVersion: currentVersion,
      );
      return _lastStatus;
    }

    try {
      final uri = Uri.parse(kAppUpdateConfigUrl);
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          '[AppUpdate] config fetch skipped status=${response.statusCode}',
        );
        return AppUpdateStatus(
          type: AppUpdateType.none,
          currentVersion: currentVersion,
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('update config root must be an object');
      }

      final config = AppUpdateConfig.fromJson(decoded);
      _lastStatus = classifyUpdate(
        currentVersion: currentVersion,
        config: config,
      );
      debugPrint(
        '[AppUpdate] current=$currentVersion latest=${config.latestVersion} '
        'minimum=${config.minimumRequiredVersion} type=${_lastStatus!.type.name}',
      );
      return _lastStatus;
    } catch (e, st) {
      debugPrint('[AppUpdate] check failed: $e');
      debugPrint('[AppUpdate][Stack]\n$st');
      return AppUpdateStatus(
        type: AppUpdateType.none,
        currentVersion: currentVersion,
      );
    }
  }

  Future<void> checkAndPromptOnEntry(BuildContext context) async {
    final status = await checkForUpdate(forceRefresh: true);
    if (status == null || !context.mounted || !status.hasUpdate) return;
    if (!status.isForced) {
      final latest = status.config?.latestVersion.toString();
      if (latest != null && _lastOptionalPromptVersion == latest) return;
      _lastOptionalPromptVersion = latest;
    }
    await showUpdateDialog(context, status: status);
  }

  Future<void> showManualUpdateCheck(BuildContext context) async {
    final status = await checkForUpdate(forceRefresh: true);
    if (!context.mounted) return;
    if (status == null || !status.hasUpdate) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('현재 설치된 앱이 최신 상태입니다.')));
      return;
    }
    await showUpdateDialog(context, status: status, manual: true);
  }

  Future<void> showUpdateDialog(
    BuildContext context, {
    required AppUpdateStatus status,
    bool manual = false,
  }) async {
    if (_isDialogShowing || !context.mounted) return;
    _isDialogShowing = true;
    final isForced = status.isForced;
    final latestText = status.config?.latestVersion.toString() ?? '-';
    final currentText = status.currentVersion.toString();
    final message = status.config?.message;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !isForced,
        builder: (dialogContext) => PopScope(
          canPop: !isForced,
          child: AlertDialog(
            title: Text(isForced ? '업데이트가 필요합니다' : '새 버전이 있습니다'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isForced
                      ? '계속 사용하려면 최신 버전으로 업데이트해야 합니다.'
                      : '더 안정적인 이용을 위해 최신 버전으로 업데이트할 수 있습니다.',
                ),
                const SizedBox(height: 10),
                Text('현재 버전: v$currentText'),
                Text('최신 버전: v$latestText'),
                if (message != null) ...[
                  const SizedBox(height: 10),
                  Text(message),
                ],
              ],
            ),
            actions: [
              if (!isForced)
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(manual ? '닫기' : '나중에'),
                ),
              FilledButton(
                onPressed: () => openStore(status.config?.playStoreUrl),
                child: const Text('업데이트'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _isDialogShowing = false;
    }
  }

  Future<bool> openStore([String? explicitPlayStoreUrl]) async {
    final info = await PackageInfo.fromPlatform();
    final packageName = info.packageName;
    final fallbackHttps = Uri.parse(
      explicitPlayStoreUrl?.trim().isNotEmpty == true
          ? explicitPlayStoreUrl!.trim()
          : 'https://play.google.com/store/apps/details?id=$packageName',
    );

    if (!kIsWeb && Platform.isAndroid) {
      final marketUri = Uri.parse('market://details?id=$packageName');
      if (await launchUrl(marketUri, mode: LaunchMode.externalApplication)) {
        return true;
      }
      return launchUrl(fallbackHttps, mode: LaunchMode.externalApplication);
    }

    if (await launchUrl(fallbackHttps, mode: LaunchMode.externalApplication)) {
      return true;
    }
    debugPrint(
      '[AppUpdate] store open unsupported platform=${kIsWeb ? 'web' : Platform.operatingSystem}',
    );
    return false;
  }
}
