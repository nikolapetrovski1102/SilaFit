import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:intl/intl.dart';

/// A store's introductory offer on one subscription product, as the store
/// itself quotes it - the paywall only ever advertises a discount that one of
/// these backs (App Review 3.1.2: the price shown must be the price charged).
class StoreIntroOffer {
  /// Localized intro price, e.g. "€1.49" - already formatted by the store.
  final String displayPrice;
  final double rawPrice;
  final bool isFreeTrial;

  /// True when the intro price is billed every period for [periodCount]
  /// periods (StoreKit "pay as you go"), rather than once up front.
  final bool isPerPeriod;
  final String periodUnit; // day | week | month | year
  final int periodValue;
  final int periodCount;

  const StoreIntroOffer({
    required this.displayPrice,
    required this.rawPrice,
    required this.isFreeTrial,
    required this.isPerPeriod,
    required this.periodUnit,
    required this.periodValue,
    required this.periodCount,
  });

  /// "month", "3 months", "week"... - the offer's whole span.
  String get duration {
    final total = periodValue * periodCount;
    return total == 1 ? periodUnit : '$total ${periodUnit}s';
  }

  /// "€1.49/month for the first 3 months" / "Free for the first week".
  String get summary {
    if (isFreeTrial) return 'Free for the first $duration';
    final unit = periodValue == 1 ? periodUnit : '$periodValue ${periodUnit}s';
    return isPerPeriod && periodCount > 1
        ? '$displayPrice/$unit for the first $duration'
        : '$displayPrice for the first $duration';
  }
}

/// Everything the paywall needs to show and sell one store product: the
/// store's own localized regular price, plus its intro offer when the store
/// says this user is eligible for one.
class StoreQuote {
  /// The regular-price product (on Play, the base plan).
  final ProductDetails product;

  /// What to hand the purchase sheet - on Play, the intro offer's own
  /// [GooglePlayProductDetails] (its offer token selects the discount);
  /// otherwise [product], since StoreKit applies an eligible intro offer
  /// automatically.
  final ProductDetails purchaseProduct;
  final StoreIntroOffer? intro;

  const StoreQuote({
    required this.product,
    ProductDetails? purchaseProduct,
    this.intro,
  }) : purchaseProduct = purchaseProduct ?? product;

  String get price => product.price;
  double get rawPrice => product.rawPrice;

  /// Formats an arbitrary amount (e.g. a per-day figure) in this product's
  /// currency, so derived numbers never fall back to a hardcoded "$".
  String format(double amount) =>
      NumberFormat.simpleCurrency(name: product.currencyCode).format(amount);

  /// Whole-percent discount of the intro price off the regular price, for a
  /// badge - null when there is no paid intro offer to compare.
  int? get introDiscountPercent {
    final offer = intro;
    if (offer == null || offer.isFreeTrial || rawPrice <= 0) return null;
    final perPeriod = offer.isPerPeriod || offer.periodCount <= 1
        ? offer.rawPrice
        : offer.rawPrice / offer.periodCount;
    final pct = ((1 - perPeriod / rawPrice) * 100).round();
    return pct > 0 ? pct : null;
  }
}

/// Thin wrapper around the native purchase APIs (StoreKit on iOS, Play
/// Billing on Android) via the official `in_app_purchase` plugin. Owns
/// nothing but the plugin singleton itself - [PlansController] owns the
/// purchase-flow state machine and drives this through it.
class IapService {
  final InAppPurchase _iap = InAppPurchase.instance;

  // See ios/SilaFit/StoreOffersPlugin.swift - in_app_purchase_storekit has no
  // API for a product's intro offer price.
  static const _storeOffersChannel =
      MethodChannel('com.nikolapetrovski.silafit/store_offers');

  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  Future<bool> isAvailable() => _iap.isAvailable();

  /// Store quotes keyed by product id. Ids the store doesn't know are simply
  /// absent from the result.
  Future<Map<String, StoreQuote>> loadQuotes(Set<String> productIds) async {
    final response = await _iap.queryProductDetails(productIds);
    final byId = <String, List<ProductDetails>>{};
    for (final details in response.productDetails) {
      (byId[details.id] ??= []).add(details);
    }
    final quotes = <String, StoreQuote>{};
    for (final MapEntry(key: id, value: details) in byId.entries) {
      quotes[id] = Platform.isAndroid
          ? _playQuote(details)
          : await _appStoreQuote(details.first);
    }
    return quotes;
  }

