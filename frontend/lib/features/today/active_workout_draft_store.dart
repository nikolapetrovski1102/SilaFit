import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'today_models.dart';

/// One logged (or in-progress) set inside a persisted [ActiveWorkoutDraft] -
/// the storage counterpart of `_SetDraft` in `active_workout_tracker_screen.dart`.
class DraftSet {
  final double weightKg;
  final int reps;
  final bool completed;

  const DraftSet({
    required this.weightKg,
    required this.reps,
    required this.completed,
  });

  Map<String, dynamic> toJson() =>
      {'weightKg': weightKg, 'reps': reps, 'completed': completed};

  factory DraftSet.fromJson(Map<String, dynamic> json) => DraftSet(
        weightKg: (json['weightKg'] as num).toDouble(),
        reps: json['reps'] as int,
        completed: json['completed'] as bool? ?? false,
      );
}

/// A snapshot of an in-progress `ActiveWorkoutTrackerScreen`, persisted to
/// device storage so the workout survives the app being backgrounded,
/// killed, or the phone locked mid-session - without ever touching the
/// backend, which (per `_SetDraft`'s doc there) has no set-by-set logging
/// endpoint of its own. Scoped to the one [workoutSessionId] it was saved
/// for; [ActiveWorkoutDraftStore] is the only thing that decides whether a
/// given draft is still fresh enough to hand back.
class ActiveWorkoutDraft {
  final String workoutSessionId;
  final int exerciseIndex;
  final List<List<DraftSet>> setsByExercise;
  // Full exercise data, one per `setsByExercise` slot - not just an id. The
  // live-workout swap/add feature can change this list away from whatever
  // `TodayDashboard.targetExercises` originally prescribed, so resuming from
  // a killed app has to rebuild `_exercises` from here rather than from the
  // (now stale) split-day plan; carrying the full record avoids needing a
  // by-id refetch endpoint that doesn't exist.
  final List<TargetExercise> exercises;
  final DateTime startedAtUtc;
  final DateTime savedAtUtc;

  const ActiveWorkoutDraft({
    required this.workoutSessionId,
    required this.exerciseIndex,
    required this.setsByExercise,
    required this.exercises,
    required this.startedAtUtc,
    required this.savedAtUtc,
  });

  /// Completed sets over total sets, across every exercise - what Home's
  /// session-card ring shows for "Continue Workout" instead of the flat 0
  /// it shows before a workout has started. 0 for an edge-case empty plan
  /// rather than dividing by zero.
  double get completionRatio {
    var total = 0;
    var completed = 0;
    for (final sets in setsByExercise) {
      total += sets.length;
      completed += sets.where((s) => s.completed).length;
    }
    return total == 0 ? 0 : completed / total;
  }

  Map<String, dynamic> toJson() => {
        'workoutSessionId': workoutSessionId,
        'exerciseIndex': exerciseIndex,
        'setsByExercise': setsByExercise
            .map((sets) => sets.map((s) => s.toJson()).toList())
            .toList(),
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'startedAtUtc': startedAtUtc.toIso8601String(),
        'savedAtUtc': savedAtUtc.toIso8601String(),
      };

  factory ActiveWorkoutDraft.fromJson(Map<String, dynamic> json) =>
      ActiveWorkoutDraft(
        workoutSessionId: json['workoutSessionId'] as String,
        exerciseIndex: json['exerciseIndex'] as int? ?? 0,
        setsByExercise: (json['setsByExercise'] as List<dynamic>)
            .map((sets) => (sets as List<dynamic>)
                .map((s) => DraftSet.fromJson(s as Map<String, dynamic>))
                .toList())
            .toList(),
        // Missing on a draft saved before the swap/add feature landed - an
        // empty list here always fails the shape check against
        // `setsByExercise` in `ActiveWorkoutTrackerScreen._init`, so a
        // pre-upgrade draft is correctly treated as stale rather than
        // resumed with no exercise data.
        exercises: (json['exercises'] as List<dynamic>?)
                ?.map((e) => TargetExercise.fromJson(e))
                .toList() ??
            const [],
        startedAtUtc: DateTime.parse(json['startedAtUtc'] as String),
        savedAtUtc: DateTime.parse(json['savedAtUtc'] as String),
      );
}

/// Persists exactly one [ActiveWorkoutDraft] at a time - the app only ever
/// has one workout in progress, matching the one-`ActiveWorkoutTrackerScreen`
/// convention. `TodayScreen` calls [hasFreshDraftFor] to decide "Start
/// Workout" vs "Continue Workout" on Home; `ActiveWorkoutTrackerScreen`
/// itself reads/writes the full draft via [load]/[save]/[clear].
///
/// Persisted the same way `SessionStore` persists everything else - plain
/// `shared_preferences`, one JSON-encoded string - rather than adding a
/// second local-storage mechanism to the app.
class ActiveWorkoutDraftStore {
  ActiveWorkoutDraftStore._();
  static final instance = ActiveWorkoutDraftStore._();

  static const _key = 'silen.active_workout_draft';

  /// A draft older than this is treated as gone rather than resumed, and is
  /// physically deleted on the next [load]/[hasFreshDraftFor] call. Three
  /// hours comfortably covers a real session plus a stretched rest or an
  /// interruption mid-gym, while still guaranteeing a set logged this long
  /// ago - almost certainly an abandoned session, not this one - never
  /// silently reappears hours later as "Continue Workout".
  static const maxAge = Duration(hours: 3);

  /// Returns the saved draft only if it belongs to [workoutSessionId] and is
  /// still within [maxAge]; otherwise deletes whatever was stored (a stale
  /// or mismatched draft is never worth keeping around) and returns null.
  Future<ActiveWorkoutDraft?> load(String workoutSessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;

    ActiveWorkoutDraft draft;
    try {
      draft = ActiveWorkoutDraft.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await prefs.remove(_key);
      return null;
    }

    final isFresh =
        DateTime.now().toUtc().difference(draft.savedAtUtc) <= maxAge;
    if (draft.workoutSessionId != workoutSessionId || !isFresh) {
      await prefs.remove(_key);
      return null;
    }
    return draft;
  }

  /// Cheap existence check for Home's "Continue Workout" affordance - same
  /// freshness/session-match rules as [load], without the caller needing to
  /// unpack the full draft.
  Future<bool> hasFreshDraftFor(String workoutSessionId) async =>
      (await load(workoutSessionId)) != null;

  Future<void> save(ActiveWorkoutDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(draft.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
