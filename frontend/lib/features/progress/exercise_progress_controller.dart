import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import 'progress_models.dart';
import 'progress_repository.dart';

/// Whether the caller may use per-exercise progress tracking. Learned from
/// the server (a 403 on `/progress/exercises`) rather than the client's own
/// read of the plan, so the backend's gate - including its dev-only
/// `DevTiersFree` override - stays the single source of truth.
enum ExerciseProgressAccess { unknown, granted, locked }

enum ExerciseProgressMetric { estimatedOneRm, topSet, volume, reps }

/// Unit of the tracker's "last N months / years" timeframe. [maxAmount]
/// keeps every pick within the server's two-year cap (730 days).
enum ProgressTimeframeUnit {
  month(days: 30, maxAmount: 12, short: 'M', singular: 'month'),
  year(days: 365, maxAmount: 2, short: 'Y', singular: 'year');

  final int days;
  final int maxAmount;
  final String short;
  final String singular;

  const ProgressTimeframeUnit({
    required this.days,
    required this.maxAmount,
    required this.short,
    required this.singular,
  });

  String describe(int amount) => '$amount $singular${amount == 1 ? '' : 's'}';
}

/// App-wide controller for the PRO/Advanced per-exercise tracker on the
/// Progress screen. Kept apart from [ProgressController] because its requests
/// are entitlement-gated while the overview's are not (Home's day strip and
/// streak sheet share the overview).
class ExerciseProgressController extends ChangeNotifier {
  final ProgressRepository _repository;

  ExerciseProgressAccess access = ExerciseProgressAccess.unknown;

  /// Granted only by a rewarded-video pass (see [unlockWithAdPass]), which
  /// ends when the user leaves the Progress screen.
  bool viaAdPass = false;
  ResourceState<List<TrackedExercise>> exercisesState =
      const ResourceState.loading();
  ResourceState<ExerciseProgress> progressState = const ResourceState.loading();
  String? selectedExerciseId;
  ExerciseProgressMetric metric = ExerciseProgressMetric.estimatedOneRm;

  /// The tracker's own "last N months / years" window, picked inside
  /// [ExerciseProgressCard] - independent of [ProgressController.days].
  int timeframeAmount = 1;
  ProgressTimeframeUnit timeframeUnit = ProgressTimeframeUnit.month;

  int get days => timeframeAmount * timeframeUnit.days;

  bool _exercisesLoading = false;

  // Bumped on every progress request so a slow response for a previously
  // selected exercise/timeframe can't overwrite the current one.
  int _progressRequest = 0;

  ExerciseProgressController(this._repository);

  TrackedExercise? get selectedExercise {
    final exercises = exercisesState.data;
    if (exercises == null) return null;
    for (final e in exercises) {
      if (e.exerciseId == selectedExerciseId) return e;
    }
    return null;
  }

  Future<void> load({bool force = false}) async {
    if (_exercisesLoading) return;
    if (!force && exercisesState.hasData) return;
    _exercisesLoading = true;
    exercisesState = const ResourceState.loading();
    notifyListeners();
    try {
      final exercises =
          await _repository.getTrackedExercises(cache: !viaAdPass);
      access = ExerciseProgressAccess.granted;
      exercisesState = ResourceState.data(exercises);
      if (!exercises.any((e) => e.exerciseId == selectedExerciseId)) {
        selectedExerciseId =
            exercises.isEmpty ? null : exercises.first.exerciseId;
      }
    } on ApiException catch (e) {
      if (e.isForbidden) {
        access = ExerciseProgressAccess.locked;
        viaAdPass = false;
        exercisesState = const ResourceState.error('');
      } else {
        exercisesState = ResourceState.error(e.userMessage);
      }
    } catch (_) {
      exercisesState = const ResourceState.error(ApiException.genericMessage);
    } finally {
      _exercisesLoading = false;
    }
    notifyListeners();
    if (selectedExerciseId != null) await _loadProgress();
  }

  Future<void> select(String exerciseId) {
    if (exerciseId == selectedExerciseId) return Future.value();
    selectedExerciseId = exerciseId;
    return _loadProgress();
  }

  Future<void> setTimeframe(int amount, ProgressTimeframeUnit unit) {
    final clamped = amount.clamp(1, unit.maxAmount);
    if (clamped == timeframeAmount && unit == timeframeUnit) {
      return Future.value();
    }
    timeframeAmount = clamped;
    timeframeUnit = unit;
    if (access != ExerciseProgressAccess.granted || selectedExerciseId == null) {
      notifyListeners();
      return Future.value();
    }
    return _loadProgress();
  }

  void setMetric(ExerciseProgressMetric value) {
    if (value == metric) return;
    metric = value;
    notifyListeners();
  }

  Future<void> retryProgress() => _loadProgress();

  /// Asks the server for an ad pass after a rewarded video was watched, then
  /// reloads the tracker under it. Throws the server's [ApiException] (a 429
  /// once the day's passes are used up) for the screen to show.
  Future<void> unlockWithAdPass() async {
    viaAdPass = await _repository.grantAdPass();
    await load(force: true);
  }

  /// Locks the screen again and ends the pass server-side, so one ad buys
  /// one look rather than the pass's full lifetime.
  Future<void> endAdPass() async {
    if (!viaAdPass) return;
    viaAdPass = false;
    ++_progressRequest;
    access = ExerciseProgressAccess.locked;
    exercisesState = const ResourceState.error('');
    progressState = const ResourceState.loading();
    notifyListeners();
    try {
      await _repository.endAdPass();
    } catch (_) {}
  }

  Future<void> _loadProgress() async {
    final exerciseId = selectedExerciseId;
    if (exerciseId == null) return;
    final request = ++_progressRequest;
    progressState = const ResourceState.loading();
    notifyListeners();
    ResourceState<ExerciseProgress> next;
    try {
      next = ResourceState.data(
          await _repository.getExerciseProgress(exerciseId,
              days: days, cache: !viaAdPass));
    } on ApiException catch (e) {
      if (e.isForbidden) {
        access = ExerciseProgressAccess.locked;
        viaAdPass = false;
      }
      next = ResourceState.error(e.userMessage);
    } catch (_) {
      next = const ResourceState.error(ApiException.genericMessage);
    }
    if (request != _progressRequest) return;
    progressState = next;
    notifyListeners();
  }
}
