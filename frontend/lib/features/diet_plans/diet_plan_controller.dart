import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import 'diet_plan_models.dart';
import 'diet_plan_repository.dart';

class DietPlansController extends ChangeNotifier {
  final DietPlanRepository _repository;

  ResourceState<List<DietPlan>> state = const ResourceState.loading();

  // App-wide provider: skip a repeat load when we already have the catalogue,
  // and never overlap two loads. `force` is the explicit refresh path.
  bool _isLoading = false;

  DietPlansController(this._repository);

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && state.hasData) return;
    _isLoading = true;
    state = const ResourceState.loading();
    notifyListeners();
    try {
      final plans = await _repository.getAll();
      state = ResourceState.data(plans);
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

/// One instance per diet-plan-detail screen (not app-wide), so it's created
/// where it's pushed rather than registered globally.
class DietPlanDetailController extends ChangeNotifier {
  final DietPlanRepository _repository;
  final String dietPlanId;

  ResourceState<DietPlanDetail> state = const ResourceState.loading();
  bool isKeeping = false;
  String? actionError;

  DietPlanDetailController(this._repository, this.dietPlanId);

  bool _isLoading = false;

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && state.hasData) return;
    _isLoading = true;
    state = const ResourceState.loading();
    notifyListeners();
    try {
      final detail = await _repository.getDetail(dietPlanId);
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

  /// Marks an AI-generated diet plan permanent, so next Sunday's generation
  /// creates a fresh plan instead of overwriting this one in place.
  Future<bool> keep() async {
    isKeeping = true;
    actionError = null;
    notifyListeners();
    try {
      await _repository.keep(dietPlanId);
      isKeeping = false;
      notifyListeners();
      await load(force: true);
      return true;
    } on ApiException catch (e) {
      actionError = e.userMessage;
    } catch (_) {
      actionError = ApiException.genericMessage;
    }
    isKeeping = false;
    notifyListeners();
    return false;
  }
}

/// App-wide provider for the "My diet plans" list - plans this user built
/// themselves via the in-app builder (always isEditableByMe == true).
class MyDietPlansController extends ChangeNotifier {
  final DietPlanRepository _repository;

  ResourceState<List<DietPlan>> state = const ResourceState.loading();

  bool _isLoading = false;

  MyDietPlansController(this._repository);

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && state.hasData) return;
    _isLoading = true;
    state = const ResourceState.loading();
    notifyListeners();
    try {
      final plans = await _repository.getMine();
      state = ResourceState.data(plans);
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

/// Wrapper so "no active plan" (a normal, renderable state) is distinguishable
/// from "not loaded yet" - `ResourceState.hasData` is false for a null payload,
/// so the null-ness has to live one level in.
class ActiveDietPlan {
  final DietPlanDetail? plan;

  const ActiveDietPlan(this.plan);
}

/// App-wide provider backing the Nutrition screen's "active plan" section and
/// its on-demand generation action. Holds the full active plan (days + meals)
/// so the screen can render the viewed day without a second request.
class ActiveDietPlanController extends ChangeNotifier {
  final DietPlanRepository _repository;

  ResourceState<ActiveDietPlan> state = const ResourceState.loading();
  bool isGenerating = false;
  String? actionError;

  bool _isLoading = false;

  ActiveDietPlanController(this._repository);

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && state.hasData) return;
    _isLoading = true;
    // Keep the previous plan on screen while refreshing, so switching to this
    // tab or re-activating a plan doesn't flash a spinner over known content.
    if (!state.hasData) state = const ResourceState.loading();
    notifyListeners();
    try {
      state = ResourceState.data(ActiveDietPlan(await _repository.getActive()));
    } on ApiException catch (e) {
      state = ResourceState.error(e.userMessage);
    } catch (_) {
      state = const ResourceState.error(ApiException.genericMessage);
    } finally {
      _isLoading = false;
    }
    notifyListeners();
  }

  /// Generates a fresh plan from the user's calorie/macro targets and makes it
  /// active. Returns false (with [actionError] set) when generation is
  /// unavailable, e.g. the AI provider isn't configured.
  Future<bool> generate() async {
    if (isGenerating) return false;
    isGenerating = true;
    actionError = null;
    notifyListeners();
    try {
      final detail = await _repository.generate();
      state = ResourceState.data(ActiveDietPlan(detail));
      isGenerating = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      actionError = e.userMessage;
    } catch (_) {
      actionError = ApiException.genericMessage;
    }
    isGenerating = false;
    notifyListeners();
    return false;
  }

  Future<bool> activate(String dietPlanId) async {
    actionError = null;
    notifyListeners();
    try {
      await _repository.activate(dietPlanId);
      await load(force: true);
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

/// One instance per diet-plan-builder screen (not app-wide) - holds the
/// in-progress plan/day/meal edit state for a single build session.
class DietPlanBuilderController extends ChangeNotifier {
  final DietPlanRepository _repository;

  /// Null while creating a brand-new plan; set once the header has been
  /// saved for the first time, so subsequent day/meal saves have a parent
  /// to attach to.
  String? dietPlanId;

  DietPlanDetail? detail;
  ResourceState<DietPlanDetail>? loadState;

  bool isSaving = false;
  String? actionError;

  DietPlanBuilderController(this._repository, {this.dietPlanId});

  bool _isLoading = false;

  Future<void> load() async {
    final id = dietPlanId;
    if (id == null || _isLoading) return;
    _isLoading = true;
    loadState = const ResourceState.loading();
    notifyListeners();
    try {
      detail = await _repository.getDetail(id);
      loadState = ResourceState.data(detail!);
    } on ApiException catch (e) {
      loadState = ResourceState.error(e.userMessage);
    } catch (_) {
      loadState = const ResourceState.error(ApiException.genericMessage);
    } finally {
      _isLoading = false;
    }
    notifyListeners();
  }

  Future<bool> saveHeader({
    required String name,
    String? description,
    String? heroImageUrl,
    required String periodType,
    required int durationDays,
  }) =>
      _run(() async {
        final id = await _repository.createOrUpdate(
          dietPlanId: dietPlanId,
          name: name,
          description: description,
          heroImageUrl: heroImageUrl,
          periodType: periodType,
          durationDays: durationDays,
        );
        dietPlanId ??= id;
        await load();
      });

  Future<bool> deletePlan() {
    final id = dietPlanId;
    if (id == null) return Future.value(false);
    return _run(() => _repository.delete(id));
  }

  Future<bool> saveDay({
    String? dietPlanDayId,
    required int dayIndex,
    String? title,
  }) {
    final id = dietPlanId;
    if (id == null) return Future.value(false);
    return _run(() async {
      await _repository.saveDay(
        dietPlanDayId: dietPlanDayId,
        dietPlanId: id,
        dayIndex: dayIndex,
        title: title,
      );
      await load();
    });
  }

  Future<bool> deleteDay(String dietPlanDayId) => _run(() async {
        await _repository.deleteDay(dietPlanDayId);
        await load();
      });

  Future<bool> saveMeal({
    String? dietPlanMealId,
    required String dietPlanDayId,
    required String mealType,
    required String mealSuggestionId,
    required int sortOrder,
  }) =>
      _run(() async {
        await _repository.saveMeal(
          dietPlanMealId: dietPlanMealId,
          dietPlanDayId: dietPlanDayId,
          mealType: mealType,
          mealSuggestionId: mealSuggestionId,
          sortOrder: sortOrder,
        );
        await load();
      });

  Future<bool> deleteMeal(String dietPlanMealId) => _run(() async {
        await _repository.deleteMeal(dietPlanMealId);
        await load();
      });

  Future<bool> _run(Future<void> Function() action) async {
    isSaving = true;
    actionError = null;
    notifyListeners();
    try {
      await action();
      isSaving = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      actionError = e.userMessage;
    } catch (_) {
      actionError = ApiException.genericMessage;
    }
    isSaving = false;
    notifyListeners();
    return false;
  }
}
