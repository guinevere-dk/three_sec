import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/managers/user_status_manager.dart';
import 'package:three_s/utils/cloud_cost_policy.dart';

void main() {
  group('Cloud cost policy limits', () {
    test('standard quota is 50GB and premium uses standard runtime quota', () {
      expect(kStandardCloudLimitBytes, 50 * kCloudBytesPerGiB);
      expect(
        cloudStorageLimitBytesForTier(UserTier.standard),
        kStandardCloudLimitBytes,
      );
      expect(
        cloudStorageLimitBytesForTier(UserTier.premium),
        kStandardCloudLimitBytes,
      );
      expect(cloudStorageLimitBytesForTier(UserTier.free), 0);
    });

    test('download and cache thresholds are centralized', () {
      expect(kMonthlyDownloadSoftLimitBytes, 50 * kCloudBytesPerGiB);
      expect(kMonthlyDownloadHardLimitBytes, 100 * kCloudBytesPerGiB);
      expect(kBulkRestoreDailyLimitBytes, 10 * kCloudBytesPerGiB);
      expect(kCloudVideoCacheMaxBytes, 2 * kCloudBytesPerGiB);
      expect(kStandardCloudVideoObjectLimitBytes, 50 * kCloudBytesPerMiB);
      expect(kLegacyGlobalVideoObjectSafetyCapBytes, 500 * kCloudBytesPerMiB);
    });
  });

  group('cloudUsageRatio', () {
    test('returns zero when the limit is unavailable', () {
      expect(cloudUsageRatio(10 * kCloudBytesPerGiB, 0), 0);
    });

    test('calculates usage against the provided limit', () {
      expect(
        cloudUsageRatio(25 * kCloudBytesPerGiB, kStandardCloudLimitBytes),
        0.5,
      );
    });

    test('normalizes negative usage to zero', () {
      expect(cloudUsageRatio(-1, kStandardCloudLimitBytes), 0);
    });
  });

  group('canUploadWithinLimit', () {
    test('allows upload at the exact quota boundary', () {
      expect(
        canUploadWithinLimit(
          usedBytes: 49 * kCloudBytesPerGiB,
          reservedBytes: 512 * kCloudBytesPerMiB,
          incomingBytes: 512 * kCloudBytesPerMiB,
          limitBytes: kStandardCloudLimitBytes,
        ),
        isTrue,
      );
    });

    test('rejects upload when used and reserved bytes exceed quota', () {
      expect(
        canUploadWithinLimit(
          usedBytes: 49 * kCloudBytesPerGiB,
          reservedBytes: 800 * kCloudBytesPerMiB,
          incomingBytes: 512 * kCloudBytesPerMiB,
          limitBytes: kStandardCloudLimitBytes,
        ),
        isFalse,
      );
    });

    test('rejects uploads without an entitlement limit', () {
      expect(
        canUploadWithinLimit(
          usedBytes: 0,
          reservedBytes: 0,
          incomingBytes: 1,
          limitBytes: 0,
        ),
        isFalse,
      );
    });

    test('checks Standard video object limit separately from quota', () {
      expect(
        isWithinStandardCloudVideoObjectLimit(
          kStandardCloudVideoObjectLimitBytes,
        ),
        isTrue,
      );
      expect(
        isWithinStandardCloudVideoObjectLimit(
          kStandardCloudVideoObjectLimitBytes + 1,
        ),
        isFalse,
      );
      expect(isWithinStandardCloudVideoObjectLimit(0), isFalse);
    });
  });

  group('formatCloudBytes', () {
    test('formats common Cloud byte values', () {
      expect(formatCloudBytes(0), '0MB');
      expect(formatCloudBytes(512 * kCloudBytesPerMiB), '512MB');
      expect(formatCloudBytes(kCloudBytesPerGiB), '1GB');
      expect(
        formatCloudBytes(kCloudBytesPerGiB + 512 * kCloudBytesPerMiB),
        '1.5GB',
      );
      expect(formatCloudBytes(kStandardCloudLimitBytes), '50GB');
    });
  });
}
