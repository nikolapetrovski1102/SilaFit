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

  /// Set once a 422 comes back - distinguishes "not enough logged history yet"
  /// from any other error so the UI can show an encouraging card instead of a
  /// generic one (see InsufficientAnalyticsDataException on the backend).
  bool notEnoughData = false;

  bool isRefreshing = false;

  // App-wide provider: the analytics tab used to refetch on every remount.
  bool _isLoading = false;

  AnalyticsController(this._repository);

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && state.hasData) return;
    _isLoading = true;
    requiresUpgrade = false;
    notEnoughData = false;
    state = const ResourceState.loading();
    notifyListeners();
    try {
      await _fetch(refresh: false);
    } finally {
      _isLoading = false;
    }
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
      notEnoughData = false;
      state = ResourceState.data(analytics);
    } on ApiException catch (e) {
      if (e.isForbidden) {
        requiresUpgrade = true;
        state = const ResourceState.error('');
      } else if (e.isInsufficientData) {
        notEnoughData = true;
        state = ResourceState.error(e.userMessage);
      } else {
        state = ResourceState.error(e.userMessage);
      }
    } catch (_) {
      state = const ResourceState.error(ApiException.genericMessage);
    }
    notifyListeners();
  }
}
