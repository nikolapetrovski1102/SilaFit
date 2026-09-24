import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/features/exercises/exercise_focus.dart';

void main() {
  group('muscleGroupsInText', () {
    test('folds finer muscle words onto the coarse catalogue groups', () {
      expect(muscleGroupsInText('Triceps'), ['arms']);
      expect(muscleGroupsInText('Delts & Traps'), ['back', 'shoulders']);
      expect(muscleGroupsInText('Quads, Hamstrings and Calves'), ['legs']);
      expect(muscleGroupsInText('Abs'), ['core']);
    });

    test('reads a multi-muscle title as several groups in catalogue order', () {
      expect(
        muscleGroupsInText('Push A: Chest, Delts & Triceps'),
        ['chest', 'shoulders', 'arms'],
      );
    });

    test('does not match a keyword inside a longer word', () {
      // "warm up" must not read as "arm"; "backpack" must not read as "back".
      expect(muscleGroupsInText('Warm up and mobility'), isEmpty);
      expect(muscleGroupsInText('Backpack carry'), isEmpty);
    });

    test('session-shape words are not muscles', () {
      expect(muscleGroupsInText('Push'), isEmpty);
      expect(muscleGroupsInText('Upper / Lower'), isEmpty);
      expect(muscleGroupsInText('Full body'), isEmpty);
      expect(muscleGroupsInText('Day 1'), isEmpty);
    });
  });

  group('resolveExerciseFocus', () {
    test('title intent leads and is reported as fromTitle', () {
      final focus = resolveExerciseFocus(title: 'Arms Day');

      expect(focus.muscleGroups, ['arms']);
      expect(focus.fromTitle, isTrue);
      expect(focus.isEmpty, isFalse);
    });

    test('generic title blends in the sequence of added exercises', () {
      final focus = resolveExerciseFocus(
        title: 'Push',
        existingExerciseGroups: const ['arms', 'chest'],
      );

      // No title muscles, so the sequence order is preserved as supplied.
      expect(focus.muscleGroups, ['arms', 'chest']);
      expect(focus.fromTitle, isFalse);
    });

    test('explicit title muscles come before sequence muscles, deduped', () {
      final focus = resolveExerciseFocus(
        title: 'Chest & Triceps',
        existingExerciseGroups: const ['arms', 'back'],
      );

      expect(focus.muscleGroups, ['chest', 'arms', 'back']);
      expect(focus.fromTitle, isTrue);
    });

    test('no title and no added exercises means the generic fallback', () {
      final focus = resolveExerciseFocus(title: 'Push', focus: 'Day 1');

      expect(focus.isEmpty, isTrue);
      expect(focus, isA<ExerciseFocus>());
    });

    test('focus label is considered alongside the title', () {
      final focus =
          resolveExerciseFocus(title: 'Day 1', focus: 'Chest/Triceps');

      expect(focus.muscleGroups, ['chest', 'arms']);
      expect(focus.fromTitle, isTrue);
    });
  });
}
