import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import 'diet_guide_models.dart';
import 'diet_guide_repository.dart';

/// App-wide provider for the diet-guide catalogue. Mirrors `DietPlansController`:
/// skip a repeat load when we already have the data, never overlap two loads,
/// and leave `force` as the explicit refresh path.
class DietGuidesController extends ChangeNotifier {
  final DietGuideRepository _repository;

  ResourceState<List<DietGuide>> state = const ResourceState.loading();

  bool _isLoading = false;

  DietGuidesController(this._repository);

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && state.hasData) return;
    _isLoading = true;
    state = const ResourceState.loading();
    notifyListeners();
    try {
      final guides = await _repository.getAll();
      state = ResourceState.data(guides);
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

/// One instance per guide-detail screen (not app-wide), created where it's
/// pushed - same shape as `DietPlanDetailController`.
class DietGuideDetailController extends ChangeNotifier {
  final DietGuideRepository _repository;
  final String dietGuideId;

  ResourceState<DietGuideDetail> state = const ResourceState.loading();

  bool _isLoading = false;

  DietGuideDetailController(this._repository, this.dietGuideId);

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && state.hasData) return;
    _isLoading = true;
    state = const ResourceState.loading();
    notifyListeners();
    try {
      final detail = await _repository.getDetail(dietGuideId);
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
}
