import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import 'analytics_models.dart';
import 'analytics_repository.dart';

class AnalyticsController extends ChangeNotifier {
  final AnalyticsRepository _repository;

  ResourceState<MonthlyAnalytics> state = const ResourceState.loading();

  /// Set once a 403 comes back - distinguishes "not Pro" from any other
  /// error so the UI can show an upsell card instead of a generic error.
  bool requiresUpgrade = false;

  bool isRefreshing = false;

  AnalyticsController(this._repository);

  Future<void> load() async {
    requiresUpgrade = false;
    state = const ResourceState.loading();
    notifyListeners();
    await _fetch(refresh: false);
  }

  Future<void> refresh() async {
    if (isRefreshing) return;
    isRefreshing = true;
    notifyListeners();
    await _fetch(refresh: true);
    isRefreshing = false;
    notifyListeners();
  }

  Future<void> _fetch({required bool refresh}) async {
    try {
      final analytics = await _repository.getMonthly(refresh: refresh);
      requiresUpgrade = false;
      state = ResourceState.data(analytics);
    } on ApiException catch (e) {
      if (e.isForbidden) {
        requiresUpgrade = true;
        state = const ResourceState.error('');
      } else {
        state = ResourceState.error(e.userMessage);
      }
    } catch (_) {
      state = const ResourceState.error(ApiException.genericMessage);
    }
    notifyListeners();
  }
}
