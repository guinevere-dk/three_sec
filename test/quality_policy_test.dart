import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/managers/user_status_manager.dart';
import 'package:three_s/utils/quality_policy.dart';

void main() {
  group('clampExportQualityForTier', () {
    test('free exports are always clamped to 720p', () {
      expect(
        clampExportQualityForTier(
          requestedQuality: kQuality1080p,
          tier: UserTier.free,
        ),
        kQuality720p,
      );
    });

    test('standard can export 720p and 1080p, but not 4K', () {
      expect(
        clampExportQualityForTier(
          requestedQuality: kQuality720p,
          tier: UserTier.standard,
        ),
        kQuality720p,
      );
      expect(
        clampExportQualityForTier(
          requestedQuality: kQuality1080p,
          tier: UserTier.standard,
        ),
        kQuality1080p,
      );
      expect(
        clampExportQualityForTier(
          requestedQuality: kQuality4k,
          tier: UserTier.standard,
        ),
        kQuality1080p,
      );
    });

    test(
      'premium runtime permissions are normalized to standard export policy',
      () {
        expect(normalizeRuntimeUserTier(UserTier.premium), UserTier.standard);
        expect(
          normalizeRuntimeUserTierKey(kUserTierPremium),
          kUserTierStandard,
        );
        expect(
          clampExportQualityForTier(
            requestedQuality: kQuality4k,
            tier: UserTier.premium,
          ),
          kQuality1080p,
        );
      },
    );
  });

  group('central export quality policy', () {
    test('free exposes and defaults to 720p only', () {
      expect(availableExportQualities(UserTier.free), <String>[kQuality720p]);
      expect(defaultExportQuality(UserTier.free), kQuality720p);
      expect(maxExportQuality(UserTier.free), kQuality720p);
      expect(clampExportQuality(UserTier.free, kQuality1080p), kQuality720p);
    });

    test('standard exposes 720p and 1080p with 1080p default', () {
      expect(availableExportQualities(UserTier.standard), <String>[
        kQuality720p,
        kQuality1080p,
      ]);
      expect(defaultExportQuality(UserTier.standard), kQuality1080p);
      expect(maxExportQuality(UserTier.standard), kQuality1080p);
      expect(clampExportQuality(UserTier.standard, kQuality720p), kQuality720p);
      expect(clampExportQuality(UserTier.standard, kQuality4k), kQuality1080p);
    });

    test('premium uses the standard runtime policy', () {
      expect(availableExportQualities(UserTier.premium), <String>[
        kQuality720p,
        kQuality1080p,
      ]);
      expect(defaultExportQuality(UserTier.premium), kQuality1080p);
      expect(maxExportQuality(UserTier.premium), kQuality1080p);
      expect(clampExportQuality(UserTier.premium, kQuality4k), kQuality1080p);
    });

    test('legacy project 4K quality restores as 1080p', () {
      expect(restoreProjectExportQuality(kQuality4k), kQuality1080p);
      expect(restoreProjectExportQuality(kQuality720p), kQuality720p);
      expect(restoreProjectExportQuality(null), kQuality1080p);
    });
  });

  group('VideoEditScreen access policy', () {
    test(
      'free cannot access editor while standard and premium-compatible can',
      () {
        expect(canAccessVideoEditScreenForTier(UserTier.free), isFalse);
        expect(canAccessVideoEditScreenForTier(UserTier.standard), isTrue);
        expect(canAccessVideoEditScreenForTier(UserTier.premium), isTrue);
      },
    );
  });
}
