import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:three_s/services/standard_annual_offer_service.dart';

void main() {
  group('StandardAnnualOfferService', () {
    const service = StandardAnnualOfferService();

    test(
      'returns launch offer model when launch tag, token, and prices exist',
      () {
        final model = service.buildFromStoreProducts([
          StandardAnnualStoreProduct(
            productId: kStandardAnnualProductId,
            offers: [
              _offer(offerToken: 'regular-token', price: 'KRW 69000'),
              _offer(
                offerId: 'standard-annual-launch-offer',
                offerTags: ['launch'],
                offerToken: 'launch-token',
                phases: [_phase('KRW 59000'), _phase('KRW 69000')],
              ),
            ],
          ),
        ]);

        expect(model.purchaseMode, StandardAnnualOfferPurchaseMode.launchOffer);
        expect(model.canPurchase, isTrue);
        expect(model.hasLaunchOffer, isTrue);
        expect(model.launchOfferPriceText, 'KRW 59000');
        expect(model.basePlanPriceText, 'KRW 69000');
        expect(model.launchOfferToken, 'launch-token');
        expect(model.regularAnnualOfferToken, 'regular-token');
        expect(model.annualProductFound, isTrue);
        expect(model.annualProductCount, 1);
        expect(model.androidOfferDetailsCount, 2);
        expect(model.launchTagOfferFound, isTrue);
        expect(model.launchOfferTokenExists, isTrue);
        expect(model.regularAnnualOfferTokenExists, isTrue);
      },
    );

    test('returns regular annual model when launch offer is absent', () {
      final model = service.buildFromStoreProducts([
        StandardAnnualStoreProduct(
          productId: kStandardAnnualProductId,
          offers: [_offer(offerToken: 'regular-token', price: 'KRW 69000')],
        ),
      ]);

      expect(model.purchaseMode, StandardAnnualOfferPurchaseMode.regularAnnual);
      expect(model.canPurchase, isTrue);
      expect(model.hasLaunchOffer, isFalse);
      expect(model.launchOfferPriceText, isNull);
      expect(model.launchOfferToken, isNull);
      expect(model.basePlanPriceText, 'KRW 69000');
      expect(model.regularAnnualOfferToken, 'regular-token');
      expect(model.annualProductFound, isTrue);
      expect(model.annualProductCount, 1);
      expect(model.androidOfferDetailsCount, 1);
      expect(model.launchTagOfferFound, isFalse);
      expect(model.launchOfferTokenExists, isFalse);
      expect(model.regularAnnualOfferTokenExists, isTrue);
    });

    test('does not start launch path when launch offer token is missing', () {
      final model = service.buildFromStoreProducts([
        StandardAnnualStoreProduct(
          productId: kStandardAnnualProductId,
          offers: [
            _offer(offerToken: 'regular-token', price: 'KRW 69000'),
            _offer(
              offerId: 'standard-annual-launch-offer',
              offerTags: ['launch'],
              offerToken: ' ',
              price: 'KRW 59000',
            ),
          ],
        ),
      ]);

      expect(model.purchaseMode, StandardAnnualOfferPurchaseMode.unavailable);
      expect(model.canPurchase, isFalse);
      expect(model.hasLaunchOffer, isFalse);
      expect(model.launchOfferToken, isNull);
      expect(model.launchOfferPriceText, 'KRW 59000');
      expect(model.basePlanPriceText, 'KRW 69000');
      expect(model.diagnosticReason, 'launch_offer_missing_token');
      expect(model.annualProductFound, isTrue);
      expect(model.androidOfferDetailsCount, 2);
      expect(model.launchTagOfferFound, isTrue);
      expect(model.launchOfferTokenExists, isFalse);
    });

    test(
      'uses launch renewal pricing phase when base plan is not separate',
      () {
        final model = service.buildFromStoreProducts([
          StandardAnnualStoreProduct(
            productId: kStandardAnnualProductId,
            offers: [
              _offer(
                offerId: 'standard-annual-launch-offer',
                offerTags: ['launch'],
                offerToken: 'launch-token',
                phases: [_phase('KRW 59000'), _phase('KRW 69000')],
              ),
            ],
          ),
        ]);

        expect(model.purchaseMode, StandardAnnualOfferPurchaseMode.launchOffer);
        expect(model.canPurchase, isTrue);
        expect(model.launchOfferPriceText, 'KRW 59000');
        expect(model.basePlanPriceText, 'KRW 69000');
      },
    );

    test(
      'ignores unknown discounted offer tags instead of treating as launch',
      () {
        final model = service.buildFromStoreProducts([
          StandardAnnualStoreProduct(
            productId: kStandardAnnualProductId,
            offers: [
              _offer(
                offerId: 'retention-offer',
                offerTags: ['retention'],
                offerToken: 'retention-token',
                price: 'KRW 49000',
              ),
            ],
          ),
        ]);

        expect(model.purchaseMode, StandardAnnualOfferPurchaseMode.unavailable);
        expect(model.canPurchase, isFalse);
        expect(model.hasLaunchOffer, isFalse);
        expect(model.launchOfferToken, isNull);
        expect(model.diagnosticReason, 'base_plan_price_missing');
      },
    );

    test('returns unavailable when annual product is missing', () {
      final model = service.buildFromStoreProducts([
        StandardAnnualStoreProduct(
          productId: '3s_standard_monthly',
          priceText: 'KRW 6900',
        ),
      ]);

      expect(model.purchaseMode, StandardAnnualOfferPurchaseMode.unavailable);
      expect(model.canPurchase, isFalse);
      expect(model.diagnosticReason, 'annual_product_missing');
      expect(model.annualProductFound, isFalse);
      expect(model.androidOfferDetailsCount, 0);
      expect(model.launchTagOfferFound, isFalse);
    });

    test('non-Android product details can still show regular annual', () {
      final productDetails = ProductDetails(
        id: kStandardAnnualProductId,
        title: 'Standard Annual',
        description: 'Standard annual subscription',
        price: 'KRW 69000',
        rawPrice: 69000,
        currencyCode: 'KRW',
      );

      final model = service.buildFromProductDetails([productDetails]);

      expect(model.purchaseMode, StandardAnnualOfferPurchaseMode.regularAnnual);
      expect(model.canPurchase, isTrue);
      expect(model.hasLaunchOffer, isFalse);
      expect(model.basePlanPriceText, 'KRW 69000');
      expect(model.launchOfferToken, isNull);
    });
  });
}

StandardAnnualStoreOffer _offer({
  String? offerId,
  List<String> offerTags = const [],
  String? offerToken,
  String? price,
  List<StandardAnnualStorePricingPhase>? phases,
}) {
  return StandardAnnualStoreOffer(
    productId: kStandardAnnualProductId,
    basePlanId: 'standard-annual',
    offerId: offerId,
    offerTags: offerTags,
    offerToken: offerToken,
    pricingPhases: phases ?? [if (price != null) _phase(price)],
  );
}

StandardAnnualStorePricingPhase _phase(String price) {
  return StandardAnnualStorePricingPhase(
    billingCycleCount: 1,
    billingPeriod: 'P1Y',
    formattedPrice: price,
    priceAmountMicros: 69000000000,
    priceCurrencyCode: 'KRW',
    recurrenceMode: 'infiniteRecurring',
  );
}
