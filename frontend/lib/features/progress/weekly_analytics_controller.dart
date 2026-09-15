import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import 'analytics_models.dart';
import 'analytics_repository.dart';

/// App-wide controller for the ADVANCED-only weekly AI recap. Deliberately
/// separate from [AnalyticsController] (which owns the Pro monthly report) so
/// the two entitlements can be upsold independently: a Pro user sees the
/// weekly card locked to Advanced while still getting the monthly report.
class WeeklyAnalyticsController extends ChangeNotifier {
  final AnalyticsRepository _repository;

  ResourceState<WeeklyAnalytics> state = const ResourceState.loading();

  /// Set once a 403 comes back - for the weekly endpoint this means "not
  /// Advanced", so the UI shows the Advanced upsell card.
  bool requiresUpgrade = false;

  /// Set once a 422 comes back - not enough logged activity in the week yet.
  bool notEnoughData = false;

  bool isRefreshing = false;

  bool _isLoading = false;

  WeeklyAnalyticsController(this._repository);

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
      final analytics = await _repository.getWeekly(refresh: refresh);
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
