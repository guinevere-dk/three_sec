import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart' as play_update;
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
  final int? latestBuildNumber;
  final int? minimumRequiredBuildNumber;
  final SemanticVersion? latestCandidateVersion;
  final int? latestCandidateBuildNumber;
  final String? candidateStatus;
  final String? playStoreUrl;
  final String? message;

  const AppUpdateConfig({
    this.latestVersion,
    this.minimumRequiredVersion,
    this.latestBuildNumber,
    this.minimumRequiredBuildNumber,
    this.latestCandidateVersion,
    this.latestCandidateBuildNumber,
    this.candidateStatus,
    this.playStoreUrl,
    this.message,
  });

  factory AppUpdateConfig.fromJson(Map<String, dynamic> json) {
    final latestPublished = _stringValue(
      json['latestPublishedVersion'] ??
          json['latest_published_version'] ??
          json['latestVersion'] ??
          json['latest_version'],
    );
    final hasModernMinimumBuildPolicy = _hasAnyValue(json, [
      'minSupportedBuild',
      'min_supported_build',
      'forceUpdateMinBuild',
      'force_update_min_build',
    ]);
    final minimum = hasModernMinimumBuildPolicy
        ? null
        : _stringValue(
            json['minimumRequiredVersion'] ?? json['minimum_required_version'],
          );
    final latestCandidate = _stringValue(
      json['latestCandidateVersion'] ??
          json['candidateVersion'] ??
          json['latest_candidate_version'] ??
          json['candidate_version'],
    );
    final minimumBuildNumber =
        _maxBuildValue([
          json['minSupportedBuild'],
          json['min_supported_build'],
          json['forceUpdateMinBuild'],
          json['force_update_min_build'],
        ]) ??
        _maxBuildValue([
          json['minimumRequiredBuildNumber'],
          json['minimumRequiredVersionCode'],
          json['minimum_required_build_number'],
          json['minimum_required_version_code'],
        ]);
    return AppUpdateConfig(
      latestVersion: _parseNullableVersion(
        latestPublished,
        'latestPublishedVersion',
      ),
      minimumRequiredVersion: _parseNullableVersion(
        minimum,
        'minimumRequiredVersion',
      ),
      latestBuildNumber: _intValue(
        json['latestPublishedBuild'] ??
            json['latestPublishedBuildNumber'] ??
            json['latest_published_build'] ??
            json['latest_published_build_number'] ??
            json['latestBuildNumber'] ??
            json['latestVersionCode'] ??
            json['latest_build_number'] ??
            json['latest_version_code'],
      ),
      minimumRequiredBuildNumber: minimumBuildNumber,
      latestCandidateVersion: _parseNullableVersion(
        latestCandidate,
        'latestCandidateVersion',
      ),
      latestCandidateBuildNumber: _intValue(
        json['latestCandidateBuild'] ??
            json['candidateBuild'] ??
            json['latestCandidateBuildNumber'] ??
            json['latest_candidate_build'] ??
            json['candidate_build'] ??
            json['latest_candidate_build_number'],
      ),
      candidateStatus: _stringValue(
        json['candidateStatus'] ?? json['candidate_status'],
      ),
      playStoreUrl: _stringValue(
        json['playStoreUrl'] ?? json['play_store_url'],
      ),
      message: _stringValue(json['message']),
    );
  }

  static int? _maxBuildValue(List<dynamic> values) {
    int? max;
    for (final value in values) {
      final parsed = _intValue(value);
      if (parsed == null) continue;
      if (max == null || parsed > max) max = parsed;
    }
    return max;
  }

  static bool _hasAnyValue(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      if (json.containsKey(key) && json[key] != null) return true;
    }
    return false;
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

  static int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is! String) return null;
    return int.tryParse(value.trim());
  }
}

@immutable
class AppUpdateStatus {
  final AppUpdateType type;
  final SemanticVersion currentVersion;
  final int? currentBuildNumber;
  final AppUpdateConfig? config;
  final play_update.AppUpdateInfo? playUpdateInfo;

  const AppUpdateStatus({
    required this.type,
    required this.currentVersion,
    this.currentBuildNumber,
    this.config,
    this.playUpdateInfo,
  });

  bool get hasUpdate => type != AppUpdateType.none;
  bool get isForced => type == AppUpdateType.forced;
  bool get hasNativePlayUpdate => _hasNativePlayUpdate(playUpdateInfo);
  bool get hasDownloadedFlexibleUpdate =>
      playUpdateInfo?.installStatus == play_update.InstallStatus.downloaded;
  bool get isDeveloperTriggeredUpdateInProgress =>
      playUpdateInfo?.updateAvailability ==
      play_update.UpdateAvailability.developerTriggeredUpdateInProgress;

