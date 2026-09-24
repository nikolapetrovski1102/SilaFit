import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/features/splits/splits_models.dart';
import 'package:silafit/core/widgets/container_transform.dart';
import 'package:silafit/features/today/today_models.dart';
import 'package:silafit/features/today/widgets/overview_card.dart';
import 'package:silafit/features/today/workout_preview_screen.dart';
import 'package:silafit/features/today/widgets/day_preview.dart';

void main() {
  group('future day preview', () {
    test('resolves the future split day and its exercises', () {
      final monday = _upcomingMonday();
      final split = ActiveSplit(
        splitId: 'split-1',
        durationDays: 2,
        activatedAtUtc: monday,
      );
      final detail = _splitDetail([
        _day(index: 1, title: 'Push', exercise: 'Bench press'),
        _day(index: 2, title: 'Pull', exercise: 'Barbell row'),
      ]);

      final preview = DayPreview.resolve(
        date: monday.add(const Duration(days: 1)),
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
      final monday = _upcomingMonday();
      final split = ActiveSplit(
        splitId: 'split-1',
        durationDays: 2,
        activatedAtUtc: monday,
      );
      final detail = _splitDetail([
        _day(index: 1, title: 'Push', exercise: 'Bench press'),
        _day(index: 2, title: 'Recovery', isRestDay: true),
      ]);

      final preview = DayPreview.resolve(
        date: monday.add(const Duration(days: 1)),
        dashboard: _dashboard(split),
        splitDetail: detail,
      );

      expect(preview.isRestDay, isTrue);
      expect(preview.title, 'Recovery');
      expect(preview.scheduledExercises, isEmpty);
    });

    test('treats rotation slots with no authored day as rest days', () {
      // A 7-day split with only 5 days built: the other 2 slots in the
      // rotation rest by default, same as the backend leaving that day's
      // session unset when it has no split day to point at.
      final monday = _upcomingMonday();
      final split = ActiveSplit(
        splitId: 'split-1',
        durationDays: 7,
        activatedAtUtc: monday,
      );
      final detail = SplitDetail(
        split: const WorkoutSplit(
          splitId: 'split-1',
          name: 'Five-day split',
          category: 'Strength',
          level: 'Beginner',
          durationDays: 7,
          isSystemDefault: false,
        ),
        days: [
          for (var i = 1; i <= 5; i++)
            _day(index: i, title: 'Day $i', exercise: 'Exercise $i'),
        ],
      );

      for (final offset in [5, 6]) {
        final preview = DayPreview.resolve(
          date: monday.add(Duration(days: offset)),
          dashboard: _dashboard(split),
          splitDetail: detail,
        );
        expect(preview.isRestDay, isTrue, reason: 'offset $offset');
        expect(preview.scheduledExercises, isEmpty, reason: 'offset $offset');
      }

      // And the cycle keeps repeating indefinitely - day 7 of the next lap
      // lands back on the first authored day rather than running out.
      final nextLap = DayPreview.resolve(
        date: monday.add(const Duration(days: 7)),
        dashboard: _dashboard(split),
        splitDetail: detail,
      );
      expect(nextLap.isRestDay, isFalse);
      expect(nextLap.title, 'Day 1');
    });

    test('rests on gaps in the day numbering', () {
      // Day 1, Day 2, Day 4 - Day 3 was never built, so Wednesday rests and
      // Day 4 stays on Thursday instead of sliding forward.
      final monday = _upcomingMonday();
      final split = ActiveSplit(
        splitId: 'split-1',
        durationDays: 3,
        activatedAtUtc: monday,
      );
      final detail = _splitDetail([
        _day(index: 1, title: 'Push'),
        _day(index: 2, title: 'Pull'),
        _day(index: 4, title: 'Legs'),
      ]);

      String? titleOn(int offset) =>
          resolveSplitDay(monday.add(Duration(days: offset)), split, detail)
              ?.title;
      bool? restOn(int offset) =>
          resolveSplitDay(monday.add(Duration(days: offset)), split, detail)
              ?.isRestDay;

      expect(titleOn(0), 'Push');
      expect(titleOn(1), 'Pull');
      expect(restOn(2), isTrue);
      expect(titleOn(3), 'Legs');
      for (final offset in [4, 5, 6]) {
        expect(restOn(offset), isTrue, reason: 'offset $offset');
      }
    });

    test('starts Day 1 on every Monday, whatever the split length', () {
      // A 4-day split rotates weekly rather than every 4 days, so Friday
      // rests and the next Monday is Day 1 again.
      final monday = _upcomingMonday();
      final split = ActiveSplit(
        splitId: 'split-1',
        durationDays: 4,
        activatedAtUtc: monday,
      );
      final detail = _splitDetail([
        for (var i = 1; i <= 4; i++) _day(index: i, title: 'Day $i'),
      ]);

      expect(
          resolveSplitDay(monday.add(const Duration(days: 4)), split, detail)
              ?.isRestDay,
          isTrue);
      for (final week in [1, 2, 5]) {
        expect(
          // Calendar arithmetic, not Duration: week 5 can cross a DST change.
          resolveSplitDay(
                  DateTime(monday.year, monday.month, monday.day + 7 * week),
                  split,
                  detail)
              ?.title,
          'Day 1',
          reason: 'week $week',
        );
      }
    });

    test('orders days by their index', () {
      final monday = _upcomingMonday();
      final split = ActiveSplit(
        splitId: 'split-1',
        durationDays: 2,
        activatedAtUtc: monday,
      );
      final detail = _splitDetail([
        _day(index: 2, title: 'Second'),
        _day(index: 1, title: 'First'),
      ]);

      expect(resolveSplitDay(monday, split, detail)?.title, 'First');
      expect(
        resolveSplitDay(monday.add(const Duration(days: 1)), split, detail)
            ?.title,
        'Second',
      );
    });

    test('anchors the rotation to the Monday of the activation week', () {
      // Activated on a Wednesday: the first day still belongs to that week's
      // Monday, so Wednesday resolves to the third day, not the first.
      final monday = _upcomingMonday();
      final wednesday = monday.add(const Duration(days: 2));
      final split = ActiveSplit(
        splitId: 'split-1',
        durationDays: 7,
        activatedAtUtc: wednesday,
      );
      final detail = _splitDetail([
        for (var i = 1; i <= 7; i++) _day(index: i, title: 'Day $i'),
      ]);

      expect(resolveSplitDay(wednesday, split, detail)?.title, 'Day 3');
      expect(
        resolveSplitDay(monday.add(const Duration(days: 7)), split, detail)
            ?.title,
        'Day 1',
      );
    });

    testWidgets('opens the complete workout from the future-day button',
        (tester) async {
      final monday = _upcomingMonday();
      final futureDate = monday.add(const Duration(days: 1));
      final split = ActiveSplit(
        splitId: 'split-1',
        name: 'Strength rotation',
        durationDays: 2,
        activatedAtUtc: monday,
      );
      final detail = _splitDetail([
        _day(index: 1, title: 'Push'),
        const SplitDayWithExercises(
          day: SplitDay(
            splitDayId: 'day-2',
            dayIndex: 2,
            title: 'Pull strength',
            focusLabel: 'Back and biceps',
            estimatedMinutes: 55,
            isRestDay: false,
          ),
          exercises: [
            SplitDayExercise(
              splitDayExerciseId: 'slot-1',
              exerciseId: 'row',
              name: 'Barbell row',
              muscleGroup: 'Back',
              sortOrder: 0,
              targetSets: 4,
              targetRepsLow: 6,
              targetRepsHigh: 8,
            ),
            SplitDayExercise(
              splitDayExerciseId: 'slot-2',
              exerciseId: 'curl',
              name: 'Hammer curl',
              muscleGroup: 'Biceps',
              sortOrder: 1,
              targetSets: 3,
              targetRepsLow: 10,
              targetRepsHigh: 12,
            ),
          ],
        ),
      ]);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TodayOverviewCard(
              dashboard: _dashboard(split),
              splitDetail: detail,
              selectedDate: futureDate,
              selectedKnownStatus: null,
              onDaySelected: (_) {},
              workoutBuilder: (_) => const SizedBox.shrink(),
              onWorkoutClosed: () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('View full workout'), findsOneWidget);
      expect(find.text('Barbell row'), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(ContainerTransform), findsNothing);

      await tester.tap(find.text('View full workout'));
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutPreviewScreen), findsOneWidget);
      expect(find.text('Workout Preview'), findsOneWidget);
      expect(find.text('Pull strength'), findsOneWidget);
      expect(find.text('From Strength rotation'), findsOneWidget);
      expect(find.text('Barbell row'), findsOneWidget);
      expect(find.text('Hammer curl'), findsOneWidget);
      expect(find.text('7 total sets'), findsOneWidget);
    });
  });
}

/// A Monday strictly after today, so every date the tests resolve is a
/// future day and the split's rotation starts exactly on it.
DateTime _upcomingMonday() {
  final today = dateOnly(DateTime.now());
  return today.add(Duration(days: 8 - today.weekday));
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
