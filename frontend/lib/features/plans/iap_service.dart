import 'package:in_app_purchase/in_app_purchase.dart';

/// Thin wrapper around the native purchase APIs (StoreKit on iOS, Play
/// Billing on Android) via the official `in_app_purchase` plugin. Owns
/// nothing but the plugin singleton itself - [PlansController] owns the
/// purchase-flow state machine and drives this through it.
class IapService {
  final InAppPurchase _iap = InAppPurchase.instance;

  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  Future<bool> isAvailable() => _iap.isAvailable();

  Future<ProductDetailsResponse> queryProducts(Set<String> productIds) =>
      _iap.queryProductDetails(productIds);

  /// Subscriptions are modeled as non-consumables in this plugin - Apple and
  /// Google each own renewal on their own side, this only starts the initial
  /// purchase sheet. Returns true once the request is handed off to the
  /// platform; the actual result arrives later on [purchaseStream].
  Future<bool> buy(ProductDetails product) =>
      _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));

  Future<void> completePurchase(PurchaseDetails purchase) {
    if (!purchase.pendingCompletePurchase) return Future.value();
    return _iap.completePurchase(purchase);
  }

  Future<void> restorePurchases() => _iap.restorePurchases();
}