  String get optionalPromptKey {
    final latest = config?.latestVersion?.toString();
    if (latest != null) return 'version:$latest';
    final latestBuild = config?.latestBuildNumber;
    if (latestBuild != null) return 'build:$latestBuild';
    final playBuild = playUpdateInfo?.availableVersionCode;
    if (playBuild != null) return 'play:$playBuild';
    return 'play:update-available';
  }

  static bool _hasNativePlayUpdate(play_update.AppUpdateInfo? info) {
    if (info == null) return false;
    return info.updateAvailability ==
            play_update.UpdateAvailability.updateAvailable ||
        info.updateAvailability ==
            play_update.UpdateAvailability.developerTriggeredUpdateInProgress ||
        info.installStatus == play_update.InstallStatus.downloaded;
  }
}

enum _UpdateLaunchResult { started, openedStore, userCancelled, failed }

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static const Duration _updateCheckTimeout = Duration(seconds: 4);

  AppUpdateStatus? _lastStatus;
  String? _lastOptionalPromptVersion;
  bool _isDialogShowing = false;
  bool _isNativeUpdateFlowRunning = false;
  StreamSubscription<play_update.InstallStatus>? _flexibleUpdateSubscription;

  AppUpdateStatus classifyUpdate({
    required SemanticVersion currentVersion,
    int? currentBuildNumber,
    AppUpdateConfig? config,
    play_update.AppUpdateInfo? playUpdateInfo,
  }) {
    final configType = config == null
        ? AppUpdateType.none
        : _resolveUpdateType(
            currentVersion: currentVersion,
            currentBuildNumber: currentBuildNumber,
            latestVersion: config.latestVersion,
            minimumRequiredVersion: config.minimumRequiredVersion,
            latestBuildNumber: config.latestBuildNumber,
            minimumRequiredBuildNumber: config.minimumRequiredBuildNumber,
          );
    final nativeType = AppUpdateStatus._hasNativePlayUpdate(playUpdateInfo)
        ? AppUpdateType.optional
        : AppUpdateType.none;
    final type = configType == AppUpdateType.forced
        ? AppUpdateType.forced
        : (configType == AppUpdateType.optional ||
              nativeType == AppUpdateType.optional)
        ? AppUpdateType.optional
        : AppUpdateType.none;
    return AppUpdateStatus(
      type: type,
      currentVersion: currentVersion,
      currentBuildNumber: currentBuildNumber,
      config: config,
      playUpdateInfo: playUpdateInfo,
    );
  }

  AppUpdateType _resolveUpdateType({
    required SemanticVersion currentVersion,
    required int? currentBuildNumber,
    required SemanticVersion? latestVersion,
    required SemanticVersion? minimumRequiredVersion,
    required int? latestBuildNumber,
    required int? minimumRequiredBuildNumber,
  }) {
    if (minimumRequiredBuildNumber != null &&
        currentBuildNumber != null &&
        currentBuildNumber < minimumRequiredBuildNumber) {
      return AppUpdateType.forced;
    }
    if (minimumRequiredVersion != null &&
        currentVersion.compareTo(minimumRequiredVersion) < 0) {
      return AppUpdateType.forced;
    }
    if (latestBuildNumber != null &&
        currentBuildNumber != null &&
        currentBuildNumber < latestBuildNumber) {
      return AppUpdateType.optional;
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
    final currentBuildNumber = int.tryParse(info.buildNumber);

    final configFuture = _fetchRemoteConfig();
    final playUpdateInfoFuture = _checkPlayUpdateInfo();
    final config = await configFuture;
    final playUpdateInfo = await playUpdateInfoFuture;

    _lastStatus = classifyUpdate(
      currentVersion: currentVersion,
      currentBuildNumber: currentBuildNumber,
      config: config,
      playUpdateInfo: playUpdateInfo,
    );
    debugPrint(
      '[AppUpdate] current=$currentVersion+$currentBuildNumber '
      'published=${config?.latestVersion}+${config?.latestBuildNumber} '
      'minimum=${config?.minimumRequiredVersion}+${config?.minimumRequiredBuildNumber} '
      'playAvailability=${playUpdateInfo?.updateAvailability.name} '
      'playAvailableVersionCode=${playUpdateInfo?.availableVersionCode} '
      'type=${_lastStatus!.type.name}',
    );
    return _lastStatus;
  }

  Future<AppUpdateConfig?> _fetchRemoteConfig() async {
    if (kAppUpdateConfigUrl.isEmpty) {
      debugPrint(
        '[AppUpdate] APP_UPDATE_CONFIG_URL is empty. remote config skipped.',
      );
      return null;
    }

    try {
      final uri = Uri.parse(kAppUpdateConfigUrl);
      final response = await http.get(uri).timeout(_updateCheckTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          '[AppUpdate] config fetch skipped status=${response.statusCode}',
        );
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('update config root must be an object');
      }

      return AppUpdateConfig.fromJson(decoded);
    } catch (e, st) {
      debugPrint('[AppUpdate] remote config check failed: $e');
      debugPrint('[AppUpdate][RemoteConfigStack]\n$st');
      return null;
    }
  }

  Future<play_update.AppUpdateInfo?> _checkPlayUpdateInfo() async {
    if (kIsWeb || !Platform.isAndroid) return null;

    try {
      final info = await play_update.InAppUpdate.checkForUpdate().timeout(
        _updateCheckTimeout,
      );
      debugPrint(
        '[AppUpdate][Play] availability=${info.updateAvailability.name} '
        'immediateAllowed=${info.immediateUpdateAllowed} '
        'flexibleAllowed=${info.flexibleUpdateAllowed} '
        'availableVersionCode=${info.availableVersionCode} '
        'installStatus=${info.installStatus.name} '
        'stalenessDays=${info.clientVersionStalenessDays} '
        'priority=${info.updatePriority}',
      );
      return info;
    } catch (e, st) {
      debugPrint('[AppUpdate][Play] check failed: $e');
      debugPrint('[AppUpdate][PlayStack]\n$st');
      return null;
    }
  }

  Future<void> checkAndPromptOnEntry(BuildContext context) async {
    final status = await checkForUpdate(forceRefresh: true);
    if (status == null || !context.mounted || !status.hasUpdate) return;
    if (status.isDeveloperTriggeredUpdateInProgress) {
      await _startNativePlayUpdate(status);
      return;
    }
    if (!status.isForced) {
      final promptKey = status.optionalPromptKey;
      if (_lastOptionalPromptVersion == promptKey) return;
      _lastOptionalPromptVersion = promptKey;
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
    final latestText = _latestVersionText(status);
    final currentText = _currentVersionText(status);
    final message = status.config?.message;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !isForced,
        builder: (dialogContext) {
          var isStartingUpdate = false;
          String? errorText;
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) => PopScope(
              canPop: !isForced && !isStartingUpdate,
              child: AlertDialog(
                title: Text(isForced ? '업데이트가 필요합니다' : '업데이트할 수 있습니다'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isForced
                          ? '계속 사용하려면 최신 버전으로 업데이트해야 합니다.'
                          : 'Google Play에 배포된 버전으로 업데이트할 수 있습니다.',
                    ),
                    const SizedBox(height: 10),
                    Text('현재 버전: $currentText'),
                    if (latestText != null) Text('최신 버전: $latestText'),
                    if (message != null) ...[
                      const SizedBox(height: 10),
                      Text(message),
                    ],
                    if (status.hasNativePlayUpdate) ...[
                      const SizedBox(height: 10),
                      const Text('업데이트는 Google Play에서 안전하게 진행됩니다.'),
                    ],
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  if (!isForced)
                    TextButton(
                      onPressed: isStartingUpdate
                          ? null
                          : () => Navigator.pop(dialogContext),
                      child: Text(manual ? '닫기' : '나중에'),
                    ),
                  FilledButton(
                    onPressed: isStartingUpdate
                        ? null
                        : () async {
                            setDialogState(() {
                              isStartingUpdate = true;
                              errorText = null;
                            });
                            final result = await _launchUpdate(status);
                            if (!dialogContext.mounted) return;

                            if (result == _UpdateLaunchResult.started ||
                                result == _UpdateLaunchResult.openedStore ||
                                (!isForced &&
                                    result ==
                                        _UpdateLaunchResult.userCancelled)) {
                              Navigator.pop(dialogContext);
                              return;
                            }

                            setDialogState(() {
                              isStartingUpdate = false;
                              errorText =
                                  result == _UpdateLaunchResult.userCancelled
                                  ? '업데이트가 취소되었습니다. 계속 사용하려면 업데이트가 필요합니다.'
                                  : '업데이트를 시작하지 못했습니다. 잠시 후 다시 시도해 주세요.';
                            });
                          },
                    child: isStartingUpdate
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('업데이트'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      _isDialogShowing = false;
    }
  }

  String _currentVersionText(AppUpdateStatus status) {
    final build = status.currentBuildNumber;
    if (build == null) return 'v${status.currentVersion}';
    return 'v${status.currentVersion}+$build';
  }

  String? _latestVersionText(AppUpdateStatus status) {
    final version = status.config?.latestVersion;
    final build =
        status.config?.latestBuildNumber ??
        status.playUpdateInfo?.availableVersionCode;
    if (version != null && build != null) return 'v$version+$build';
    if (version != null) return 'v$version';
    if (build != null) return '빌드 $build';
    return null;
  }

  Future<_UpdateLaunchResult> _launchUpdate(AppUpdateStatus status) async {
    final nativeResult = await _startNativePlayUpdate(status);
    if (nativeResult == _UpdateLaunchResult.started ||
        nativeResult == _UpdateLaunchResult.userCancelled) {
      return nativeResult;
    }

    final opened = await openStore(status.config?.playStoreUrl);
    return opened
        ? _UpdateLaunchResult.openedStore
        : _UpdateLaunchResult.failed;
  }

  Future<_UpdateLaunchResult> _startNativePlayUpdate(
    AppUpdateStatus status,
  ) async {
    if (!status.hasNativePlayUpdate || kIsWeb || !Platform.isAndroid) {
      return _UpdateLaunchResult.failed;
    }
    if (_isNativeUpdateFlowRunning) return _UpdateLaunchResult.started;

    final updateInfo = status.playUpdateInfo!;
    _isNativeUpdateFlowRunning = true;
    try {
      if (status.hasDownloadedFlexibleUpdate) {
        await play_update.InAppUpdate.completeFlexibleUpdate();
        return _UpdateLaunchResult.started;
      }

      if (status.isDeveloperTriggeredUpdateInProgress ||
          updateInfo.immediateUpdateAllowed) {
        final result = await play_update.InAppUpdate.performImmediateUpdate();
        debugPrint('[AppUpdate][Play] immediate result=${result.name}');
        if (result == play_update.AppUpdateResult.userDeniedUpdate) {
          return _UpdateLaunchResult.userCancelled;
        }
        if (result == play_update.AppUpdateResult.inAppUpdateFailed) {
          return _UpdateLaunchResult.failed;
        }
        return _UpdateLaunchResult.started;
      }

      if (updateInfo.flexibleUpdateAllowed) {
        _ensureFlexibleUpdateCompletionListener();
        final result = await play_update.InAppUpdate.startFlexibleUpdate();
        debugPrint('[AppUpdate][Play] flexible result=${result.name}');
        if (result == play_update.AppUpdateResult.userDeniedUpdate) {
          return _UpdateLaunchResult.userCancelled;
        }
        if (result == play_update.AppUpdateResult.inAppUpdateFailed) {
          return _UpdateLaunchResult.failed;
        }
        return _UpdateLaunchResult.started;
      }

      debugPrint(
        '[AppUpdate][Play] update available but no allowed flow: '
        'immediatePreconditions=${updateInfo.immediateAllowedPreconditions} '
        'flexiblePreconditions=${updateInfo.flexibleAllowedPreconditions}',
      );
      return _UpdateLaunchResult.failed;
    } catch (e, st) {
      debugPrint('[AppUpdate][Play] start failed: $e');
      debugPrint('[AppUpdate][PlayStartStack]\n$st');
      return _UpdateLaunchResult.failed;
    } finally {
      _isNativeUpdateFlowRunning = false;
    }
  }

  void _ensureFlexibleUpdateCompletionListener() {
    _flexibleUpdateSubscription ??= play_update
        .InAppUpdate
        .installUpdateListener
        .listen(
          (status) {
            debugPrint(
              '[AppUpdate][Play] flexible install status=${status.name}',
            );
            if (status == play_update.InstallStatus.downloaded) {
              unawaited(_completeFlexibleUpdateFromListener());
            }
          },
          onError: (Object e) {
            debugPrint(
              '[AppUpdate][Play] flexible install listener failed: $e',
            );
          },
        );
  }

  Future<void> _completeFlexibleUpdateFromListener() async {
    try {
      await play_update.InAppUpdate.completeFlexibleUpdate();
    } catch (e, st) {
      debugPrint('[AppUpdate][Play] flexible completion failed: $e');
      debugPrint('[AppUpdate][PlayFlexibleCompletionStack]\n$st');
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
