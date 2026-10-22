import '../../core/api/api_client.dart';
import 'plans_models.dart';

class PlansRepository {
  final ApiClient _client;

  PlansRepository(this._client);

  Future<List<PlanCatalogEntry>> getCatalog() => _client.get(
      '/plans',
      (json) => (json as List<dynamic>)
          .map((e) => PlanCatalogEntry.fromJson(e))
          .toList());

  Future<CurrentSubscription> getCurrent() =>
      _client.get('/plans/current', CurrentSubscription.fromJson, cache: true);

  Future<String> getActivePlanCode() async => (await getCurrent()).planCode;

  Future<void> purchase(
          {required String planId, required String billingCycle}) =>
      _client.post(
        '/plans/purchase',
        (_) {},
        body: {'planId': planId, 'billingCycle': billingCycle},
      );

  /// Hands a completed StoreKit/Play Billing purchase to the server for
  /// receipt validation. The server derives which plan to grant from the
  /// verified [productId] against the store, never from anything the client
  /// claims - this call only tells it which transaction to go check.
  ///
  /// Returns the subscription the server granted, and saves it as the
  /// offline copy of `/plans/current` so a later fallback can't show Free.
  /// The server checks with Apple/Google before answering, hence the longer
  /// timeout; it upserts by transaction, so the automatic retry is safe.
  Future<CurrentSubscription> verifyPurchase({
    required String store,
    required String productId,
    required String receiptData,
    String? transactionId,
  }) async {
    final raw = await _client.post(
      '/plans/purchase/verify',
      (json) => json,
      body: {
        'store': store,
        'productId': productId,
        'receiptData': receiptData,
        if (transactionId != null) 'transactionId': transactionId,
      },
      idempotent: true,
      timeout: const Duration(seconds: 45),
    );
    final subscription = CurrentSubscription.fromJson(raw);
    await _client.updateCached('/plans/current', raw);
    return subscription;
  }

  /// Claims a Silen promo code (Google Play only) - throws an ApiException
  /// carrying the reason when the server turns it down.
  Future<PromoCode> redeemPromoCode(String code) => _client.post(
        '/plans/promo-codes/redeem',
        PromoCode.fromJson,
        body: {'code': code},
        idempotent: true,
      );
}