  /// Play returns one [GooglePlayProductDetails] per base plan / offer, and
  /// only the offers this user is eligible for - so an offer with a leading
  /// discounted pricing phase is an intro offer they can actually get.
  StoreQuote _playQuote(List<ProductDetails> details) {
    GooglePlayProductDetails? basePlan;
    GooglePlayProductDetails? introProduct;
    PricingPhaseWrapper? introPhase;
    for (final product in details.whereType<GooglePlayProductDetails>()) {
      final offers = product.productDetails.subscriptionOfferDetails;
      final index = product.subscriptionIndex;
      if (offers == null || index == null) continue;
      final offer = offers[index];
      if (offer.offerId == null) {
        basePlan ??= product;
      } else if (introProduct == null && offer.pricingPhases.length > 1) {
        introProduct = product;
        introPhase = offer.pricingPhases.first;
      }
    }
    final regular = basePlan ?? details.first;
    if (introProduct == null || introPhase == null) {
      return StoreQuote(product: regular);
    }
    final (unit, value) = _parseIsoPeriod(introPhase.billingPeriod);
    return StoreQuote(
      product: regular,
      purchaseProduct: introProduct,
      intro: StoreIntroOffer(
        displayPrice: introPhase.formattedPrice,
        rawPrice: introPhase.priceAmountMicros / 1000000.0,
        isFreeTrial: introPhase.priceAmountMicros == 0,
        isPerPeriod: introPhase.billingCycleCount > 1,
        periodUnit: unit,
        periodValue: value,
        periodCount:
            introPhase.billingCycleCount < 1 ? 1 : introPhase.billingCycleCount,
      ),
    );
  }

  Future<StoreQuote> _appStoreQuote(ProductDetails product) async {
    try {
      final offer = await _storeOffersChannel.invokeMapMethod<String, dynamic>(
          'introOffer', {'productId': product.id});
      if (offer == null) return StoreQuote(product: product);
      final mode = offer['paymentMode'] as String? ?? '';
      return StoreQuote(
        product: product,
        intro: StoreIntroOffer(
          displayPrice: offer['displayPrice'] as String,
          rawPrice: (offer['price'] as num).toDouble(),
          isFreeTrial: mode == 'freeTrial',
          isPerPeriod: mode == 'payAsYouGo',
          periodUnit: offer['periodUnit'] as String? ?? 'month',
          periodValue: offer['periodValue'] as int? ?? 1,
          periodCount: offer['periodCount'] as int? ?? 1,
        ),
      );
    } on PlatformException {
      return StoreQuote(product: product);
    } on MissingPluginException {
      return StoreQuote(product: product);
    }
  }

  /// "P1M" -> (month, 1), "P2W" -> (week, 2), "P3D" -> (day, 3).
  static (String, int) _parseIsoPeriod(String iso) {
    final match = RegExp(r'^P(\d+)([DWMY])$').firstMatch(iso);
    if (match == null) return ('month', 1);
    final unit = switch (match.group(2)) {
      'D' => 'day',
      'W' => 'week',
      'Y' => 'year',
      _ => 'month',
    };
    return (unit, int.parse(match.group(1)!));
  }

  /// Subscriptions are modeled as non-consumables in this plugin - Apple and
  /// Google each own renewal on their own side, this only starts the initial
  /// purchase sheet. Returns true once the request is handed off to the
  /// platform; the actual result arrives later on [purchaseStream].
  Future<bool> buy(StoreQuote quote) => _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: quote.purchaseProduct));

  Future<void> completePurchase(PurchaseDetails purchase) {
    if (!purchase.pendingCompletePurchase) return Future.value();
    return _iap.completePurchase(purchase);
  }

  /// Re-delivers the user's current purchases onto [purchaseStream].
  /// [syncWithStore] first refreshes StoreKit's entitlement cache from Apple
  /// (see ios/SilaFit/StoreOffersPlugin.swift) - only for the explicit
  /// Restore button, since it can prompt for an Apple ID sign-in. Play has no
  /// equivalent: its query already goes to Google.
  Future<void> restorePurchases({bool syncWithStore = false}) async {
    if (syncWithStore && Platform.isIOS) {
      try {
        await _storeOffersChannel.invokeMethod<void>('syncTransactions');
      } on PlatformException {
        // Restore from the cached entitlements instead.
      } on MissingPluginException {
        // Restore from the cached entitlements instead.
      }
    }
    await _iap.restorePurchases();
  }
}
