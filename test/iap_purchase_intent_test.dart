import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/managers/user_status_manager.dart';
import 'package:three_s/services/iap_service.dart';

void main() {
  group('IAPPurchaseIntent', () {
    test('allows regular purchases without an offer token', () {
      final intent = IAPPurchaseIntent(productId: IAPService.standardMonthly);

      expect(intent.canStart, isTrue);
      expect(intent.hasOfferToken, isFalse);
      expect(intent.offerToken, isNull);
      expect(intent.purchaseContext, 'regular');
      expect(intent.guardFailureReason, isNull);
    });

    test('blocks required offer-token purchase when token is absent', () {
      final intent = IAPPurchaseIntent(
        productId: IAPService.standardAnnual,
        offerToken: ' ',
        requireOfferToken: true,
        purchaseContext: 'standard_annual_launch',
      );

      expect(intent.canStart, isFalse);
      expect(intent.hasOfferToken, isFalse);
      expect(intent.offerToken, isNull);
      expect(intent.guardFailureReason, 'offer_token_required');
    });

    test('normalizes token and log-safe purchase context', () {
      final intent = IAPPurchaseIntent(
        productId: IAPService.standardAnnual,
        offerToken: ' launch-token ',
        requireOfferToken: true,
        purchaseContext: 'standard annual:launch',
      );

      expect(intent.canStart, isTrue);
      expect(intent.hasOfferToken, isTrue);
      expect(intent.offerToken, 'launch-token');
      expect(intent.purchaseContext, 'standard_annual_launch');
    });

    test('limits purchase context length for diagnostics', () {
      final intent = IAPPurchaseIntent(
        productId: IAPService.standardAnnual,
        purchaseContext: 'a' * 80,
      );

      expect(intent.purchaseContext.length, 64);
    });
  });

  group('IAPEntitlementPolicy', () {
    test(
      'maps Standard annual launch purchases to the Standard entitlement',
      () {
        expect(
          IAPEntitlementPolicy.tierForProductId(IAPService.standardAnnual),
          UserTier.standard,
        );
        expect(
          IAPEntitlementPolicy.canonicalVerifiedProductId(
            purchaseProductId: IAPService.standardAnnual,
            verifiedProductId: IAPService.standardAnnual,
          ),
          IAPService.standardAnnual,
        );
      },
    );

    test(
      'keeps renewal and restore on the same Standard annual product id',
      () {
        expect(
          IAPEntitlementPolicy.tierForProductId(' 3S_STANDARD_ANNUAL '),
          UserTier.standard,
        );
        expect(
          IAPEntitlementPolicy.canonicalVerifiedProductId(
            purchaseProductId: ' 3S_STANDARD_ANNUAL ',
            verifiedProductId: '3s_standard_annual',
          ),
          IAPService.standardAnnual,
        );
      },
    );

    test(
      'does not grant entitlement when purchase and verification ids differ',
      () {
        expect(
          IAPEntitlementPolicy.canonicalVerifiedProductId(
            purchaseProductId: IAPService.standardAnnual,
            verifiedProductId: IAPService.standardMonthly,
          ),
          isNull,
        );
      },
    );

    test('does not treat unsupported product ids as Premium', () {
      expect(IAPEntitlementPolicy.tierForProductId('unknown_product'), isNull);
      expect(
        IAPEntitlementPolicy.canonicalVerifiedProductId(
          purchaseProductId: 'unknown_product',
          verifiedProductId: 'unknown_product',
        ),
        isNull,
      );
    });
  });
}
