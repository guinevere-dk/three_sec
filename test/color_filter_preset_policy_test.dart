import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/managers/video_manager.dart';
import 'package:three_s/models/vlog_project.dart';
import 'package:three_s/utils/color_filter_preset_policy.dart';

void main() {
  group('color filter preset policy', () {
    test('normalizes preset ids and intensity values', () {
      expect(
        normalizeColorFilterPresetId(kColorFilterPresetKoreanTravelPop),
        kColorFilterPresetKoreanTravelPop,
      );
      expect(normalizeColorFilterPresetId('missing'), kColorFilterPresetNone);
      expect(normalizeColorFilterPresetId(''), kColorFilterPresetNone);

      expect(normalizeColorFilterIntensity(null), 1.0);
      expect(normalizeColorFilterIntensity('0.45'), 0.45);
      expect(normalizeColorFilterIntensity(-1), 0.0);
      expect(normalizeColorFilterIntensity(2), 1.0);
    });

    test('export payload is emitted only for active LUT presets', () {
      expect(
        colorFilterForExportVideoEffects(
          presetId: kColorFilterPresetNone,
          intensity: 1.0,
        ),
        isEmpty,
      );
      expect(
        colorFilterForExportVideoEffects(
          presetId: kColorFilterPresetClearSky,
          intensity: 0.0,
        ),
        isEmpty,
      );

      final payload = colorFilterForExportVideoEffects(
        presetId: kColorFilterPresetClearSky,
        intensity: 0.75,
      );

      expect(payload['moaColorLutV1'], 1.0);
      expect(payload['colorFilterPresetId'], kColorFilterPresetClearSky);
      expect(payload['colorFilterIntensity'], 0.75);
      expect(payload['colorFilterLutAsset'], 'assets/luts/moa_clear_sky.cube');
    });

    test('preview adjustments scale with visibly strong intensity', () {
      final full = colorFilterPreviewAdjustments(
        presetId: kColorFilterPresetKoreanTravelPop,
        intensity: 1.0,
      );
      final half = colorFilterPreviewAdjustments(
        presetId: kColorFilterPresetKoreanTravelPop,
        intensity: 0.5,
      );

      expect(full['contrast'], 30.0);
      expect(full['saturation'], 46.0);
      expect(full['clarity'], 20.0);
      expect(half['contrast'], 15.0);
      expect(half['saturation'], 23.0);
      expect(half['clarity'], 10.0);
      expect(
        colorFilterPreviewAdjustments(
          presetId: kColorFilterPresetNone,
          intensity: 1.0,
        ),
        isEmpty,
      );
    });

    test('active presets have obvious preview strength at full intensity', () {
      for (final preset in kColorFilterPresetSpecs) {
        if (preset.id == kColorFilterPresetNone) continue;

        final adjustments = colorFilterPreviewAdjustments(
          presetId: preset.id,
          intensity: 1.0,
        );

        final saturation = adjustments['saturation'] ?? 0.0;
        final contrast = adjustments['contrast'] ?? 0.0;
        final clarity = adjustments['clarity'] ?? 0.0;
        expect(
          saturation.abs() + contrast.abs() + clarity.abs(),
          greaterThanOrEqualTo(50.0),
          reason: '${preset.id} should visibly change the preview at 100%',
        );
      }
    });
  });

  group('VlogProject color filter contract', () {
    test('missing color filter fields restore defaults', () {
      final project = VlogProject.fromJson({
        'id': 'project-1',
        'title': 'Project',
        'clips': const [],
        'createdAt': DateTime(2026, 5, 21).toIso8601String(),
        'updatedAt': DateTime(2026, 5, 21).toIso8601String(),
      });

      expect(project.colorFilterPresetId, kColorFilterPresetNone);
      expect(project.colorFilterIntensity, 1.0);
    });

    test('unknown preset ids are ignored when saving project JSON', () {
      final project = VlogProject.fromJson({
        'id': 'project-2',
        'title': 'Project',
        'clips': const [],
        'colorFilterPresetId': 'unknown',
        'colorFilterIntensity': '2',
        'createdAt': DateTime(2026, 5, 21).toIso8601String(),
        'updatedAt': DateTime(2026, 5, 21).toIso8601String(),
      });

      final json = project.toJson();

      expect(json['colorFilterPresetId'], kColorFilterPresetNone);
      expect(json['colorFilterIntensity'], 1.0);
    });

    test('clip-specific color filters round-trip per clip', () {
      final project = VlogProject.fromJson({
        'id': 'project-3',
        'title': 'Project',
        'colorFilterPresetId': kColorFilterPresetWarmSunset,
        'colorFilterIntensity': 0.4,
        'clips': const [
          {
            'id': 'clip-1',
            'path': 'clip_1.mp4',
            'colorFilterPresetId': kColorFilterPresetClearSky,
            'colorFilterIntensity': 0.65,
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

      expect(project.colorFilterPresetId, kColorFilterPresetWarmSunset);
      expect(project.colorFilterIntensity, 0.4);
      expect(project.clips[0].colorFilterPresetId, kColorFilterPresetClearSky);
      expect(project.clips[0].colorFilterIntensity, 0.65);
      expect(project.clips[1].colorFilterPresetId, kColorFilterPresetNone);
      expect(project.clips[1].colorFilterIntensity, 1.0);
      expect(firstClip['colorFilterPresetId'], kColorFilterPresetClearSky);
      expect(firstClip['colorFilterIntensity'], 0.65);
      expect(secondClip['colorFilterPresetId'], kColorFilterPresetNone);
      expect(secondClip['colorFilterIntensity'], 1.0);
    });

    test('project copy preserves clip-specific color filters', () {
      final project = VlogProject(
        id: 'project-4',
        title: 'Project',
        clips: [
          VlogClip(
            id: 'clip-1',
            path: 'clip_1.mp4',
            colorFilterPresetId: kColorFilterPresetClearSky,
            colorFilterIntensity: 0.7,
          ),
          VlogClip(
            id: 'clip-2',
            path: 'clip_2.mp4',
            colorFilterPresetId: kColorFilterPresetFilmGreen,
            colorFilterIntensity: 0.25,
          ),
        ],
        colorFilterPresetId: kColorFilterPresetWarmSunset,
        colorFilterIntensity: 0.5,
        createdAt: DateTime(2026, 5, 21),
        updatedAt: DateTime(2026, 5, 21),
      );

      final copied = debugBuildCopiedProjectForFolder(
        project: project,
        targetFolder: 'target',
        timestamp: DateTime(2026, 6, 5, 12),
      );
      final reopened = VlogProject.fromJson(copied.toJson());

      expect(reopened.colorFilterPresetId, kColorFilterPresetWarmSunset);
      expect(reopened.colorFilterIntensity, 0.5);
      expect(reopened.clips[0].colorFilterPresetId, kColorFilterPresetClearSky);
      expect(reopened.clips[0].colorFilterIntensity, 0.7);
      expect(
        reopened.clips[1].colorFilterPresetId,
        kColorFilterPresetFilmGreen,
      );
      expect(reopened.clips[1].colorFilterIntensity, 0.25);
      expect(reopened.clips[0].path, project.clips[0].path);
      expect(reopened.clips[0].id, isNot(project.clips[0].id));
    });

    test(
      'mixed clip filters keep project fallback separate from clip state',
      () {
        final project = VlogProject(
          id: 'project-5',
          title: 'Project',
          clips: [
            VlogClip(
              id: 'clip-1',
              path: 'clip_1.mp4',
              colorFilterPresetId: kColorFilterPresetClearSky,
              colorFilterIntensity: 0.7,
            ),
            VlogClip(id: 'clip-2', path: 'clip_2.mp4'),
          ],
          colorFilterPresetId: kColorFilterPresetWarmSunset,
          colorFilterIntensity: 0.5,
          createdAt: DateTime(2026, 5, 21),
          updatedAt: DateTime(2026, 5, 21),
        );

        expect(hasActiveClipColorFilters(project.clips), isTrue);

        final reopened = VlogProject.fromJson(project.toJson());
        expect(reopened.colorFilterPresetId, kColorFilterPresetWarmSunset);
        expect(reopened.colorFilterIntensity, 0.5);
        expect(
          reopened.clips[0].colorFilterPresetId,
          kColorFilterPresetClearSky,
        );
        expect(reopened.clips[0].colorFilterIntensity, 0.7);
        expect(reopened.clips[1].colorFilterPresetId, kColorFilterPresetNone);
        expect(reopened.clips[1].colorFilterIntensity, 1.0);
      },
    );
  });
}
