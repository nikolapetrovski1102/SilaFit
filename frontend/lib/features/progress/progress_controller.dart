import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import 'progress_models.dart';
import 'progress_repository.dart';

/// Which series the hero trend chart plots. Purely a client-side view of the
/// already-fetched heatmap - switching metric never re-hits the network.
enum TrendMetric { sessions, volume, rpe }

class ProgressController extends ChangeNotifier {
  final ProgressRepository _repository;

  ResourceState<ProgressOverview> state = const ResourceState.loading();

  /// Backs the timeframe filter pills - `/api/progress` already accepts a
  /// `days` query param server-side, so this is a real filter, not a
  /// decorative one.
  int days = 30;

  TrendMetric metric = TrendMetric.sessions;

  ProgressController(this._repository);

  Future<void> load() async {
    state = const ResourceState.loading();
    notifyListeners();
    try {
      final overview = await _repository.getOverview(days: days);
      state = ResourceState.data(overview);
    } on ApiException catch (e) {
      state = ResourceState.error(e.userMessage);
    } catch (_) {
      state = const ResourceState.error(ApiException.genericMessage);
    }
    notifyListeners();
  }

  Future<void> setDays(int value) {
    if (value == days) return Future.value();
    days = value;
    return load();
  }

  void setMetric(TrendMetric value) {
    if (value == metric) return;
    metric = value;
    notifyListeners();
  }
}
