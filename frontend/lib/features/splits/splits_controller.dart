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

  ResourceState<SplitDetail> state;
  bool isActivating = false;
  bool isKeeping = false;
  String? actionError;
  bool activated = false;

  SplitDetailController(this._repository, this.splitId,
      {SplitDetail? initialDetail})
      : state = initialDetail == null
            ? const ResourceState.loading()
            : ResourceState.data(initialDetail);

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

  /// Marks an AI-generated split permanent, so next Sunday's generation
  /// creates a fresh split instead of overwriting this one in place.
  Future<bool> keep() async {
    isKeeping = true;
    actionError = null;
    notifyListeners();
    try {
      await _repository.keep(splitId);
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

/// App-wide provider for the "My splits" list - splits this user built
/// themselves via the in-app builder (always isEditableByMe == true).
class MySplitsController extends ChangeNotifier {
  final SplitsRepository _repository;

  ResourceState<List<WorkoutSplit>> state = const ResourceState.loading();

  bool _isLoading = false;

  MySplitsController(this._repository);

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && state.hasData) return;
    _isLoading = true;
    state = const ResourceState.loading();
    notifyListeners();
    try {
      final splits = await _repository.getMine();
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

/// One instance per split-builder screen (not app-wide) - holds the
/// in-progress split/day/exercise edit state for a single build session.
class SplitBuilderController extends ChangeNotifier {
  final SplitsRepository _repository;

  /// Null while creating a brand-new split; set once the header has been
  /// saved for the first time, so subsequent day/exercise saves have a
  /// parent to attach to.
  String? splitId;

  SplitDetail? detail;
  ResourceState<SplitDetail>? loadState;

  bool isSaving = false;
  String? actionError;

  bool isActivating = false;
  bool activated = false;

  SplitBuilderController(this._repository, {this.splitId});

  bool _isLoading = false;

  Future<void> load() async {
    final id = splitId;
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
    required String category,
    required String level,
    required int durationDays,
    String? description,
    String? heroImageUrl,
    String? recommendedGoal,
  }) =>
      _run(() async {
        final id = await _repository.createOrUpdate(
          splitId: splitId,
          name: name,
          category: category,
          level: level,
          durationDays: durationDays,
          description: description,
          heroImageUrl: heroImageUrl,
          recommendedGoal: recommendedGoal,
        );
        splitId ??= id;
        await load();
      });

  Future<bool> deleteSplit() {
    final id = splitId;
    if (id == null) return Future.value(false);
    return _run(() => _repository.delete(id));
  }

  Future<bool> activate() async {
    final id = splitId;
    if (id == null) return false;
    isActivating = true;
    actionError = null;
    notifyListeners();
    try {
      await _repository.activate(id);
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

  Future<bool> saveDay({
    String? splitDayId,
    required int dayIndex,
    required String title,
    String? focusLabel,
    int estimatedMinutes = 60,
    bool isRestDay = false,
  }) {
    final id = splitId;
    if (id == null) return Future.value(false);
    return _run(() async {
      await _repository.saveDay(
        splitDayId: splitDayId,
        splitId: id,
        dayIndex: dayIndex,
        title: title,
        focusLabel: focusLabel,
        estimatedMinutes: estimatedMinutes,
        isRestDay: isRestDay,
      );
      await load();
    });
  }

  Future<bool> deleteDay(String splitDayId) => _run(() async {
        await _repository.deleteDay(splitDayId);
        await load();
      });

  /// Applies [orderedSplitDayIds] - a full permutation of every day
  /// currently on this split - as the new day order, persisting 1-based
  /// `dayIndex` values one day at a time via [SplitsRepository.saveDay].
  ///
  /// `dbo.SplitDays` enforces UNIQUE(SplitId, DayIndex), so writing each
  /// day's new index in list order can 409 the moment two days trade
  /// places: the destination index is still held by whichever day is being
  /// displaced. Moves are sequenced instead - non-cyclic ones (a day whose
  /// target slot isn't held by anyone else still pending) go first, then
  /// whatever's left (always a closed cycle, since every remaining day's
  /// target is held by another remaining day) is routed through one spare
  /// index as a temporary parking spot, freeing a slot before the next day
  /// in the cycle claims it.
  Future<bool> reorderDays(List<String> orderedSplitDayIds) => _run(() async {
        final id = splitId;
        if (id == null) return;
        final days = {
          for (final d in detail?.days ?? const <SplitDayWithExercises>[])
            d.day.splitDayId: d.day,
        };
        final newIndexOf = <String, int>{
          for (var i = 0; i < orderedSplitDayIds.length; i++)
            orderedSplitDayIds[i]: i + 1,
        };

        Future<void> write(String dayId, int index) async {
          final day = days[dayId]!;
          await _repository.saveDay(
            splitDayId: dayId,
            splitId: id,
            dayIndex: index,
            title: day.title,
            focusLabel: day.focusLabel,
            estimatedMinutes: day.estimatedMinutes,
            isRestDay: day.isRestDay,
          );
        }

        final occupied = {for (final d in days.values) d.dayIndex};
        final pending = orderedSplitDayIds
            .where((dayId) => days[dayId]!.dayIndex != newIndexOf[dayId])
            .toSet();

        var moved = true;
        while (moved) {
          moved = false;
          for (final dayId in pending.toList()) {
            final target = newIndexOf[dayId]!;
            if (occupied.contains(target)) continue;
            occupied
              ..remove(days[dayId]!.dayIndex)
              ..add(target);
            await write(dayId, target);
            pending.remove(dayId);
            moved = true;
          }
        }

        while (pending.isNotEmpty) {
          var spare = -1;
          for (var v = 1; v <= 14; v++) {
            if (!occupied.contains(v)) {
              spare = v;
              break;
            }
          }
          final start = pending.first;
          if (spare == -1) {
            // No parking spot free - every index 1-14 is already claimed.
            // Write directly and let the server's own error surface rather
            // than spinning forever looking for a slot that doesn't exist.
            await write(start, newIndexOf[start]!);
            pending.remove(start);
            continue;
          }
          final startOldIndex = days[start]!.dayIndex;
          occupied
            ..remove(startOldIndex)
            ..add(spare);
          await write(start, spare);
          pending.remove(start);

          var holePos = startOldIndex;
          while (true) {
            String? next;
            for (final dayId in pending) {
              if (newIndexOf[dayId] == holePos) {
                next = dayId;
                break;
              }
            }
            if (next == null) break;
            final nextOldIndex = days[next]!.dayIndex;
            occupied
              ..remove(nextOldIndex)
              ..add(holePos);
            await write(next, holePos);
            pending.remove(next);
            holePos = nextOldIndex;
          }

          occupied
            ..remove(spare)
            ..add(newIndexOf[start]!);
          await write(start, newIndexOf[start]!);
        }

        await load();
      });

  Future<bool> saveDayExercise({
    String? splitDayExerciseId,
    required String splitDayId,
    required String exerciseId,
    required int sortOrder,
    required int targetSets,
    required int targetRepsLow,
    required int targetRepsHigh,
  }) =>
      _run(() async {
        await _repository.saveDayExercise(
          splitDayExerciseId: splitDayExerciseId,
          splitDayId: splitDayId,
          exerciseId: exerciseId,
          sortOrder: sortOrder,
          targetSets: targetSets,
          targetRepsLow: targetRepsLow,
          targetRepsHigh: targetRepsHigh,
        );
        await load();
      });

  Future<bool> deleteDayExercise(String splitDayExerciseId) => _run(() async {
        await _repository.deleteDayExercise(splitDayExerciseId);
        await load();
      });

  /// Applies [orderedSplitDayExerciseIds] - a full permutation of every
  /// exercise on [splitDayId] - as that day's new exercise order,
  /// persisting each slot's 0-based `sortOrder`. Unlike [reorderDays],
  /// `dbo.SplitDayExercises.SortOrder` carries no uniqueness constraint, so
  /// this can just write each changed slot directly in list order with no
  /// risk of a mid-reorder collision.
  Future<bool> reorderDayExercises(
    String splitDayId,
    List<String> orderedSplitDayExerciseIds,
  ) =>
      _run(() async {
        final day = (detail?.days ?? const <SplitDayWithExercises>[])
            .firstWhere((d) => d.day.splitDayId == splitDayId);
        final byId = {
          for (final e in day.exercises) e.splitDayExerciseId: e,
        };
        for (var i = 0; i < orderedSplitDayExerciseIds.length; i++) {
          final exercise = byId[orderedSplitDayExerciseIds[i]]!;
          if (exercise.sortOrder == i) continue;
          await _repository.saveDayExercise(
            splitDayExerciseId: exercise.splitDayExerciseId,
            splitDayId: splitDayId,
            exerciseId: exercise.exerciseId,
            sortOrder: i,
            targetSets: exercise.targetSets,
            targetRepsLow: exercise.targetRepsLow,
            targetRepsHigh: exercise.targetRepsHigh,
          );
        }
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
