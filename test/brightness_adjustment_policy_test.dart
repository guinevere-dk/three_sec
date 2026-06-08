import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/managers/video_manager.dart';
import 'package:three_s/models/vlog_project.dart';
import 'package:three_s/utils/brightness_adjustment_policy.dart';

void main() {
  group('brightness adjustment policy', () {
    test('normalizes missing, unknown, string, and out-of-range values', () {
      final normalized = normalizeBrightnessAdjustments({
        'brightness': 24,
        'contrast': '45.5',
        'saturation': 125,
        'unknown': 99,
      });

      expect(normalized['brightness'], 24);
      expect(normalized['contrast'], 45.5);
      expect(normalized['saturation'], 100);
      expect(normalized['exposure'], 0);
      expect(normalized.containsKey('unknown'), isFalse);
      expect(normalized.keys, hasLength(kBrightnessAdjustmentSpecs.length));
    });

    test('native payload uses the centralized native keys', () {
      final payload = brightnessAdjustmentsForNativePayload({
        'brightness': 10,
        'temperature': -12,
      });

      expect(payload['brightness'], 10);
      expect(payload['temperature'], -12);
      expect(payload['clarity'], 0);
      expect(payload.keys, hasLength(kBrightnessAdjustmentSpecs.length));
    });

    test('export video effects include all supported dirty keys only', () {
      final payload = brightnessAdjustmentsForExportVideoEffects({
        'brightness': 10,
        'contrast': 0,
        'saturation': -20,
        'temperature': 12,
        'highlights': 100,
        'shadows': -40,
        'sharpness': 25,
        'clarity': 50,
      });

      expect(payload['moaColorAdjustmentV1'], 1);
      expect(payload['brightness'], 10);
      expect(payload['saturation'], -20);
      expect(payload['temperature'], 12);
      expect(payload['highlights'], 100);
      expect(payload['shadows'], -40);
      expect(payload['sharpness'], 25);
      expect(payload['clarity'], 50);
      expect(payload.containsKey('contrast'), isFalse);
    });

    test('preview exposes supported color controls only', () {
      final keys = brightnessPreviewAdjustmentSpecs()
          .map((spec) => spec.key)
          .toList();

      expect(keys, <String>[
        'brightness',
        'exposure',
        'contrast',
        'highlights',
        'shadows',
        'saturation',
        'tint',
        'temperature',
        'sharpness',
        'clarity',
      ]);
      expect(isBrightnessPreviewAdjustmentKey('highlights'), isTrue);
      expect(isBrightnessPreviewAdjustmentKey('clarity'), isTrue);
    });

    test('default preview matrix is identity', () {
      expect(
        brightnessPreviewColorMatrix(const <String, double>{}),
        kIdentityBrightnessPreviewMatrix,
      );
    });

    test('preview matrix reflects supported adjustments', () {
      final matrix = brightnessPreviewColorMatrix({
        'brightness': 40,
        'contrast': 25,
        'saturation': -30,
        'exposure': 20,
        'temperature': 50,
        'tint': -20,
      });

      expect(matrix, isNot(kIdentityBrightnessPreviewMatrix));
      expect(matrix, hasLength(20));
      expect(matrix[0], isNot(1));
      expect(matrix[4], isNot(0));
      expect(matrix[6], isNot(1));
      expect(matrix[12], isNot(1));
    });

    test('advanced adjustments affect Flutter preview after native parity', () {
      final matrix = brightnessPreviewColorMatrix({
        'highlights': 100,
        'shadows': -100,
        'sharpness': 80,
        'clarity': 60,
      });

      expect(matrix, isNot(kIdentityBrightnessPreviewMatrix));
      expect(matrix, hasLength(20));
    });
  });

  group('VlogProject brightness contract', () {
    test('missing brightness map restores project-wide defaults', () {
      final project = VlogProject.fromJson({
        'id': 'project-1',
        'title': 'Project',
        'clips': const [],
        'createdAt': DateTime(2026, 5, 21).toIso8601String(),
        'updatedAt': DateTime(2026, 5, 21).toIso8601String(),
      });

      expect(
        project.brightnessAdjustmentScope,
        kBrightnessAdjustmentScopeProjectWide,
      );
      expect(project.brightnessAdjustments['brightness'], 0);
      expect(project.brightnessAdjustments['clarity'], 0);
    });

    test('unknown brightness keys are ignored when saving project JSON', () {
      final project = VlogProject.fromJson({
        'id': 'project-2',
        'title': 'Project',
        'clips': const [],
        'brightnessAdjustmentScope': 'clip_specific',
        'brightnessAdjustments': const {'brightness': 12, 'unknown': 50},
        'createdAt': DateTime(2026, 5, 21).toIso8601String(),
        'updatedAt': DateTime(2026, 5, 21).toIso8601String(),
      });

      final json = project.toJson();
      final brightness = json['brightnessAdjustments'] as Map<String, Object?>;

      expect(
        json['brightnessAdjustmentScope'],
        kBrightnessAdjustmentScopeClipSpecific,
      );
      expect(brightness['brightness'], 12);
      expect(brightness['exposure'], 0);
      expect(brightness.containsKey('unknown'), isFalse);
    });

    test('clip-specific brightness maps round-trip per clip', () {
      final project = VlogProject.fromJson({
        'id': 'project-3',
        'title': 'Project',
        'brightnessAdjustmentScope': 'clip_specific',
        'brightnessAdjustments': const {'brightness': 8},
        'clips': const [
          {
            'id': 'clip-1',
            'path': 'clip_1.mp4',
            'brightnessAdjustments': {'brightness': 32, 'unknown': 99},
          },
          {'id': 'clip-2', 'path': 'clip_2.mp4'},
        ],
        'createdAt': DateTime(2026, 5, 21).toIso8601String(),
        'updatedAt': DateTime(2026, 5, 21).toIso8601String(),
      });

      final json = project.toJson();
      final clips = json['clips'] as List<Object?>;
      final firstClip = clips.first as Map<String, Object?>;
      final secondClip = clips[1] as Map<String, Object?>;
      final firstBrightness =
          firstClip['brightnessAdjustments'] as Map<String, Object?>;
      final secondBrightness =
          secondClip['brightnessAdjustments'] as Map<String, Object?>;

      expect(project.brightnessAdjustmentScope, 'clip_specific');
      expect(json['brightnessAdjustmentScope'], 'clip_specific');
      expect(firstBrightness['brightness'], 32);
      expect(firstBrightness.containsKey('unknown'), isFalse);
      expect(secondBrightness['brightness'], 0);
    });

    test('project copy preserves clip-specific brightness maps', () {
      final project = VlogProject(
        id: 'project-4',
        title: 'Project',
        clips: [
          VlogClip(
            id: 'clip-1',
            path: 'clip_1.mp4',
            brightnessAdjustments: const {'brightness': 32},
          ),
          VlogClip(
            id: 'clip-2',
            path: 'clip_2.mp4',
            brightnessAdjustments: const {'brightness': -18},
          ),
        ],
        brightnessAdjustmentScope: kBrightnessAdjustmentScopeClipSpecific,
        brightnessAdjustments: const {'brightness': 8},
        createdAt: DateTime(2026, 5, 21),
        updatedAt: DateTime(2026, 5, 21),
      );

      final copied = debugBuildCopiedProjectForFolder(
        project: project,
        targetFolder: 'target',
        timestamp: DateTime(2026, 6, 5, 12),
      );
      final reopened = VlogProject.fromJson(copied.toJson());

      expect(reopened.folderName, 'target');
      expect(
        reopened.brightnessAdjustmentScope,
        kBrightnessAdjustmentScopeClipSpecific,
      );
      expect(reopened.brightnessAdjustments['brightness'], 8);
      expect(reopened.clips[0].brightnessAdjustments['brightness'], 32);
      expect(reopened.clips[1].brightnessAdjustments['brightness'], -18);
      expect(reopened.clips[0].path, project.clips[0].path);
      expect(reopened.clips[0].id, isNot(project.clips[0].id));
    });
  });

  group('export audio contract', () {
    test('clip-index volumes preserve duplicate source paths', () {
      final clips = [
        VlogClip(id: 'clip-1', path: 'same_source.mp4', volume: 0.25),
        VlogClip(id: 'clip-2', path: 'same_source.mp4', volume: 0.75),
      ];

      final originalVolumes = buildOriginalAudioVolumesByClip(
        clips: clips,
        originalAudioVolume: 0.8,
      );
      final resolvedVolumes = resolveOriginalAudioVolumesByClip(
        clips: clips,
        audioConfig: const {'same_source.mp4': 0.6},
        originalAudioVolumes: originalVolumes,
      );

      expect(originalVolumes[0], closeTo(0.2, 0.0001));
      expect(originalVolumes[1], closeTo(0.6, 0.0001));
      expect(resolvedVolumes, originalVolumes);
      expect(
        resolvedVolumes.toSet(),
        hasLength(2),
        reason:
            'Duplicate source paths must still keep distinct per-clip gains.',
      );
    });
  });
}
