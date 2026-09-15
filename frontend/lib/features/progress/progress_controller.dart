import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import 'progress_models.dart';
import 'progress_repository.dart';

class ProgressController extends ChangeNotifier {
  final ProgressRepository _repository;

  ResourceState<ProgressOverview> state = const ResourceState.loading();

  /// Independent of [state]: the Personal Records card renders regardless of
  /// how the overview load went, so its own request gets its own resource
  /// state rather than blocking (or being blocked by) the overview.
  ResourceState<List<PersonalRecord>> prsState = const ResourceState.loading();

  /// Backs the timeframe filter pills - `/api/progress` already accepts a
  /// `days` query param server-side, so this is a real filter, not a
  /// decorative one.
  int days = 30;

  // App-wide provider: guard both requests so a remount/retry can't re-fetch
  // what we already have, and so the two halves never overlap themselves.
  bool _overviewLoading = false;
  bool _prsLoading = false;

  ProgressController(this._repository);

  Future<void> load({bool force = false}) async {
    if (!force && state.hasData && prsState.hasData) return;
    await Future.wait([
      _loadOverview(force: force),
      _loadPersonalRecords(force: force),
    ]);
  }

  Future<void> _loadOverview({bool force = false}) async {
    if (_overviewLoading) return;
    if (!force && state.hasData) return;
    _overviewLoading = true;
    state = const ResourceState.loading();
    notifyListeners();
    try {
      final overview = await _repository.getOverview(days: days, force: force);
      state = ResourceState.data(overview);
    } on ApiException catch (e) {
      state = ResourceState.error(e.userMessage);
    } catch (_) {
      state = const ResourceState.error(ApiException.genericMessage);
    } finally {
      _overviewLoading = false;
    }
    notifyListeners();
  }

  Future<void> _loadPersonalRecords({bool force = false}) async {
    if (_prsLoading) return;
    if (!force && prsState.hasData) return;
    _prsLoading = true;
    prsState = const ResourceState.loading();
    notifyListeners();
    try {
      final records = await _repository.getPersonalRecords();
      prsState = ResourceState.data(records);
    } on ApiException catch (e) {
      prsState = ResourceState.error(e.userMessage);
    } catch (_) {
      prsState = const ResourceState.error(ApiException.genericMessage);
    } finally {
      _prsLoading = false;
    }
    notifyListeners();
  }

  /// Only reloads the overview - Personal Records are lifetime bests, not
  /// scoped to the timeframe pills, so a timeframe change has nothing new
  /// for that card to fetch.
  Future<void> setDays(int value) {
    if (value == days) return Future.value();
    days = value;
    return _loadOverview(force: true);
  }
}
