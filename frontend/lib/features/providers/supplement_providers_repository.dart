import '../../core/api/api_client.dart';
import 'supplement_provider_models.dart';

class SupplementProvidersRepository {
  final ApiClient _client;

  SupplementProvidersRepository(this._client);

  List<SupplementProvider>? _memo;

  /// Active partner shops, cached in memory for the session and on disk so the
  /// meal tracker's protein hint never waits on the network.
  Future<List<SupplementProvider>> getAll({bool refresh = false}) async {
    if (!refresh && _memo != null) return _memo!;
    final list = await _client.get(
      '/providers',
      SupplementProvider.listFromJson,
      cache: true,
    );
    return _memo = list;
  }

  /// The grocery partner to order ingredients from, or null while none is
  /// switched on in the console - every "Order the ingredients" entry point
  /// stays hidden until then.
  Future<SupplementProvider?> groceryPartner() async {
    try {
      final all = await getAll();
      for (final p in all) {
        if (p.ordersIngredients && (p.shopUrl != null || p.searchUrl != null)) {
          return p;
        }
      }
    } catch (_) {
      // An offer, never an error: no partner means no button.
    }
    return null;
  }

  /// The protein partner to suggest, or null when none has a code or a shop.
  Future<SupplementProvider?> proteinPartner() async {
    try {
      final all = await getAll();
      for (final p in all) {
        if (p.sellsProtein && (p.promoCode != null || p.shopUrl != null)) {
          return p;
        }
      }
    } catch (_) {
      // A hint, never an error: no partner means no chip.
    }
    return null;
  }
}
