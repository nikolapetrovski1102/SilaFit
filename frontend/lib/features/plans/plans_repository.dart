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

  Future<void> purchase(
          {required String planId, required String billingCycle}) =>
      _client.post(
        '/plans/purchase',
        (_) => null,
        body: {'planId': planId, 'billingCycle': billingCycle},
      );
}
