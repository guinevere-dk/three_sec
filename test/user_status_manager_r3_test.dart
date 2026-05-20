import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_s/managers/user_status_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserStatusManager manager;

  Future<void> resetManager() async {
    SharedPreferences.setMockInitialValues({});
    manager = UserStatusManager();
    await manager.resetToFree();
    await manager.initialize();
  }

  setUp(resetManager);

  test('active paid subscription can write and read cloud clips', () async {
    await manager.setTier(
      UserTier.standard,
      productId: '3s_standard_monthly',
      purchaseDate: DateTime(2026, 1, 1),
    );

    final now = DateTime(2026, 1, 15);

    expect(manager.canStartNewCloudWrite(now: now), isTrue);
    expect(manager.canReadExistingCloudClips(now: now), isTrue);
    expect(manager.isInCloudReadGrace(now: now), isFalse);
  });

  test(
    'expired paid subscription can read during grace but cannot write',
    () async {
      await manager.setTier(
        UserTier.standard,
        productId: '3s_standard_monthly',
        purchaseDate: DateTime(2026, 1, 1),
      );

      final inGrace = DateTime(2026, 2, 10);

      expect(manager.canStartNewCloudWrite(now: inGrace), isFalse);
      expect(manager.canReadExistingCloudClips(now: inGrace), isTrue);
      expect(manager.isInCloudReadGrace(now: inGrace), isFalse);
    },
  );

  test(
    'auto downgraded expired subscription preserves local grace history',
    () async {
      await manager.setTier(
        UserTier.standard,
        productId: '3s_standard_monthly',
        purchaseDate: DateTime(2026, 1, 1),
      );

      await manager.downgradeExpiredSubscriptionToFreePreservingHistory(
        reason: 'test',
      );

      final inGrace = DateTime(2026, 2, 10);
      final afterGrace = DateTime(2026, 3, 5);

      expect(manager.currentTier, UserTier.free);
      expect(manager.lastKnownPaidExpiryAt, DateTime(2026, 2, 1));
      expect(manager.cloudReadGraceEndsAt, DateTime(2026, 3, 3));
      expect(manager.canStartNewCloudWrite(now: inGrace), isFalse);
      expect(manager.canReadExistingCloudClips(now: inGrace), isTrue);
      expect(manager.isInCloudReadGrace(now: inGrace), isTrue);
      expect(manager.canReadExistingCloudClips(now: afterGrace), isFalse);
    },
  );

  test('free never-paid user cannot write or read cloud clips', () {
    final now = DateTime(2026, 2, 10);

    expect(manager.currentTier, UserTier.free);
    expect(manager.lastKnownPaidExpiryAt, isNull);
    expect(manager.cloudReadGraceEndsAt, isNull);
    expect(manager.canStartNewCloudWrite(now: now), isFalse);
    expect(manager.canReadExistingCloudClips(now: now), isFalse);
    expect(manager.isInCloudReadGrace(now: now), isFalse);
  });

  test(
    'reset free state removes grace history for refund-like inactive states',
    () async {
      await manager.setTier(
        UserTier.premium,
        productId: '3s_premium_monthly',
        purchaseDate: DateTime(2026, 1, 1),
      );

      await manager.resetToFree();

      final inFormerGraceWindow = DateTime(2026, 2, 10);

      expect(manager.currentTier, UserTier.free);
      expect(manager.lastKnownPaidExpiryAt, isNull);
      expect(
        manager.canReadExistingCloudClips(now: inFormerGraceWindow),
        isFalse,
      );
      expect(manager.isInCloudReadGrace(now: inFormerGraceWindow), isFalse);
    },
  );
}
