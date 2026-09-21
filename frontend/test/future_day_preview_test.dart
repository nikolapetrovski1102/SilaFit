import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/features/splits/splits_models.dart';
import 'package:silafit/features/today/today_models.dart';
import 'package:silafit/features/today/widgets/day_preview.dart';

void main() {
  group('future day preview', () {
    test('resolves the future split day and its exercises', () {
      final today = dateOnly(DateTime.now());
      final split = ActiveSplit(
        splitId: 'split-1',
        durationDays: 2,
        activatedAtUtc: today,
      );
      final detail = _splitDetail([
        _day(index: 1, title: 'Push', exercise: 'Bench press'),
        _day(index: 2, title: 'Pull', exercise: 'Barbell row'),
      ]);

      final preview = DayPreview.resolve(
        date: today.add(const Duration(days: 1)),
        dashboard: _dashboard(split),
        splitDetail: detail,
      );

      expect(preview.isToday, isFalse);
      expect(preview.title, 'Pull');
      expect(preview.estimatedMinutes, 45);
      expect(preview.scheduledExercises, hasLength(1));
      expect(preview.scheduledExercises.single.name, 'Barbell row');
    });

    test('keeps future rest days as rest previews', () {
      final today = dateOnly(DateTime.now());
      final split = ActiveSplit(
        splitId: 'split-1',
        durationDays: 2,
        activatedAtUtc: today,
      );
      final detail = _splitDetail([
        _day(index: 0, title: 'Push', exercise: 'Bench press'),
        _day(index: 1, title: 'Recovery', isRestDay: true),
      ]);

      final preview = DayPreview.resolve(
        date: today.add(const Duration(days: 1)),
        dashboard: _dashboard(split),
        splitDetail: detail,
      );

      expect(preview.isRestDay, isTrue);
      expect(preview.title, 'Recovery');
      expect(preview.scheduledExercises, isEmpty);
    });

    test('uses ordinal order for splits with one-based day indexes', () {
      final today = dateOnly(DateTime.now());
      final split = ActiveSplit(
        splitId: 'split-1',
        durationDays: 2,
        activatedAtUtc: today,
      );
      final detail = _splitDetail([
        _day(index: 2, title: 'Second'),
        _day(index: 1, title: 'First'),
      ]);

      expect(resolveSplitDay(today, split, detail)?.title, 'First');
      expect(
        resolveSplitDay(today.add(const Duration(days: 1)), split, detail)
            ?.title,
        'Second',
      );
    });
  });
}

TodayDashboard _dashboard(ActiveSplit split) => TodayDashboard(
      session: const TodaySession(status: 'Scheduled', isRestDay: false),
      targetExercises: const [],
      hydrationTotalMl: 0,
      hydrationTargetMl: 2000,
      currentStreakDays: 0,
      weeklyCompliancePercent: 0,
      weekStatuses: const [],
      activeSplit: split,
    );

SplitDetail _splitDetail(List<SplitDayWithExercises> days) => SplitDetail(
      split: const WorkoutSplit(
        splitId: 'split-1',
        name: 'Test split',
        category: 'Strength',
        level: 'Beginner',
        durationDays: 2,
        isSystemDefault: false,
      ),
      days: days,
    );

SplitDayWithExercises _day({
  required int index,
  required String title,
  String? exercise,
  bool isRestDay = false,
}) =>
    SplitDayWithExercises(
      day: SplitDay(
        splitDayId: 'day-$index',
        dayIndex: index,
        title: title,
        estimatedMinutes: 45,
        isRestDay: isRestDay,
      ),
      exercises: exercise == null
          ? const []
          : [
              SplitDayExercise(
                splitDayExerciseId: 'slot-$index',
                exerciseId: 'exercise-$index',
                name: exercise,
                sortOrder: 0,
                targetSets: 3,
                targetRepsLow: 8,
                targetRepsHigh: 12,
              ),
            ],
    );
