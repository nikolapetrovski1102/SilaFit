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

/// App-wide controller for the PRO/Advanced per-exercise tracker on the
/// Progress screen. Kept apart from [ProgressController] because its requests
/// are entitlement-gated while the overview's are not (Home's day strip and
/// streak sheet share the overview).
class ExerciseProgressController extends ChangeNotifier {
  final ProgressRepository _repository;

  ExerciseProgressAccess access = ExerciseProgressAccess.unknown;
  ResourceState<List<TrackedExercise>> exercisesState =
      const ResourceState.loading();
  ResourceState<ExerciseProgress> progressState = const ResourceState.loading();
  String? selectedExerciseId;
  ExerciseProgressMetric metric = ExerciseProgressMetric.estimatedOneRm;

  /// Mirrors the Progress screen's timeframe pills, which drive both this
  /// and [ProgressController.days].
  int days = 30;

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
      final exercises = await _repository.getTrackedExercises();
      access = ExerciseProgressAccess.granted;
      exercisesState = ResourceState.data(exercises);
      if (!exercises.any((e) => e.exerciseId == selectedExerciseId)) {
        selectedExerciseId =
            exercises.isEmpty ? null : exercises.first.exerciseId;
      }
    } on ApiException catch (e) {
      if (e.isForbidden) {
        access = ExerciseProgressAccess.locked;
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

  Future<void> setDays(int value) {
    if (value == days) return Future.value();
    days = value;
    if (access != ExerciseProgressAccess.granted || selectedExerciseId == null) {
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

  Future<void> _loadProgress() async {
    final exerciseId = selectedExerciseId;
    if (exerciseId == null) return;
    final request = ++_progressRequest;
    progressState = const ResourceState.loading();
    notifyListeners();
    ResourceState<ExerciseProgress> next;
    try {
      next = ResourceState.data(
          await _repository.getExerciseProgress(exerciseId, days: days));
    } on ApiException catch (e) {
      if (e.isForbidden) access = ExerciseProgressAccess.locked;
      next = ResourceState.error(e.userMessage);
    } catch (_) {
      next = const ResourceState.error(ApiException.genericMessage);
    }
    if (request != _progressRequest) return;
    progressState = next;
    notifyListeners();
  }
}
