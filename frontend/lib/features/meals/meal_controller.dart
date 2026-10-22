import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart' show queuedWriteTimeout;
import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import '../../core/sync/sync_queue.dart';
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

  /// True while a day fetch is in flight. The previously selected day's data
  /// stays in [state] for the duration, so the ring/macro bars interpolate to
  /// the new values instead of the whole section collapsing to a spinner.
  bool isDayLoading = false;

  // Loaded once per screen visit rather than per selected day - suggestions
  // are keyed off the calendar month, not the day being viewed, so there's
  // no need to re-fetch when the day strip selection changes.
  ResourceState<List<MealSuggestion>> suggestionsState =
      const ResourceState.loading();

  // App-wide provider: guard the suggestions independently so a remount/retry
  // can't refetch what another screen already loaded. Day fetches are instead
  // tracked by request id (below) so a newer tap supersedes an in-flight one.
  bool _suggestionsLoading = false;
  int _dayRequestId = 0;

  /// Where meal writes go when the server can't be reached - see
  /// [SyncQueue]. Null means a failed write is just an error.
  final SyncQueue? _syncQueue;

  MealController(this._repository, {SyncQueue? syncQueue})
      : _syncQueue = syncQueue {
    _syncQueue?.syncedVersion.addListener(_onSynced);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _syncQueue?.syncedVersion.removeListener(_onSynced);
    super.dispose();
  }

  /// A load started by a sync can finish after sign-out has torn this
  /// controller down - its result just has nowhere to go.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// Queued meal writes reached the server - re-fetch the day for real.
  void _onSynced() {
    if (state.hasData) _loadFor(_selectedDate, force: true);
  }

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
    if (!force && _isSameDay(date, _selectedDate) && state.hasData) return;

    // Request id rather than a simple "already loading" guard: tapping day B
    // then C must land on C, not have C dropped because B is still in flight.
    final requestId = ++_dayRequestId;
    final previous = state.data;
    _selectedDate = date;
    isDayLoading = true;
    // Keep the current day's numbers on screen while the next one loads, so
    // switching days interpolates the ring/macros instead of flashing a
    // spinner over everything (only a cold start has no data to keep).
    if (previous == null) state = const ResourceState.loading();
    notifyListeners();
    try {
      final day = await _withPendingWrites(await fetchPaintingCached(
        cached: () => _repository.getCachedDay(date),
        fetch: () => _repository.getDay(date),
        paint: (saved) async {
          // Only over a skeleton - never over another day's real numbers.
          bool stale() =>
              requestId != _dayRequestId || !isDayLoading || state.hasData;
          if (stale()) return;
          final shown = await _withPendingWrites(saved);
          if (stale()) return;
          state = ResourceState.data(shown);
          notifyListeners();
        },
      ));
      if (requestId != _dayRequestId) return;
      state = ResourceState.data(day);
    } on ApiException catch (e) {
      if (requestId != _dayRequestId) return;
      state = ResourceState.error(e.userMessage);
    } catch (_) {
      if (requestId != _dayRequestId) return;
      state = const ResourceState.error(ApiException.genericMessage);
    } finally {
      if (requestId == _dayRequestId) {
        isDayLoading = false;
        notifyListeners();
      }
    }
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
      // No signal: keep the optimistic flip and upload it later.
      if (await _queueUpsert(e, optimisticMeal)) return;
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
    final meal = MealLog(
      mealLogId: const Uuid().v4(),
      logDateUtc: MealRepository.isoDate(_selectedDate),
      mealType: mealType,
      title: title,
      caloriesKcal: caloriesKcal,
      proteinG: proteinG,
      carbsG: carbsG,
      fatsG: fatsG,
      status: logNow ? 'Logged' : 'Planned',
    );
    try {
      await _create(meal);
      await _loadFor(_selectedDate, force: true);
      return true;
    } on ApiException catch (e) {
      if (await _queueUpsert(e, meal)) return true;
      actionError = e.userMessage;
    } catch (_) {
      actionError = ApiException.genericMessage;
    }
    notifyListeners();
    return false;
  }

  /// Saves a meal built food-by-food in the meal tracker - a new Logged meal
  /// on the selected day, or an edit of [existing]. Totals are sent for
  /// completeness, but the server recomputes them from [items].
  Future<bool> saveTrackedMeal({
    MealLog? existing,
    required String mealType,
    required String title,
    required List<MealLogItem> items,
  }) async {
    final totals = MealTotals.of(items);
    final meal = MealLog(
      mealLogId: existing?.mealLogId ?? const Uuid().v4(),
      logDateUtc:
          existing?.logDateUtc ?? MealRepository.isoDate(_selectedDate),
      mealType: mealType,
      title: title,
      caloriesKcal: totals.caloriesKcal.round(),
      proteinG: totals.proteinG.round(),
      carbsG: totals.carbsG.round(),
      fatsG: totals.fatsG.round(),
      status: 'Logged',
      plannedLocalTime: existing?.plannedLocalTime,
      items: items,
    );
    try {
      if (existing == null) {
        await _create(meal);
      } else {
        await _repository.updateLog(meal);
      }
      await _loadFor(_selectedDate, force: true);
      return true;
    } on ApiException catch (e) {
      if (await _queueUpsert(e, meal)) return true;
      actionError = e.userMessage;
    } catch (_) {
      actionError = ApiException.genericMessage;
    }
    notifyListeners();
    return false;
  }

  Future<MealLog> _create(MealLog meal) => _repository.createLog(
        mealLogId: meal.mealLogId,
        logDate: DateTime.parse(meal.logDateUtc),
        mealType: meal.mealType,
        title: meal.title,
        caloriesKcal: meal.caloriesKcal,
        proteinG: meal.proteinG,
        carbsG: meal.carbsG,
        fatsG: meal.fatsG,
        status: meal.status,
        items: meal.items.isEmpty ? null : meal.items,
        timeout: queuedWriteTimeout,
      );

  /// After a failed create/edit of [meal]: when the server just couldn't be
  /// reached, queue the write for later, show it on the day straight away,
  /// and return true. False when [error] is a real refusal to report.
  Future<bool> _queueUpsert(ApiException error, MealLog meal) async {
    final queue = _syncQueue;
    if (!error.isRetryable || queue == null) return false;
    await queue.enqueue(PendingWrite.create(
      kind: SyncQueue.kindMealUpsert,
      method: 'PUT',
      path: MealRepository.logPath(meal.mealLogId),
      body: MealRepository.logBody(meal),
      entityId: meal.mealLogId,
    ));
    await _repaintWithPending();
    return true;
  }

  Future<void> _repaintWithPending() async {
    final current = state.data;
    if (current == null) return;
    state = ResourceState.data(await _withPendingWrites(current));
    notifyListeners();
  }

  /// Meal writes still waiting in the offline queue, replayed over [day]
  /// (fresh from the server or its saved copy, which can't include them
  /// yet) so a meal logged with no signal doesn't vanish from the list -
  /// and from the calorie ring - on the next refresh or app restart.
  Future<MealDay> _withPendingWrites(MealDay day) async {
    final queue = _syncQueue;
    if (queue == null) return day;
    await queue.ready();
    final writes = queue.pending.where((w) =>
        w.kind == SyncQueue.kindMealUpsert ||
        w.kind == SyncQueue.kindMealDelete);
    if (writes.isEmpty) return day;

    final date = MealRepository.isoDate(_selectedDate);
    final meals = List.of(day.meals);
    for (final write in writes) {
      final id = write.entityId;
      if (id == null) continue;
      final index = meals.indexWhere((m) => m.mealLogId == id);
      if (write.kind == SyncQueue.kindMealDelete) {
        if (index >= 0) meals.removeAt(index);
        continue;
      }
      final body = write.body;
      if (body == null || body['logDateUtc'] != date) continue;
      MealLog meal;
      try {
        meal = MealLog.fromJson({...body, 'mealLogId': id});
      } catch (_) {
        continue;
      }
      if (index >= 0) {
        // An edit that didn't resend the foods keeps the stored ones, same
        // as the server does.
        if (meal.items.isEmpty && meals[index].items.isNotEmpty) {
          meal = MealLog(
            mealLogId: meal.mealLogId,
            logDateUtc: meal.logDateUtc,
            mealType: meal.mealType,
            title: meal.title,
            caloriesKcal: meal.caloriesKcal,
            proteinG: meal.proteinG,
            carbsG: meal.carbsG,
            fatsG: meal.fatsG,
            status: meal.status,
            plannedLocalTime: meal.plannedLocalTime,
            items: meals[index].items,
          );
        }
        meals[index] = meal;
      } else {
        meals.add(meal);
      }
    }
    return _recompute(day, meals);
  }

  Future<List<FoodItem>> searchFoods(String query) =>
      _repository.searchFoods(query);

  Future<FoodScanQuota> getScanQuota() => _repository.getScanQuota();

  Future<FoodScanResult> scanFood(List<int> jpegBytes, {String? mealName}) =>
      _repository.scanFood(jpegBytes, mealName: mealName);

  Future<FoodItem> createCustomFood({
    required String name,
    String? brandName,
    double? servingSizeG,
    required double caloriesKcal,
    required double proteinG,
    required double carbohydrateG,
    required double fatG,
    double? fiberG,
    double? sugarG,
    double? sodiumMg,
  }) =>
      _repository.createCustomFood(
        name: name,
        brandName: brandName,
        servingSizeG: servingSizeG,
        caloriesKcal: caloriesKcal,
        proteinG: proteinG,
        carbohydrateG: carbohydrateG,
        fatG: fatG,
        fiberG: fiberG,
        sugarG: sugarG,
        sodiumMg: sodiumMg,
      );

  Future<void> deleteMeal(String mealLogId) async {
    if (state.data == null) return;
    try {
      await _repository.deleteLog(mealLogId);
      await _loadFor(_selectedDate, force: true);
    } on ApiException catch (e) {
      final queue = _syncQueue;
      if (e.isRetryable && queue != null) {
        await queue.enqueue(PendingWrite.create(
          kind: SyncQueue.kindMealDelete,
          method: 'DELETE',
          path: MealRepository.logPath(mealLogId),
          entityId: mealLogId,
        ));
        await _repaintWithPending();
        return;
      }
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
