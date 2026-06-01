const String kColorFilterPresetNone = 'none';
const String kColorFilterPresetClearSky = 'clear_sky';
const String kColorFilterPresetWarmSunset = 'warm_sunset';
const String kColorFilterPresetFilmGreen = 'film_green';
const String kColorFilterPresetKoreanTravelPop = 'korean_travel_pop';
const String kColorFilterPresetCityNightWarm = 'city_night_warm';

const double kColorFilterIntensityDefault = 1.0;

class ColorFilterPresetSpec {
  final String id;
  final String label;
  final String? lutAsset;
  final Map<String, double> previewAdjustments;

  const ColorFilterPresetSpec({
    required this.id,
    required this.label,
    this.lutAsset,
    this.previewAdjustments = const <String, double>{},
  });
}

const List<ColorFilterPresetSpec> kColorFilterPresetSpecs =
    <ColorFilterPresetSpec>[
      ColorFilterPresetSpec(id: kColorFilterPresetNone, label: '원본'),
      ColorFilterPresetSpec(
        id: kColorFilterPresetClearSky,
        label: '청량',
        lutAsset: 'assets/luts/moa_clear_sky.cube',
        previewAdjustments: <String, double>{
          'exposure': 4.0,
          'contrast': 6.0,
          'saturation': 10.0,
          'temperature': -4.0,
          'tint': -2.0,
          'highlights': -6.0,
          'shadows': 8.0,
          'clarity': 6.0,
        },
      ),
      ColorFilterPresetSpec(
        id: kColorFilterPresetWarmSunset,
        label: '노을',
        lutAsset: 'assets/luts/moa_warm_sunset.cube',
        previewAdjustments: <String, double>{
          'exposure': 4.0,
          'contrast': 8.0,
          'saturation': 12.0,
          'temperature': 9.0,
          'tint': -2.0,
          'highlights': -7.0,
          'shadows': 4.0,
          'clarity': 3.0,
        },
      ),
      ColorFilterPresetSpec(
        id: kColorFilterPresetFilmGreen,
        label: '필름',
        lutAsset: 'assets/luts/moa_film_green.cube',
        previewAdjustments: <String, double>{
          'exposure': 1.0,
          'contrast': -4.0,
          'saturation': 6.0,
          'temperature': 1.0,
          'tint': -3.0,
          'highlights': -8.0,
          'shadows': 12.0,
          'clarity': -4.0,
        },
      ),
      ColorFilterPresetSpec(
        id: kColorFilterPresetKoreanTravelPop,
        label: '여행',
        lutAsset: 'assets/luts/moa_korean_travel_pop.cube',
        previewAdjustments: <String, double>{
          'exposure': 5.0,
          'contrast': 10.0,
          'saturation': 16.0,
          'temperature': 2.0,
          'tint': -2.0,
          'highlights': -5.0,
          'shadows': 8.0,
          'clarity': 5.0,
        },
      ),
      ColorFilterPresetSpec(
        id: kColorFilterPresetCityNightWarm,
        label: '도시밤',
        lutAsset: 'assets/luts/moa_city_night_warm.cube',
        previewAdjustments: <String, double>{
          'exposure': 2.0,
          'contrast': 16.0,
          'saturation': 12.0,
          'temperature': 8.0,
          'highlights': -4.0,
          'shadows': -6.0,
          'clarity': 8.0,
        },
      ),
    ];

Map<String, ColorFilterPresetSpec> get colorFilterPresetSpecById =>
    <String, ColorFilterPresetSpec>{
      for (final spec in kColorFilterPresetSpecs) spec.id: spec,
    };

String normalizeColorFilterPresetId(Object? raw) {
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty) return kColorFilterPresetNone;
  return colorFilterPresetSpecById.containsKey(value)
      ? value
      : kColorFilterPresetNone;
}

double normalizeColorFilterIntensity(Object? raw) {
  final value = raw is num
      ? raw.toDouble()
      : raw is String
      ? double.tryParse(raw)
      : null;
  return (value ?? kColorFilterIntensityDefault).clamp(0.0, 1.0).toDouble();
}

ColorFilterPresetSpec colorFilterPresetById(Object? raw) {
  return colorFilterPresetSpecById[normalizeColorFilterPresetId(raw)] ??
      kColorFilterPresetSpecs.first;
}

Map<String, double> colorFilterPreviewAdjustments({
  required Object? presetId,
  required Object? intensity,
}) {
  final spec = colorFilterPresetById(presetId);
  final amount = normalizeColorFilterIntensity(intensity);
  if (spec.id == kColorFilterPresetNone || amount == 0.0) {
    return const <String, double>{};
  }
  return <String, double>{
    for (final entry in spec.previewAdjustments.entries)
      entry.key: entry.value * amount,
  };
}

Map<String, Object> colorFilterForExportVideoEffects({
  required Object? presetId,
  required Object? intensity,
}) {
  final spec = colorFilterPresetById(presetId);
  final amount = normalizeColorFilterIntensity(intensity);
  final lutAsset = spec.lutAsset;
  if (spec.id == kColorFilterPresetNone || amount == 0.0 || lutAsset == null) {
    return const <String, Object>{};
  }
  return <String, Object>{
    'moaColorLutV1': 1.0,
    'colorFilterPresetId': spec.id,
    'colorFilterIntensity': amount,
    'colorFilterLutAsset': lutAsset,
  };
}
