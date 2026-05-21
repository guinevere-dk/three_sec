import '../managers/user_status_manager.dart';

const String kQuality720p = '720p';
const String kQuality1080p = '1080p';
const String kQuality4k = '4k';

const int kQualityTargetFps = 30;
const String kQualityVideoCodecH264 = 'h264';
const String kQualityDefaultCaptureQuality = kQuality1080p;
const int kQuality1080pTargetBitrate = 12 * 1000 * 1000;
const int kQuality1080pMinBitrate = 8 * 1000 * 1000;
const int kQuality1080pMaxBitrate = 16 * 1000 * 1000;
const int kQuality720pTargetBitrate = 5 * 1000 * 1000;
const int kQuality4kTargetBitrate = 20 * 1000 * 1000;

const String kUserTierFree = 'free';
const String kUserTierStandard = 'standard';
const String kUserTierPremium = 'premium';

const List<String> kFreeVisibleCaptureQualities = <String>[kQuality1080p];

class VideoQualityProfile {
  final String quality;
  final String label;
  final int? width;
  final int? height;
  final int targetFps;
  final int targetBitrate;
  final int? minBitrate;
  final int? maxBitrate;
  final String videoCodec;

  const VideoQualityProfile({
    required this.quality,
    required this.label,
    required this.width,
    required this.height,
    required this.targetFps,
    required this.targetBitrate,
    required this.videoCodec,
    this.minBitrate,
    this.maxBitrate,
  });

  String get bitrateMbpsLabel => '${(targetBitrate / 1000000).round()}Mbps';

  String get resolutionLabel {
    if (width == null || height == null) return label;
    return '${width}x$height';
  }

  String get summaryLabel => '$label · ${targetFps}fps · $bitrateMbpsLabel';

  Map<String, Object?> toLogMap() {
    return {
      'quality': quality,
      'label': label,
      'width': width,
      'height': height,
      'targetFps': targetFps,
      'targetBitrate': targetBitrate,
      'minBitrate': minBitrate,
      'maxBitrate': maxBitrate,
      'videoCodec': videoCodec,
    };
  }

  Map<String, Object?> toBenchmarkLogMap() {
    return {
      ...toLogMap(),
      'bitrateBenchmarks': {
        if (quality == kQuality1080p) 'min1080p': kQuality1080pMinBitrate,
        if (quality == kQuality1080p) 'target1080p': kQuality1080pTargetBitrate,
        if (quality == kQuality1080p) 'max1080p': kQuality1080pMaxBitrate,
      },
      'bitrateSamplePlan': bitrateSamplePlanForQuality(quality),
    };
  }
}

List<Map<String, Object?>> bitrateSamplePlanForQuality(String? quality) {
  final normalized = normalizeExportQuality(quality);
  if (normalized != kQuality1080p) {
    final profile = videoQualityProfile(normalized);
    return <Map<String, Object?>>[
      {
        'sampleBitrate': profile.targetBitrate,
        'sampleMbps': (profile.targetBitrate / 1000000).round(),
        'sampleLabel': profile.bitrateMbpsLabel,
        'sampleRole': 'target',
        'quality': profile.quality,
      },
    ];
  }

  return <Map<String, Object?>>[
    {
      'sampleBitrate': kQuality1080pMinBitrate,
      'sampleMbps': 8,
      'sampleLabel': '8Mbps',
      'sampleRole': 'min1080p',
      'quality': kQuality1080p,
    },
    {
      'sampleBitrate': kQuality1080pTargetBitrate,
      'sampleMbps': 12,
      'sampleLabel': '12Mbps',
      'sampleRole': 'target1080p',
      'quality': kQuality1080p,
    },
    {
      'sampleBitrate': kQuality1080pMaxBitrate,
      'sampleMbps': 16,
      'sampleLabel': '16Mbps',
      'sampleRole': 'max1080p',
      'quality': kQuality1080p,
    },
  ];
}

const VideoQualityProfile kQualityProfile720p = VideoQualityProfile(
  quality: kQuality720p,
  label: '720p',
  width: 1280,
  height: 720,
  targetFps: kQualityTargetFps,
  targetBitrate: kQuality720pTargetBitrate,
  videoCodec: kQualityVideoCodecH264,
);

const VideoQualityProfile kQualityProfile1080p = VideoQualityProfile(
  quality: kQuality1080p,
  label: '1080p',
  width: 1920,
  height: 1080,
  targetFps: kQualityTargetFps,
  targetBitrate: kQuality1080pTargetBitrate,
  minBitrate: kQuality1080pMinBitrate,
  maxBitrate: kQuality1080pMaxBitrate,
  videoCodec: kQualityVideoCodecH264,
);

