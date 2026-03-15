import '../managers/user_status_manager.dart';

const String kQuality720p = '720p';
const String kQuality1080p = '1080p';
const String kQuality4k = '4k';

const String kUserTierFree = 'free';
const String kUserTierStandard = 'standard';
const String kUserTierPremium = 'premium';

String normalizeExportQuality(String? raw) {
  final normalized = (raw ?? '').trim().toLowerCase();
  if (normalized == '4k') return kQuality4k;
  if (normalized == '1080p') return kQuality1080p;
  if (normalized == '720p') return kQuality720p;
  return kQuality1080p;
}

String exportQualityLabel(String quality) {
  final normalized = normalizeExportQuality(quality);
  if (normalized == kQuality4k) return '4K';
  if (normalized == kQuality1080p) return '1080p';
  return '720p';
}

String normalizeUserTierKey(String? raw) {
  final normalized = (raw ?? '').trim().toLowerCase();
  if (normalized == kUserTierPremium) return kUserTierPremium;
  if (normalized == kUserTierStandard) return kUserTierStandard;
  return kUserTierFree;
}

String userTierKeyFromManager(UserStatusManager manager) {
  if (manager.isPremium()) return kUserTierPremium;
  if (manager.isStandardOrAbove()) return kUserTierStandard;
  return kUserTierFree;
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

String clampExportQualityForTier({
  required String requestedQuality,
  required UserTier tier,
}) {
  final q = normalizeExportQuality(requestedQuality);
  switch (tier) {
    case UserTier.free:
      return kQuality720p;
    case UserTier.standard:
      if (q == kQuality4k) return kQuality1080p;
      if (q == kQuality720p) return kQuality720p;
      return kQuality1080p;
    case UserTier.premium:
      return q;
  }
}

