import 'package:in_app_purchase/in_app_purchase.dart';

const String kStandardAnnualProductId = '3s_standard_annual';
const String kStandardAnnualLaunchOfferTag = 'launch';

enum StandardAnnualOfferPurchaseMode { regularAnnual, launchOffer, unavailable }

class StandardAnnualStorePricingPhase {
  final int? billingCycleCount;
  final String? billingPeriod;
  final String? formattedPrice;
  final int? priceAmountMicros;
  final String? priceCurrencyCode;
  final String? recurrenceMode;

  const StandardAnnualStorePricingPhase({
    this.billingCycleCount,
    this.billingPeriod,
    this.formattedPrice,
    this.priceAmountMicros,
    this.priceCurrencyCode,
    this.recurrenceMode,
  });
}

class StandardAnnualStoreOffer {
  final String productId;
  final String? basePlanId;
  final String? offerId;
  final List<String> offerTags;
  final String? offerToken;
  final List<StandardAnnualStorePricingPhase> pricingPhases;

  StandardAnnualStoreOffer({
    required this.productId,
    this.basePlanId,
    this.offerId,
    Iterable<String> offerTags = const [],
    this.offerToken,
    Iterable<StandardAnnualStorePricingPhase> pricingPhases = const [],
  }) : offerTags = List.unmodifiable(
         offerTags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty),
       ),
       pricingPhases = List.unmodifiable(pricingPhases);
}

class StandardAnnualStoreProduct {
  final String productId;
  final String? priceText;
  final List<StandardAnnualStoreOffer> offers;

  StandardAnnualStoreProduct({
    required this.productId,
    this.priceText,
    Iterable<StandardAnnualStoreOffer> offers = const [],
  }) : offers = List.unmodifiable(offers);
}

class StandardAnnualOfferViewModel {
  final String productId;
  final int annualProductCount;
  final int androidOfferDetailsCount;
  final String? basePlanPriceText;
  final String? launchOfferPriceText;
  final String? launchOfferToken;
  final String? regularAnnualOfferToken;
  final bool launchTagOfferFound;
  final bool hasLaunchOffer;
  final bool canPurchase;
  final StandardAnnualOfferPurchaseMode purchaseMode;
  final String? diagnosticReason;

  const StandardAnnualOfferViewModel({
    required this.productId,
    required this.annualProductCount,
    required this.androidOfferDetailsCount,
    required this.basePlanPriceText,
    required this.launchOfferPriceText,
    required this.launchOfferToken,
    required this.regularAnnualOfferToken,
    required this.launchTagOfferFound,
    required this.hasLaunchOffer,
    required this.canPurchase,
    required this.purchaseMode,
    required this.diagnosticReason,
  });

  factory StandardAnnualOfferViewModel.unavailable({
    required String productId,
    required String diagnosticReason,
    int annualProductCount = 0,
    int androidOfferDetailsCount = 0,
    String? basePlanPriceText,
    String? launchOfferPriceText,
    String? regularAnnualOfferToken,
    bool launchTagOfferFound = false,
  }) {
    return StandardAnnualOfferViewModel(
      productId: productId,
      annualProductCount: annualProductCount,
      androidOfferDetailsCount: androidOfferDetailsCount,
      basePlanPriceText: basePlanPriceText,
      launchOfferPriceText: launchOfferPriceText,
      launchOfferToken: null,
      regularAnnualOfferToken: regularAnnualOfferToken,
      launchTagOfferFound: launchTagOfferFound,
      hasLaunchOffer: false,
      canPurchase: false,
      purchaseMode: StandardAnnualOfferPurchaseMode.unavailable,
      diagnosticReason: diagnosticReason,
    );
  }

  bool get annualProductFound => annualProductCount > 0;
  bool get launchOfferTokenExists => launchOfferToken != null;
  bool get regularAnnualOfferTokenExists => regularAnnualOfferToken != null;
}

class StandardAnnualOfferService {
  final String productId;
  final String launchOfferTag;