const VideoQualityProfile kQualityProfile4k = VideoQualityProfile(
  quality: kQuality4k,
  label: '4K',
  width: 3840,
  height: 2160,
  targetFps: kQualityTargetFps,
  targetBitrate: kQuality4kTargetBitrate,
  videoCodec: kQualityVideoCodecH264,
);

String normalizeExportQuality(String? raw) {
  final normalized = (raw ?? '').trim().toLowerCase();
  if (normalized == '4k') return kQuality4k;
  if (normalized == '1080p') return kQuality1080p;
  if (normalized == '720p') return kQuality720p;
  return kQuality1080p;
}

String clampCaptureQualityForFreePolicy(String? requestedQuality) {
  final q = normalizeExportQuality(requestedQuality);
  if (kFreeVisibleCaptureQualities.contains(q)) return q;
  return kQualityDefaultCaptureQuality;
}

String exportQualityLabel(String quality) {
  final normalized = normalizeExportQuality(quality);
  if (normalized == kQuality4k) return '4K';
  if (normalized == kQuality1080p) return '1080p';
  return '720p';
}

VideoQualityProfile videoQualityProfile(String? quality) {
  switch (normalizeExportQuality(quality)) {
    case kQuality4k:
      return kQualityProfile4k;
    case kQuality720p:
      return kQualityProfile720p;
    case kQuality1080p:
    default:
      return kQualityProfile1080p;
  }
}

String normalizeUserTierKey(String? raw) {
  final normalized = (raw ?? '').trim().toLowerCase();
  if (normalized == kUserTierPremium) return kUserTierPremium;
  if (normalized == kUserTierStandard) return kUserTierStandard;
  return kUserTierFree;
}

UserTier normalizeRuntimeUserTier(UserTier tier) {
  if (tier == UserTier.premium) return UserTier.standard;
  return tier;
}

String normalizeRuntimeUserTierKey(String? raw) {
  final normalized = normalizeUserTierKey(raw);
  if (normalized == kUserTierPremium) return kUserTierStandard;
  return normalized;
}

bool canAccessVideoEditScreenForTier(UserTier tier) {
  return normalizeRuntimeUserTier(tier) == UserTier.standard;
}

String userTierKeyFromManager(UserStatusManager manager) {
  if (manager.isPremium()) return kUserTierPremium;
  if (manager.isStandardOrAbove()) return kUserTierStandard;
  return kUserTierFree;
}

String runtimeUserTierKeyFromManager(UserStatusManager manager) {
  return normalizeRuntimeUserTierKey(userTierKeyFromManager(manager));
}

UserTier userTierFromKey(String key) {
  switch (normalizeUserTierKey(key)) {
    case kUserTierPremium:
      return UserTier.premium;
    case kUserTierStandard:
      return UserTier.standard;
    default:
      return UserTier.free;
  }
}

List<String> availableExportQualities(UserTier tier) {
  switch (normalizeRuntimeUserTier(tier)) {
    case UserTier.free:
      return const <String>[kQuality720p];
    case UserTier.standard:
      return const <String>[kQuality720p, kQuality1080p];
    case UserTier.premium:
      return const <String>[kQuality720p, kQuality1080p];
  }
}

String defaultExportQuality(UserTier tier) {
  switch (normalizeRuntimeUserTier(tier)) {
    case UserTier.free:
      return kQuality720p;
    case UserTier.standard:
      return kQuality1080p;
    case UserTier.premium:
      return kQuality1080p;
  }
}

String maxExportQuality(UserTier tier) {
  switch (normalizeRuntimeUserTier(tier)) {
    case UserTier.free:
      return kQuality720p;
    case UserTier.standard:
      return kQuality1080p;
    case UserTier.premium:
      return kQuality1080p;
  }
}

String clampExportQuality(UserTier tier, String requestedQuality) {
  final q = normalizeExportQuality(requestedQuality);
  switch (normalizeRuntimeUserTier(tier)) {
    case UserTier.free:
      return kQuality720p;
    case UserTier.standard:
      if (q == kQuality4k) return kQuality1080p;
      return q;
    case UserTier.premium:
      if (q == kQuality4k) return kQuality1080p;
      return q;
  }
}

String clampExportQualityForTier({
  required String requestedQuality,
  required UserTier tier,
}) {
  return clampExportQuality(tier, requestedQuality);
}

String restoreProjectExportQuality(String? raw) {
  final normalized = normalizeExportQuality(raw);
  if (normalized == kQuality4k) return kQuality1080p;
  return normalized;
}
