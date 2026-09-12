import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import 'today_models.dart';
import 'today_repository.dart';

/// Drives the Today screen end to end: loads the dashboard, and applies
/// optimistic local updates for the two quick-log actions before
/// reconciling with the server response.
class TodayController extends ChangeNotifier {
  final TodayRepository _repository;

  ResourceState<TodayDashboard> state = const ResourceState.loading();
  String? actionError;

  TodayController(this._repository);

  Future<void> load() async {
    // Only drop to the loading spinner on the very first load, when there's
    // no dashboard to show yet. On a pull-to-refresh, `state` already has
    // data - keep showing it while refetching instead of wiping it to
    // `loading()`. Doing that swaps ResourceBuilder over to a differently-
    // shaped widget for a beat, which tears down FitHeight's element (and
    // the fitted scale it had already settled on) and remounts it fresh
    // once the new dashboard lands - visible as a one-frame flash at the
    // wrong scale, with dead space where the old, correctly-scaled content
    // used to be. RefreshIndicator's own spinner already communicates
    // "refreshing"; the body doesn't need to blank out too.
    if (!state.hasData) {
      state = const ResourceState.loading();
      notifyListeners();
    }
    try {
      final dashboard = await _repository.getDashboard();
      state = ResourceState.data(dashboard);
    } on ApiException catch (e) {
      state = ResourceState.error(e.userMessage, staleData: state.data);
    } catch (_) {
      state = ResourceState.error(ApiException.genericMessage,
          staleData: state.data);
    }
    notifyListeners();
  }

  Future<void> logHydration(int amountMl) async {
    final current = state.data;
    if (current == null) return;

    // Optimistic bump so the UI feels instant, per the mockup's micro-interaction.
    state = ResourceState.data(current.copyWith(
        hydrationTotalMl: current.hydrationTotalMl + amountMl));
    notifyListeners();

    try {
      final total = await _repository.logHydration(amountMl);
      state = ResourceState.data(state.data!.copyWith(hydrationTotalMl: total));
    } on ApiException catch (e) {
      state = ResourceState.data(current); // roll back
      actionError = e.userMessage;
    } catch (_) {
      state = ResourceState.data(current);
      actionError = ApiException.genericMessage;
    }
    notifyListeners();
  }

  Future<bool> logBodyweight(double weightKg) async {
    final current = state.data;
    if (current == null) return false;
    try {
      final result = await _repository.logBodyweight(weightKg);
      state = ResourceState.data(current.copyWith(
          latestWeightKg: result.latestWeightKg,
          weightDeltaKg: result.deltaKg));
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      actionError = e.userMessage;
    } catch (_) {
      actionError = ApiException.genericMessage;
    }
    notifyListeners();
    return false;
  }

  Future<bool> completeWorkout({
    required String workoutSessionId,
    required int durationMinutes,
    int? caloriesEstimate,
    double? rpeScore,
    double? tonnageKg,
  }) async {
    try {
      await _repository.completeWorkout(
        workoutSessionId: workoutSessionId,
        durationMinutes: durationMinutes,
        caloriesEstimate: caloriesEstimate,
        rpeScore: rpeScore,
        tonnageKg: tonnageKg,
      );
      await load();
      return true;
    } on ApiException catch (e) {
      actionError = e.userMessage;
    } catch (_) {
      actionError = ApiException.genericMessage;
    }
    notifyListeners();
    return false;
  }
}
