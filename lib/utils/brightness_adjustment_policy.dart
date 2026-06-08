import 'dart:math' as math;

const String kBrightnessAdjustmentScopeProjectWide = 'project_wide';
const String kBrightnessAdjustmentScopeClipSpecific = 'clip_specific';

String normalizeBrightnessAdjustmentScope(String? raw) {
  if (raw == kBrightnessAdjustmentScopeClipSpecific) {
    return kBrightnessAdjustmentScopeClipSpecific;
  }
  return kBrightnessAdjustmentScopeProjectWide;
}

class BrightnessAdjustmentSpec {
  final String key;
  final String label;
  final double min;
  final double max;
  final double defaultValue;
  final String nativeKey;

  const BrightnessAdjustmentSpec({
    required this.key,
    required this.label,
    this.min = -100.0,
    this.max = 100.0,
    this.defaultValue = 0.0,
    required this.nativeKey,
  });

  double clamp(num? value) {
    return (value?.toDouble() ?? defaultValue).clamp(min, max).toDouble();
  }
}

const List<BrightnessAdjustmentSpec>
kBrightnessAdjustmentSpecs = <BrightnessAdjustmentSpec>[
  BrightnessAdjustmentSpec(
    key: 'brightness',
    label: '밝기',
    nativeKey: 'brightness',
  ),
  BrightnessAdjustmentSpec(key: 'exposure', label: '노출', nativeKey: 'exposure'),
  BrightnessAdjustmentSpec(key: 'contrast', label: '대비', nativeKey: 'contrast'),
  BrightnessAdjustmentSpec(
    key: 'highlights',
    label: '하이라이트',
    nativeKey: 'highlights',
  ),
  BrightnessAdjustmentSpec(key: 'shadows', label: '그림자', nativeKey: 'shadows'),
  BrightnessAdjustmentSpec(
    key: 'saturation',
    label: '채도',
    nativeKey: 'saturation',
  ),
  BrightnessAdjustmentSpec(key: 'tint', label: '틴트', nativeKey: 'tint'),
  BrightnessAdjustmentSpec(
    key: 'temperature',
    label: '색온도',
    nativeKey: 'temperature',
  ),
  BrightnessAdjustmentSpec(
    key: 'sharpness',
    label: '선명도',
    nativeKey: 'sharpness',
  ),
  BrightnessAdjustmentSpec(key: 'clarity', label: '명료도', nativeKey: 'clarity'),
];

Map<String, BrightnessAdjustmentSpec> get brightnessAdjustmentSpecByKey =>
    <String, BrightnessAdjustmentSpec>{
      for (final spec in kBrightnessAdjustmentSpecs) spec.key: spec,
    };

const Set<String> kBrightnessPreviewAdjustmentKeys = <String>{
  'brightness',
  'contrast',
  'saturation',
  'exposure',
  'temperature',
  'tint',
  'highlights',
  'shadows',
  'sharpness',
  'clarity',
};

const Set<String> kBrightnessAdvancedAdjustmentKeys = <String>{
  'highlights',
  'shadows',
  'sharpness',
  'clarity',
};

