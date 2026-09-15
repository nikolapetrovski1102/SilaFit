import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import 'splits_models.dart';
import 'splits_repository.dart';

class SplitsController extends ChangeNotifier {
  final SplitsRepository _repository;

  ResourceState<List<WorkoutSplit>> state = const ResourceState.loading();

  // App-wide provider: skip a repeat load when we already have the catalogue,
  // and never overlap two loads. `force` is the explicit refresh path.
  bool _isLoading = false;

  SplitsController(this._repository);

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && state.hasData) return;
    _isLoading = true;
    state = const ResourceState.loading();
    notifyListeners();
    try {
      final splits = await _repository.getAll();
      state = ResourceState.data(splits);
    } on ApiException catch (e) {
      state = ResourceState.error(e.userMessage);
    } catch (_) {
      state = const ResourceState.error(ApiException.genericMessage);
    } finally {
      _isLoading = false;
    }
    notifyListeners();
  }
}

/// One instance per split-detail screen (not app-wide), so it's created
/// where it's pushed rather than registered globally.
class SplitDetailController extends ChangeNotifier {
  final SplitsRepository _repository;
  final String splitId;

  ResourceState<SplitDetail> state = const ResourceState.loading();
  bool isActivating = false;
  String? actionError;
  bool activated = false;

  SplitDetailController(this._repository, this.splitId);

  bool _isLoading = false;

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && state.hasData) return;
    _isLoading = true;
    state = const ResourceState.loading();
    notifyListeners();
    try {
      final detail = await _repository.getDetail(splitId);
      state = ResourceState.data(detail);
    } on ApiException catch (e) {
      state = ResourceState.error(e.userMessage);
    } catch (_) {
      state = const ResourceState.error(ApiException.genericMessage);
    } finally {
      _isLoading = false;
    }
    notifyListeners();
  }

  Future<bool> activate() async {
    isActivating = true;
    actionError = null;
    notifyListeners();
    try {
      await _repository.activate(splitId);
      activated = true;
      isActivating = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      actionError = e.userMessage;
    } catch (_) {
      actionError = ApiException.genericMessage;
    }
    isActivating = false;
    notifyListeners();
    return false;
  }
}
