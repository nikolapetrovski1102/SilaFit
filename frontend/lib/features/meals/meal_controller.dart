import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import 'meal_models.dart';
import 'meal_repository.dart';

/// Drives the Nutrition screen: loads one day's meals + targets, and applies
/// an optimistic local status flip (Planned -> Logged) before reconciling
/// with the server - same "instant, then confirm" pattern as
/// `TodayController`'s hydration quick-log.
class MealController extends ChangeNotifier {
  final MealRepository _repository;

  DateTime _selectedDate = DateTime.now();
  ResourceState<MealDay> state = const ResourceState.loading();
  String? actionError;

  // Loaded once per screen visit rather than per selected day - suggestions
  // are keyed off the calendar month, not the day being viewed, so there's
  // no need to re-fetch when the day strip selection changes.
  ResourceState<List<MealSuggestion>> suggestionsState =
      const ResourceState.loading();

  // App-wide provider: guard the day and the suggestions independently so a
  // remount/retry can't refetch one the other screen already loaded.
  bool _dayLoading = false;
  bool _suggestionsLoading = false;

  MealController(this._repository);

  DateTime get selectedDate => _selectedDate;

  Future<void> load({bool force = false}) => Future.wait([
        _loadFor(_selectedDate, force: force),
        _loadSuggestions(force: force),
      ]);

  /// Public re-entry point for [_loadSuggestions] - used by
  /// MealSuggestionsScreen, which only needs the suggestions half of [load]
  /// (the day/targets half is already loaded and shared via this same
  /// controller instance).
  Future<void> loadSuggestions({bool force = false}) =>
      _loadSuggestions(force: force);

  Future<void> _loadSuggestions({bool force = false}) async {
    if (_suggestionsLoading) return;
    if (!force && suggestionsState.hasData) return;
    _suggestionsLoading = true;
    suggestionsState = const ResourceState.loading();
    notifyListeners();
    try {
      final suggestions = await _repository.getSuggestions();
      suggestionsState = ResourceState.data(suggestions);
    } on ApiException catch (e) {
      suggestionsState = ResourceState.error(e.userMessage);
    } catch (_) {
      suggestionsState = const ResourceState.error(ApiException.genericMessage);
    } finally {
      _suggestionsLoading = false;
    }
    notifyListeners();
  }

  Future<void> selectDate(DateTime date) {
    // Tapping the already-selected day pill is a no-op, not a refetch.
    if (_isSameDay(date, _selectedDate)) return Future.value();
    return _loadFor(date, force: true);
  }

  Future<void> _loadFor(DateTime date, {bool force = false}) async {
    if (_dayLoading) return;
    if (!force && _isSameDay(date, _selectedDate) && state.hasData) return;
    _selectedDate = date;
    _dayLoading = true;
    state = const ResourceState.loading();
    notifyListeners();
    try {
      final day = await _repository.getDay(date);
      state = ResourceState.data(day);
    } on ApiException catch (e) {
      state = ResourceState.error(e.userMessage);
    } catch (_) {
      state = const ResourceState.error(ApiException.genericMessage);
    } finally {
      _dayLoading = false;
    }
    notifyListeners();
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Flips a planned meal to logged (or edits a logged one) - optimistic
  /// locally, reconciled with the server's recomputed day totals after.
  Future<void> logMeal(MealLog meal) async {
    final current = state.data;
    if (current == null) return;

    final optimisticMeal = meal.copyWith(status: 'Logged');
    final optimisticMeals = [
      for (final m in current.meals)
        m.mealLogId == meal.mealLogId ? optimisticMeal : m,
    ];
    state = ResourceState.data(_recompute(current, optimisticMeals));
    notifyListeners();

    try {
      await _repository.updateLog(optimisticMeal);
      await _loadFor(_selectedDate, force: true);
    } on ApiException catch (e) {
      state = ResourceState.data(current);
      actionError = e.userMessage;
      notifyListeners();
    } catch (_) {
      state = ResourceState.data(current);
      actionError = ApiException.genericMessage;
      notifyListeners();
    }
  }

  Future<bool> addMeal({
    required String mealType,
    required String title,
    required int caloriesKcal,
    required int proteinG,
    required int carbsG,
    required int fatsG,
    bool logNow = true,
  }) async {
    try {
      await _repository.createLog(
        logDate: _selectedDate,
        mealType: mealType,
        title: title,
        caloriesKcal: caloriesKcal,
        proteinG: proteinG,
        carbsG: carbsG,
        fatsG: fatsG,
        status: logNow ? 'Logged' : 'Planned',
      );
      await _loadFor(_selectedDate, force: true);
      return true;
    } on ApiException catch (e) {
      actionError = e.userMessage;
    } catch (_) {
      actionError = ApiException.genericMessage;
    }
    notifyListeners();
    return false;
  }

  Future<void> deleteMeal(String mealLogId) async {
    if (state.data == null) return;
    try {
      await _repository.deleteLog(mealLogId);
      await _loadFor(_selectedDate, force: true);
    } on ApiException catch (e) {
      actionError = e.userMessage;
      notifyListeners();
    } catch (_) {
      actionError = ApiException.genericMessage;
      notifyListeners();
    }
  }

  /// Recomputes the day's consumed/remaining totals locally from a Logged
  /// subset of [meals] - mirrors the backend's `MealDayDto` composition so
  /// the ring/macro bars update instantly on an optimistic flip.
  MealDay _recompute(MealDay current, List<MealLog> meals) {
    var calories = 0, protein = 0, carbs = 0, fats = 0;
    for (final meal in meals) {
      if (!meal.isLogged) continue;
      calories += meal.caloriesKcal;
      protein += meal.proteinG;
      carbs += meal.carbsG;
      fats += meal.fatsG;
    }
    return MealDay(
      targets: current.targets,
      meals: meals,
      consumedCalories: calories,
      remainingCalories: current.targets.targetCalories - calories,
      consumedProteinG: protein,
      consumedCarbsG: carbs,
      consumedFatsG: fats,
    );
  }
}

/// One instance per meal-suggestion-detail screen (not app-wide) - mirrors
/// SplitDetailController's per-screen isActivating/actionError/activated
/// fields, but delegates the actual write to the shared [MealController] so
/// "activating" a suggestion lands as a Planned meal on the day the user has
/// selected on the Nutrition screen, and that screen's list picks it up
/// immediately since it shares the same controller instance.
class MealSuggestionActivationController extends ChangeNotifier {
  final MealController _mealController;
  final MealSuggestion suggestion;

  bool isActivating = false;
  String? actionError;
  bool activated = false;

  MealSuggestionActivationController(this._mealController, this.suggestion);

  Future<bool> activate() async {
    isActivating = true;
    actionError = null;
    notifyListeners();

    final ok = await _mealController.addMeal(
      mealType: suggestion.mealType,
      title: suggestion.title,
      caloriesKcal: suggestion.caloriesKcal,
      proteinG: suggestion.proteinG,
      carbsG: suggestion.carbsG,
      fatsG: suggestion.fatsG,
      // Planned, not Logged - activating adds it to the plan; the user still
      // confirms it was eaten from the day's meal list, same as any other
      // planned meal.
      logNow: false,
    );

    isActivating = false;
    if (ok) {
      activated = true;
    } else {
      actionError = _mealController.actionError ?? ApiException.genericMessage;
    }
    notifyListeners();
    return ok;
  }
}