const List<double> kIdentityBrightnessPreviewMatrix = <double>[
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

bool isBrightnessPreviewAdjustmentKey(String key) {
  return kBrightnessPreviewAdjustmentKeys.contains(key);
}

List<BrightnessAdjustmentSpec> brightnessPreviewAdjustmentSpecs() {
  return <BrightnessAdjustmentSpec>[
    for (final spec in kBrightnessAdjustmentSpecs)
      if (isBrightnessPreviewAdjustmentKey(spec.key)) spec,
  ];
}

Map<String, double> defaultBrightnessAdjustments() {
  return <String, double>{
    for (final spec in kBrightnessAdjustmentSpecs) spec.key: spec.defaultValue,
  };
}

Map<String, double> normalizeBrightnessAdjustments(Object? raw) {
  final normalized = defaultBrightnessAdjustments();
  if (raw is! Map) return normalized;

  final specs = brightnessAdjustmentSpecByKey;
  for (final entry in raw.entries) {
    final key = entry.key?.toString();
    final spec = specs[key];
    if (key == null || spec == null) continue;

    final value = entry.value;
    if (value is num) {
      normalized[key] = spec.clamp(value);
    } else if (value is String) {
      normalized[key] = spec.clamp(num.tryParse(value));
    }
  }
  return normalized;
}

Map<String, double> brightnessAdjustmentsForProjectJson(Object? raw) {
  return normalizeBrightnessAdjustments(raw);
}

bool hasNonDefaultBrightnessAdjustments(Object? raw) {
  final normalized = normalizeBrightnessAdjustments(raw);
  for (final spec in kBrightnessAdjustmentSpecs) {
    if ((normalized[spec.key] ?? spec.defaultValue) != spec.defaultValue) {
      return true;
    }
  }
  return false;
}

Map<String, double> brightnessAdjustmentsForNativePayload(Object? raw) {
  final normalized = normalizeBrightnessAdjustments(raw);
  return <String, double>{
    for (final spec in kBrightnessAdjustmentSpecs)
      spec.nativeKey: normalized[spec.key] ?? spec.defaultValue,
  };
}

Map<String, double> brightnessAdjustmentsForExportVideoEffects(Object? raw) {
  final normalized = normalizeBrightnessAdjustments(raw);
  final effects = <String, double>{};
  for (final key in kBrightnessPreviewAdjustmentKeys) {
    final value = normalized[key] ?? 0.0;
    if (value == 0.0) continue;
    effects[key] = value;
  }
  if (effects.isNotEmpty) {
    effects['moaColorAdjustmentV1'] = 1.0;
  }
  return effects;
}

List<double> brightnessPreviewColorMatrix(Object? raw) {
  final normalized = normalizeBrightnessAdjustments(raw);
  var matrix = List<double>.from(kIdentityBrightnessPreviewMatrix);

  matrix = _multiplyColorMatrices(
    _exposureMatrix(normalized['exposure'] ?? 0.0),
    matrix,
  );
  matrix = _multiplyColorMatrices(
    _contrastMatrix(normalized['contrast'] ?? 0.0),
    matrix,
  );
  matrix = _multiplyColorMatrices(
    _brightnessMatrix(normalized['brightness'] ?? 0.0),
    matrix,
  );
  matrix = _multiplyColorMatrices(
    _saturationMatrix(normalized['saturation'] ?? 0.0),
    matrix,
  );
  matrix = _multiplyColorMatrices(
    _temperatureTintMatrix(
      temperature: normalized['temperature'] ?? 0.0,
      tint: normalized['tint'] ?? 0.0,
    ),
    matrix,
  );
  matrix = _multiplyColorMatrices(
    _highlightPreviewMatrix(normalized['highlights'] ?? 0.0),
    matrix,
  );
  matrix = _multiplyColorMatrices(
    _shadowPreviewMatrix(normalized['shadows'] ?? 0.0),
    matrix,
  );
  matrix = _multiplyColorMatrices(
    _sharpnessPreviewMatrix(normalized['sharpness'] ?? 0.0),
    matrix,
  );
  matrix = _multiplyColorMatrices(
    _clarityPreviewMatrix(normalized['clarity'] ?? 0.0),
    matrix,
  );

  return matrix;
}

List<double> _brightnessMatrix(double value) {
  final offset = value.clamp(-100.0, 100.0) * 1.275;
  return <double>[
    1,
    0,
    0,
    0,
    offset,
    0,
    1,
    0,
    0,
    offset,
    0,
    0,
    1,
    0,
    offset,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _contrastMatrix(double value) {
  final factor = 1.0 + (value.clamp(-100.0, 100.0) / 100.0);
  final offset = 128.0 * (1.0 - factor);
  return <double>[
    factor,
    0,
    0,
    0,
    offset,
    0,
    factor,
    0,
    0,
    offset,
    0,
    0,
    factor,
    0,
    offset,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _exposureMatrix(double value) {
  final stops = value.clamp(-100.0, 100.0) / 100.0;
  final gain = math.pow(2.0, stops).toDouble();
  return <double>[
    gain,
    0,
    0,
    0,
    0,
    0,
    gain,
    0,
    0,
    0,
    0,
    0,
    gain,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _saturationMatrix(double value) {
  final saturation = 1.0 + (value.clamp(-100.0, 100.0) / 100.0);
  final inverse = 1.0 - saturation;
  final red = 0.2126 * inverse;
  final green = 0.7152 * inverse;
  final blue = 0.0722 * inverse;
  return <double>[
    red + saturation,
    green,
    blue,
    0,
    0,
    red,
    green + saturation,
    blue,
    0,
    0,
    red,
    green,
    blue + saturation,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _temperatureTintMatrix({
  required double temperature,
  required double tint,
}) {
  final warmth = temperature.clamp(-100.0, 100.0) / 100.0;
  final greenMagenta = tint.clamp(-100.0, 100.0) / 100.0;
  final redGain = (1.0 + (warmth * 0.18) + (greenMagenta * 0.08)).clamp(
    0.0,
    2.0,
  );
  final greenGain = (1.0 - (greenMagenta * 0.10)).clamp(0.0, 2.0);
  final blueGain = (1.0 - (warmth * 0.18) + (greenMagenta * 0.08)).clamp(
    0.0,
    2.0,
  );
  return <double>[
    redGain,
    0,
    0,
    0,
    0,
    0,
    greenGain,
    0,
    0,
    0,
    0,
    0,
    blueGain,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _highlightPreviewMatrix(double value) {
  final amount = value.clamp(-100.0, 100.0) / 100.0;
  final factor = 1.0 + (amount * 0.18);
  final offset = amount * 12.0;
  return _rgbGainOffsetMatrix(
    redGain: factor,
    greenGain: factor,
    blueGain: factor,
    offset: offset,
  );
}

List<double> _shadowPreviewMatrix(double value) {
  final amount = value.clamp(-100.0, 100.0) / 100.0;
  final factor = 1.0 + (amount * 0.10);
  final offset = amount * 18.0;
  return _rgbGainOffsetMatrix(
    redGain: factor,
    greenGain: factor,
    blueGain: factor,
    offset: offset,
  );
}

List<double> _sharpnessPreviewMatrix(double value) {
  return _contrastMatrix((value.clamp(-100.0, 100.0) * 0.14).toDouble());
}

List<double> _clarityPreviewMatrix(double value) {
  final amount = value.clamp(-100.0, 100.0);
  return _multiplyColorMatrices(
    _saturationMatrix((amount * 0.12).toDouble()),
    _contrastMatrix((amount * 0.22).toDouble()),
  );
}

List<double> _rgbGainOffsetMatrix({
  required double redGain,
  required double greenGain,
  required double blueGain,
  required double offset,
}) {
  return <double>[
    redGain,
    0,
    0,
    0,
    offset,
    0,
    greenGain,
    0,
    0,
    offset,
    0,
    0,
    blueGain,
    0,
    offset,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _multiplyColorMatrices(List<double> a, List<double> b) {
  final result = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var column = 0; column < 5; column++) {
      final index = (row * 5) + column;
      if (column == 4) {
        result[index] =
            a[(row * 5) + 4] +
            (a[(row * 5)] * b[4]) +
            (a[(row * 5) + 1] * b[9]) +
            (a[(row * 5) + 2] * b[14]) +
            (a[(row * 5) + 3] * b[19]);
      } else {
        result[index] =
            (a[(row * 5)] * b[column]) +
            (a[(row * 5) + 1] * b[5 + column]) +
            (a[(row * 5) + 2] * b[10 + column]) +
            (a[(row * 5) + 3] * b[15 + column]);
      }
    }
  }
  return result;
}
