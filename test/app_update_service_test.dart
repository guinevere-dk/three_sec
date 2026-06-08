import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart' as play_update;
import 'package:three_s/services/app_update_service.dart';

void main() {
  group('AppUpdateService', () {
    final service = AppUpdateService.instance;

    test('parses optional version code fields from remote config', () {
      final config = AppUpdateConfig.fromJson({
        'latestVersion': '2.1.4',
        'minimumRequiredVersion': '2.1.2',
        'latestVersionCode': '214',
        'minimumRequiredVersionCode': 210,
        'playStoreUrl': 'https://play.google.com/store/apps/details?id=test',
      });

      expect(config.latestVersion.toString(), '2.1.4');
      expect(config.minimumRequiredVersion.toString(), '2.1.2');
      expect(config.latestBuildNumber, 214);
      expect(config.minimumRequiredBuildNumber, 210);
    });

    test('uses latest published build instead of release candidate', () {
      final config = AppUpdateConfig.fromJson({
        'latestPublishedVersion': '2.1.8',
        'latestPublishedBuild': 218,
        'latestCandidateVersion': '2.1.9',
        'latestCandidateBuild': 219,
        'candidateStatus': 'in_review',
      });

      final status = service.classifyUpdate(
        currentVersion: SemanticVersion.parse('2.1.8'),
        currentBuildNumber: 218,
        config: config,
      );

      expect(status.type, AppUpdateType.none);
      expect(status.optionalPromptKey, 'version:2.1.8');
    });

    test('published fields override stale legacy latest fields', () {
      final config = AppUpdateConfig.fromJson({
        'latestPublishedVersion': '2.1.8',
        'latestPublishedBuild': 218,
        'latestVersion': '2.1.9',
        'latestVersionCode': 219,
        'latestCandidateVersion': '2.1.9',
        'latestCandidateBuild': 219,
        'candidateStatus': 'in_review',
      });

      final status = service.classifyUpdate(
        currentVersion: SemanticVersion.parse('2.1.8'),
        currentBuildNumber: 218,
        config: config,
      );

      expect(status.type, AppUpdateType.none);
      expect(status.optionalPromptKey, 'version:2.1.8');
    });

    test('classifies optional update from latest published build', () {
      final config = AppUpdateConfig.fromJson({
        'latestPublishedVersion': '2.1.9',
        'latestPublishedBuild': 219,
        'latestCandidateVersion': '2.2.0',
        'latestCandidateBuild': 220,
        'candidateStatus': 'in_review',
      });

      final status = service.classifyUpdate(
        currentVersion: SemanticVersion.parse('2.1.8'),
        currentBuildNumber: 218,
        config: config,
      );

      expect(status.type, AppUpdateType.optional);
      expect(status.optionalPromptKey, 'version:2.1.9');
    });

    test('classifies forced update from min supported build', () {
      final status = service.classifyUpdate(
        currentVersion: SemanticVersion.parse('2.1.8'),
        currentBuildNumber: 217,
        config: AppUpdateConfig.fromJson({'minSupportedBuild': 218}),
      );

      expect(status.type, AppUpdateType.forced);
      expect(status.isForced, isTrue);
    });

    test('classifies forced update from force update minimum build', () {
      final status = service.classifyUpdate(
        currentVersion: SemanticVersion.parse('2.1.8'),
        currentBuildNumber: 217,
        config: AppUpdateConfig.fromJson({'forceUpdateMinBuild': 218}),
      );

      expect(status.type, AppUpdateType.forced);
      expect(status.isForced, isTrue);
    });

    test('published minimum build overrides stale legacy minimum build', () {
      final config = AppUpdateConfig.fromJson({
        'minSupportedBuild': 218,
        'forceUpdateMinBuild': 0,
        'minimumRequiredVersionCode': 219,
      });

      final status = service.classifyUpdate(
        currentVersion: SemanticVersion.parse('2.1.8'),
        currentBuildNumber: 218,
        config: config,
      );

      expect(status.type, AppUpdateType.none);
    });

    test('published minimum build overrides stale legacy minimum version', () {
      final config = AppUpdateConfig.fromJson({
        'minSupportedBuild': 218,
        'forceUpdateMinBuild': 0,
        'minimumRequiredVersion': '2.1.9',
      });

      final status = service.classifyUpdate(
        currentVersion: SemanticVersion.parse('2.1.8'),
        currentBuildNumber: 218,
        config: config,
      );

      expect(status.type, AppUpdateType.none);
    });

    test('ignores candidate-only config for user-visible prompts', () {
      final config = AppUpdateConfig.fromJson({
        'latestCandidateVersion': '2.1.9',
        'latestCandidateBuild': 219,
        'candidateStatus': 'in_review',
      });

      final status = service.classifyUpdate(
        currentVersion: SemanticVersion.parse('2.1.8'),
        currentBuildNumber: 218,
        config: config,
      );

      expect(status.type, AppUpdateType.none);
      expect(status.hasUpdate, isFalse);
    });

    test('classifies forced update by minimum build number', () {
      final status = service.classifyUpdate(
        currentVersion: SemanticVersion.parse('2.1.3'),
        currentBuildNumber: 213,
        config: const AppUpdateConfig(minimumRequiredBuildNumber: 214),
      );

      expect(status.type, AppUpdateType.forced);
      expect(status.isForced, isTrue);
    });

    test('classifies Play Core update as optional without remote config', () {
      final status = service.classifyUpdate(
        currentVersion: SemanticVersion.parse('2.1.3'),
        currentBuildNumber: 213,
        playUpdateInfo: _playUpdateInfo(availableVersionCode: 214),
      );

      expect(status.type, AppUpdateType.optional);
      expect(status.hasNativePlayUpdate, isTrue);
      expect(status.optionalPromptKey, 'play:214');
    });

    test('keeps remote forced policy when Play Core also has an update', () {
      final status = service.classifyUpdate(
        currentVersion: SemanticVersion.parse('2.1.3'),
        currentBuildNumber: 213,
        config: const AppUpdateConfig(minimumRequiredBuildNumber: 214),
        playUpdateInfo: _playUpdateInfo(availableVersionCode: 214),
      );

      expect(status.type, AppUpdateType.forced);
      expect(status.hasNativePlayUpdate, isTrue);
    });
  });
}

play_update.AppUpdateInfo _playUpdateInfo({required int availableVersionCode}) {
  return play_update.AppUpdateInfo(
    updateAvailability: play_update.UpdateAvailability.updateAvailable,
    immediateUpdateAllowed: true,
    immediateAllowedPreconditions: null,
    flexibleUpdateAllowed: true,
    flexibleAllowedPreconditions: null,
    availableVersionCode: availableVersionCode,
    installStatus: play_update.InstallStatus.unknown,
    packageName: 'com.dk.three_sec',
    clientVersionStalenessDays: null,
    updatePriority: 0,
  );
}
