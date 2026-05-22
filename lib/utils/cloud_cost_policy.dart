import '../managers/user_status_manager.dart';

const int kCloudBytesPerKiB = 1024;
const int kCloudBytesPerMiB = kCloudBytesPerKiB * 1024;
const int kCloudBytesPerGiB = kCloudBytesPerMiB * 1024;

const int kStandardCloudLimitBytes = 50 * kCloudBytesPerGiB;
const int kMonthlyDownloadSoftLimitBytes = 50 * kCloudBytesPerGiB;
const int kMonthlyDownloadHardLimitBytes = 100 * kCloudBytesPerGiB;
const int kBulkRestoreDailyLimitBytes = 10 * kCloudBytesPerGiB;
const int kCloudVideoCacheMaxBytes = 2 * kCloudBytesPerGiB;
const int kStandardCloudVideoObjectLimitBytes = 50 * kCloudBytesPerMiB;
const int kLegacyGlobalVideoObjectSafetyCapBytes = 500 * kCloudBytesPerMiB;

enum CloudDownloadLimitState { normal, softLimitExceeded, hardLimitExceeded }

int cloudStorageLimitBytesForTier(UserTier tier) {
  switch (tier) {
    case UserTier.free:
      return 0;
    case UserTier.standard:
    case UserTier.premium:
      return kStandardCloudLimitBytes;
  }
}

double cloudStorageLimitGBForTier(UserTier tier) {
  return cloudStorageLimitBytesForTier(tier) / kCloudBytesPerGiB;
}

double cloudUsageRatio(int usedBytes, int limitBytes) {
  if (limitBytes <= 0) return 0;
  final safeUsed = usedBytes < 0 ? 0 : usedBytes;
  final ratio = safeUsed / limitBytes;
  if (ratio < 0) return 0;
  return ratio;
}

bool canUploadWithinLimit({
  required int usedBytes,
  required int reservedBytes,
  required int incomingBytes,
  required int limitBytes,
}) {
  if (limitBytes <= 0 || incomingBytes < 0) return false;
  final safeUsed = usedBytes < 0 ? 0 : usedBytes;
  final safeReserved = reservedBytes < 0 ? 0 : reservedBytes;
  return safeUsed + safeReserved + incomingBytes <= limitBytes;
}

bool isWithinStandardCloudVideoObjectLimit(int bytes) {
  return bytes > 0 && bytes <= kStandardCloudVideoObjectLimitBytes;
}

bool shouldRecordCloudDownloadBytes({required bool cacheHit}) {
  return !cacheHit;
}

CloudDownloadLimitState cloudDownloadLimitState({
  required int monthlyDownloadBytes,
  bool hardLimitEnabled = false,
}) {
  final safeBytes = monthlyDownloadBytes < 0 ? 0 : monthlyDownloadBytes;
  if (hardLimitEnabled && safeBytes >= kMonthlyDownloadHardLimitBytes) {
    return CloudDownloadLimitState.hardLimitExceeded;
  }
  if (safeBytes >= kMonthlyDownloadSoftLimitBytes) {
    return CloudDownloadLimitState.softLimitExceeded;
  }
  return CloudDownloadLimitState.normal;
}

int estimateBulkRestoreBytes(Iterable<int> fileSizes) {
  return fileSizes.fold<int>(0, (total, size) => total + (size < 0 ? 0 : size));
}

bool shouldShowBulkRestoreEstimate({required int selectedCount}) {
  return selectedCount > 1;
}

bool shouldSuggestStagedBulkRestore({
  required int estimatedBytes,
  int dailyLimitBytes = kBulkRestoreDailyLimitBytes,
}) {
  if (dailyLimitBytes <= 0) return false;
  return estimatedBytes > dailyLimitBytes;
}

int suggestedBulkRestoreStageCount({
  required int estimatedBytes,
  int dailyLimitBytes = kBulkRestoreDailyLimitBytes,
}) {
  if (estimatedBytes <= 0 || dailyLimitBytes <= 0) return 1;
  return (estimatedBytes / dailyLimitBytes).ceil();
}

String formatCloudBytes(int bytes) {
  final safeBytes = bytes < 0 ? 0 : bytes;
  if (safeBytes < kCloudBytesPerGiB) {
    final mb = safeBytes / kCloudBytesPerMiB;
    if (mb > 0 && mb < 10) {
      return '${mb.toStringAsFixed(1)}MB';
    }
    return '${mb.round()}MB';
  }

  final gb = safeBytes / kCloudBytesPerGiB;
  if (gb == gb.roundToDouble()) {
    return '${gb.toStringAsFixed(0)}GB';
  }
  return '${gb.toStringAsFixed(1)}GB';
}
