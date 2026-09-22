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

  Future<String> getActivePlanCode() => _client.get('/plans/current', (json) {
        final map = json as Map<String, dynamic>;
        if (map['status'] != 'Active') return 'FREE';
        final expiry = DateTime.tryParse(map['expiresAtUtc'] as String? ?? '');
        if (expiry != null && !expiry.toUtc().isAfter(DateTime.now().toUtc())) {
          return 'FREE';
        }
        return (map['planCode'] as String? ?? 'FREE').toUpperCase();
      });

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
  Future<void> verifyPurchase({
    required String store,
    required String productId,
    required String receiptData,
    String? transactionId,
  }) =>
      _client.post(
        '/plans/purchase/verify',
        (_) {},
        body: {
          'store': store,
          'productId': productId,
          'receiptData': receiptData,
          if (transactionId != null) 'transactionId': transactionId,
        },
      );
}
