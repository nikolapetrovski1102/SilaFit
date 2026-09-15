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
}