  const StandardAnnualOfferService({
    this.productId = kStandardAnnualProductId,
    this.launchOfferTag = kStandardAnnualLaunchOfferTag,
  });

  StandardAnnualOfferViewModel buildFromProductDetails(
    Iterable<ProductDetails> productDetails,
  ) {
    return buildFromStoreProducts(normalizeProductDetails(productDetails));
  }

  StandardAnnualOfferViewModel buildFromStoreProducts(
    Iterable<StandardAnnualStoreProduct> products,
  ) {
    final matchingProducts = products
        .where((product) => product.productId == productId)
        .toList(growable: false);
    if (matchingProducts.isEmpty) {
      return StandardAnnualOfferViewModel.unavailable(
        productId: productId,
        diagnosticReason: 'annual_product_missing',
      );
    }

    final offers = matchingProducts
        .expand((product) => product.offers)
        .where((offer) => offer.productId == productId)
        .toList(growable: false);
    final launchOffer = _selectLaunchOffer(offers);
    final regularOffer = _selectRegularAnnualOffer(offers);
    final regularPriceText = _firstPriceText(regularOffer?.pricingPhases);
    final hasStoreOfferDetails = offers.isNotEmpty;
    final annualProductCount = matchingProducts.length;
    final androidOfferDetailsCount = offers.length;
    final launchTagOfferFound = launchOffer != null;

    if (launchOffer != null) {
      final launchOfferToken = _cleanText(launchOffer.offerToken);
      final launchOfferPriceText = _firstPriceText(launchOffer.pricingPhases);
      final basePlanPriceText =
          regularPriceText ??
          _renewalPriceTextFromLaunchOffer(
            launchOffer,
            launchOfferPriceText: launchOfferPriceText,
          );

      if (launchOfferToken == null) {
        return StandardAnnualOfferViewModel.unavailable(
          productId: productId,
          diagnosticReason: 'launch_offer_missing_token',
          annualProductCount: annualProductCount,
          androidOfferDetailsCount: androidOfferDetailsCount,
          basePlanPriceText: basePlanPriceText,
          launchOfferPriceText: launchOfferPriceText,
          regularAnnualOfferToken: _cleanText(regularOffer?.offerToken),
          launchTagOfferFound: launchTagOfferFound,
        );
      }
      if (launchOfferPriceText == null) {
        return StandardAnnualOfferViewModel.unavailable(
          productId: productId,
          diagnosticReason: 'launch_offer_price_missing',
          annualProductCount: annualProductCount,
          androidOfferDetailsCount: androidOfferDetailsCount,
          basePlanPriceText: basePlanPriceText,
          regularAnnualOfferToken: _cleanText(regularOffer?.offerToken),
          launchTagOfferFound: launchTagOfferFound,
        );
      }
      if (basePlanPriceText == null) {
        return StandardAnnualOfferViewModel.unavailable(
          productId: productId,
          diagnosticReason: 'base_plan_price_missing',
          annualProductCount: annualProductCount,
          androidOfferDetailsCount: androidOfferDetailsCount,
          launchOfferPriceText: launchOfferPriceText,
          regularAnnualOfferToken: _cleanText(regularOffer?.offerToken),
          launchTagOfferFound: launchTagOfferFound,
        );
      }

      return StandardAnnualOfferViewModel(
        productId: productId,
        annualProductCount: annualProductCount,
        androidOfferDetailsCount: androidOfferDetailsCount,
        basePlanPriceText: basePlanPriceText,
        launchOfferPriceText: launchOfferPriceText,
        launchOfferToken: launchOfferToken,
        regularAnnualOfferToken: _cleanText(regularOffer?.offerToken),
        launchTagOfferFound: launchTagOfferFound,
        hasLaunchOffer: true,
        canPurchase: true,
        purchaseMode: StandardAnnualOfferPurchaseMode.launchOffer,
        diagnosticReason: 'launch_offer_available',
      );
    }

    final fallbackPriceText = hasStoreOfferDetails
        ? null
        : _firstProductPriceText(matchingProducts);
    final basePlanPriceText = regularPriceText ?? fallbackPriceText;
    if (basePlanPriceText == null) {
      return StandardAnnualOfferViewModel.unavailable(
        productId: productId,
        diagnosticReason: 'base_plan_price_missing',
        annualProductCount: annualProductCount,
        androidOfferDetailsCount: androidOfferDetailsCount,
        regularAnnualOfferToken: _cleanText(regularOffer?.offerToken),
        launchTagOfferFound: launchTagOfferFound,
      );
    }

    if (regularOffer != null && _cleanText(regularOffer.offerToken) == null) {
      return StandardAnnualOfferViewModel.unavailable(
        productId: productId,
        diagnosticReason: 'regular_offer_missing_token',
        annualProductCount: annualProductCount,
        androidOfferDetailsCount: androidOfferDetailsCount,
        basePlanPriceText: basePlanPriceText,
        launchTagOfferFound: launchTagOfferFound,
      );
    }

    return StandardAnnualOfferViewModel(
      productId: productId,
      annualProductCount: annualProductCount,
      androidOfferDetailsCount: androidOfferDetailsCount,
      basePlanPriceText: basePlanPriceText,
      launchOfferPriceText: null,
      launchOfferToken: null,
      regularAnnualOfferToken: _cleanText(regularOffer?.offerToken),
      launchTagOfferFound: launchTagOfferFound,
      hasLaunchOffer: false,
      canPurchase: true,
      purchaseMode: StandardAnnualOfferPurchaseMode.regularAnnual,
      diagnosticReason: 'regular_annual_available',
    );
  }

