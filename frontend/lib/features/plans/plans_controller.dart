import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import 'plans_models.dart';
import 'plans_repository.dart';

class PlansController extends ChangeNotifier {
  final PlansRepository _repository;

  ResourceState<List<PlanCatalogEntry>> state = const ResourceState.loading();
  bool isYearly = true;
  bool isPurchasing = false;
  int purchaseRevision = 0;
  String? actionError;

  PlansController(this._repository);

  // App-wide provider: skip a repeat catalogue load and never overlap loads.
  bool _isLoading = false;

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && state.hasData) return;
    _isLoading = true;
    state = const ResourceState.loading();
    notifyListeners();
    try {
      final catalog = await _repository.getCatalog();
      state = ResourceState.data(catalog);
    } on ApiException catch (e) {
      state = ResourceState.error(e.userMessage);
    } catch (_) {
      state = const ResourceState.error(ApiException.genericMessage);
    } finally {
      _isLoading = false;
    }
    notifyListeners();
  }

  void setBillingCycle({required bool yearly}) {
    isYearly = yearly;
    notifyListeners();
  }

  Future<bool> purchase(String planId) async {
    if (isPurchasing) return false;
    isPurchasing = true;
    actionError = null;
    notifyListeners();
    try {
      await _repository.purchase(
          planId: planId, billingCycle: isYearly ? 'Yearly' : 'Monthly');
      purchaseRevision++;
      isPurchasing = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      actionError = e.userMessage;
    } catch (_) {
      actionError = ApiException.genericMessage;
    }
    isPurchasing = false;
    notifyListeners();
    return false;
  }
}
