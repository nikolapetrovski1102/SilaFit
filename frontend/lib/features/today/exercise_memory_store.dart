import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The weight/reps last logged for one exercise, regardless of which
/// session it happened in.
class ExerciseMemory {
  final double weightKg;
  final int reps;

  const ExerciseMemory({required this.weightKg, required this.reps});

  Map<String, dynamic> toJson() => {'weightKg': weightKg, 'reps': reps};

  factory ExerciseMemory.fromJson(Map<String, dynamic> json) => ExerciseMemory(
        weightKg: (json['weightKg'] as num).toDouble(),
        reps: json['reps'] as int,
      );
}

/// On-device, per-exercise "what did I last do here" memory - keyed by
/// exerciseId, with no freshness window (unlike [ActiveWorkoutDraftStore]'s
/// 2-3h in-progress-workout draft): last week's working weight for an
/// exercise is still exactly what next week's fresh set list should start
/// from, so `ActiveWorkoutTrackerScreen._init` seeds new (non-restored) sets
/// from here instead of always resetting to the barbell standard or the
/// target rep-range midpoint.
class ExerciseMemoryStore {
  ExerciseMemoryStore._();

  static final instance = ExerciseMemoryStore._();

  static const _key = 'silen.exercise_memory';

  Future<Map<String, ExerciseMemory>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((exerciseId, value) => MapEntry(
          exerciseId, ExerciseMemory.fromJson(value as Map<String, dynamic>)));
    } catch (_) {
      // Corrupt/incompatible payload from a future app version - treat as
      // no memory rather than crashing the workout screen over it.
      return {};
    }
  }

  /// Every remembered exercise at once, for seeding a whole fresh set table
  /// in a single storage round-trip rather than one read per exercise.
  Future<Map<String, ExerciseMemory>> loadAll() => _loadAll();

  Future<void> remember(String exerciseId, double weightKg, int reps) async {
    final all = await _loadAll();
    all[exerciseId] = ExerciseMemory(weightKg: weightKg, reps: reps);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(all.map((id, memory) => MapEntry(id, memory.toJson()))));
  }

  /// Drops every remembered exercise. Called on sign-out so the outgoing
  /// user's weights never seed the next account/guest's fresh set table.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