  List<StandardAnnualStoreProduct> normalizeProductDetails(
    Iterable<ProductDetails> productDetails,
  ) {
    return productDetails
        .map(
          (product) => StandardAnnualStoreProduct(
            productId: product.id,
            priceText: _cleanText(product.price),
            offers: _extractAndroidSubscriptionOffers(product),
          ),
        )
        .toList(growable: false);
  }

  StandardAnnualStoreOffer? _selectLaunchOffer(
    Iterable<StandardAnnualStoreOffer> offers,
  ) {
    for (final offer in offers) {
      if (_isLaunchOffer(offer)) {
        return offer;
      }
    }
    return null;
  }

  StandardAnnualStoreOffer? _selectRegularAnnualOffer(
    Iterable<StandardAnnualStoreOffer> offers,
  ) {
    StandardAnnualStoreOffer? selected;
    for (final offer in offers) {
      if (_isLaunchOffer(offer)) continue;
      if (offer.offerId != null) continue;
      if (selected == null) {
        selected = offer;
        continue;
      }
      if (selected.offerTags.isNotEmpty && offer.offerTags.isEmpty) {
        selected = offer;
      }
    }
    return selected;
  }

  bool _isLaunchOffer(StandardAnnualStoreOffer offer) {
    return offer.offerTags.contains(launchOfferTag);
  }

  String? _firstProductPriceText(
    Iterable<StandardAnnualStoreProduct> products,
  ) {
    for (final product in products) {
      final priceText = _cleanText(product.priceText);
      if (priceText != null && product.offers.isEmpty) {
        return priceText;
      }
    }
    for (final product in products) {
      final priceText = _cleanText(product.priceText);
      if (priceText != null) return priceText;
    }
    return null;
  }

  String? _firstPriceText(
    Iterable<StandardAnnualStorePricingPhase>? pricingPhases,
  ) {
    if (pricingPhases == null) return null;
    for (final phase in pricingPhases) {
      final priceText = _cleanText(phase.formattedPrice);
      if (priceText != null) return priceText;
    }
    return null;
  }

  String? _renewalPriceTextFromLaunchOffer(
    StandardAnnualStoreOffer launchOffer, {
    required String? launchOfferPriceText,
  }) {
    final phases = launchOffer.pricingPhases;
    for (final phase in phases.reversed) {
      final priceText = _cleanText(phase.formattedPrice);
      if (priceText != null && priceText != launchOfferPriceText) {
        return priceText;
      }
    }
    return null;
  }

