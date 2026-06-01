import 'package:flutter_test/flutter_test.dart';
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

    test('preview adjustments scale with intensity', () {
      final full = colorFilterPreviewAdjustments(
        presetId: kColorFilterPresetKoreanTravelPop,
        intensity: 1.0,
      );
      final half = colorFilterPreviewAdjustments(
        presetId: kColorFilterPresetKoreanTravelPop,
        intensity: 0.5,
      );

      expect(full['saturation'], 16.0);
      expect(half['saturation'], 8.0);
      expect(
        colorFilterPreviewAdjustments(
          presetId: kColorFilterPresetNone,
          intensity: 1.0,
        ),
        isEmpty,
      );
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
  });
}
