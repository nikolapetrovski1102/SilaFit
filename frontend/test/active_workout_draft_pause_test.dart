import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/features/today/active_workout_draft_store.dart';

ActiveWorkoutDraft _draft({DateTime? pausedAtUtc}) => ActiveWorkoutDraft(
      workoutSessionId: 's1',
      exerciseIndex: 0,
      setsByExercise: const [],
      exercises: const [],
      startedAtUtc: DateTime.utc(2026, 1, 1, 10),
      savedAtUtc: DateTime.utc(2026, 1, 1, 10, 20),
      pausedAtUtc: pausedAtUtc,
    );

void main() {
  test('time spent away from a paused workout is not counted', () {
    // 20 min trained, left at 10:20, resumed at 10:50.
    final draft = _draft(pausedAtUtc: DateTime.utc(2026, 1, 1, 10, 20));
    final now = DateTime.utc(2026, 1, 1, 10, 50);
    final resumed = draft.resumedStartedAtUtc(now);
    expect(now.difference(resumed), const Duration(minutes: 20));
  });

  test('a never-paused draft keeps its original start', () {
    final draft = _draft();
    expect(draft.resumedStartedAtUtc(DateTime.utc(2026, 1, 1, 11)),
        DateTime.utc(2026, 1, 1, 10));
  });

  test('pausedAtUtc survives a JSON round-trip and stays optional', () {
    final paused = _draft(pausedAtUtc: DateTime.utc(2026, 1, 1, 10, 20));
    expect(ActiveWorkoutDraft.fromJson(paused.toJson()).pausedAtUtc,
        DateTime.utc(2026, 1, 1, 10, 20));
    expect(ActiveWorkoutDraft.fromJson(_draft().toJson()).pausedAtUtc, isNull);
  });
}
