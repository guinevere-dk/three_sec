import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/utils/cloud_cost_policy.dart';

void main() {
  group('Cloud download policy', () {
    test('cache hit does not consume download bytes', () {
      expect(shouldRecordCloudDownloadBytes(cacheHit: true), isFalse);
      expect(shouldRecordCloudDownloadBytes(cacheHit: false), isTrue);
    });

    test('download limit state keeps hard block behind explicit flag', () {
      expect(
        cloudDownloadLimitState(
          monthlyDownloadBytes: kMonthlyDownloadSoftLimitBytes,
        ),
        CloudDownloadLimitState.softLimitExceeded,
      );
      expect(
        cloudDownloadLimitState(
          monthlyDownloadBytes: kMonthlyDownloadHardLimitBytes,
        ),
        CloudDownloadLimitState.softLimitExceeded,
      );
      expect(
        cloudDownloadLimitState(
          monthlyDownloadBytes: kMonthlyDownloadHardLimitBytes,
          hardLimitEnabled: true,
        ),
        CloudDownloadLimitState.hardLimitExceeded,
      );
    });

    test(
      'bulk restore estimate ignores invalid sizes and suggests staging',
      () {
        final estimate = estimateBulkRestoreBytes([
          2 * kCloudBytesPerGiB,
          -100,
          9 * kCloudBytesPerGiB,
        ]);

        expect(estimate, 11 * kCloudBytesPerGiB);
        expect(shouldShowBulkRestoreEstimate(selectedCount: 1), isFalse);
        expect(shouldShowBulkRestoreEstimate(selectedCount: 2), isTrue);
        expect(
          shouldSuggestStagedBulkRestore(estimatedBytes: estimate),
          isTrue,
        );
        expect(suggestedBulkRestoreStageCount(estimatedBytes: estimate), 2);
      },
    );
  });
}