  List<StandardAnnualStoreOffer> _extractAndroidSubscriptionOffers(
    ProductDetails product,
  ) {
    final dynamic androidProduct = product;
    final offerDetails = _readSubscriptionOfferDetails(androidProduct);
    if (offerDetails == null || offerDetails.isEmpty) return const [];

    final subscriptionIndex = _readSubscriptionIndex(androidProduct);
    if (subscriptionIndex != null) {
      if (subscriptionIndex < 0 || subscriptionIndex >= offerDetails.length) {
        return const [];
      }
      final selectedOffer = _readAndroidOffer(
        productId: product.id,
        offer: offerDetails[subscriptionIndex],
      );
      return selectedOffer == null
          ? const []
          : <StandardAnnualStoreOffer>[selectedOffer];
    }

    final offers = <StandardAnnualStoreOffer>[];
    for (final offerDetail in offerDetails) {
      final offer = _readAndroidOffer(
        productId: product.id,
        offer: offerDetail,
      );
      if (offer != null) {
        offers.add(offer);
      }
    }
    return offers;
  }

  List<dynamic>? _readSubscriptionOfferDetails(dynamic androidProduct) {
    try {
      final dynamic wrapper = androidProduct.productDetails;
      final dynamic details = wrapper.subscriptionOfferDetails;
      if (details is Iterable) {
        return details.toList(growable: false);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  int? _readSubscriptionIndex(dynamic androidProduct) {
    try {
      final dynamic value = androidProduct.subscriptionIndex;
      if (value is int) return value;
    } catch (_) {
      return null;
    }
    return null;
  }

  StandardAnnualStoreOffer? _readAndroidOffer({
    required String productId,
    required dynamic offer,
  }) {
    final pricingPhases = _readPricingPhases(offer);
    return StandardAnnualStoreOffer(
      productId: productId,
      basePlanId: _readString(() => offer.basePlanId),
      offerId: _readString(() => offer.offerId),
      offerTags: _readStringList(() => offer.offerTags),
      offerToken: _readString(() => offer.offerIdToken),
      pricingPhases: pricingPhases,
    );
  }

  List<StandardAnnualStorePricingPhase> _readPricingPhases(dynamic offer) {
    try {
      final dynamic phases = offer.pricingPhases;
      if (phases is! Iterable) return const [];
      return phases
          .map(_readPricingPhase)
          .whereType<StandardAnnualStorePricingPhase>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  StandardAnnualStorePricingPhase? _readPricingPhase(dynamic phase) {
    return StandardAnnualStorePricingPhase(
      billingCycleCount: _readInt(() => phase.billingCycleCount),
      billingPeriod: _readString(() => phase.billingPeriod),
      formattedPrice: _readString(() => phase.formattedPrice),
      priceAmountMicros: _readInt(() => phase.priceAmountMicros),
      priceCurrencyCode: _readString(() => phase.priceCurrencyCode),
      recurrenceMode: _readRecurrenceModeName(phase),
    );
  }

  String? _readRecurrenceModeName(dynamic phase) {
    try {
      final dynamic recurrenceMode = phase.recurrenceMode;
      if (recurrenceMode == null) return null;
      try {
        final dynamic name = recurrenceMode.name;
        if (name is String && name.isNotEmpty) return name;
      } catch (_) {
        return recurrenceMode.toString();
      }
      return recurrenceMode.toString();
    } catch (_) {
      return null;
    }
  }

  String? _readString(Object? Function() read) {
    try {
      final value = read();
      if (value is String) return _cleanText(value);
    } catch (_) {
      return null;
    }
    return null;
  }

  List<String> _readStringList(Object? Function() read) {
    try {
      final value = read();
      if (value is Iterable) {
        return value
            .whereType<String>()
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {
      return const [];
    }
    return const [];
  }

  int? _readInt(Object? Function() read) {
    try {
      final value = read();
      if (value is int) return value;
      if (value is num) return value.toInt();
    } catch (_) {
      return null;
    }
    return null;
  }

  String? _cleanText(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}
