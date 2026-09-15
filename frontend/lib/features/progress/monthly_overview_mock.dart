import 'dart:math';

import 'analytics_models.dart';

/// Builds a realistic-looking [MonthlyAnalytics] entirely on-device, no
/// backend call involved - used only by the dev-only "Simulate monthly
/// overview" action in Settings (see `_SimulateMonthlyOverviewButton` there)
/// so [MonthlyOverviewScreen] can be previewed instantly, without seeding a
/// real month of history first (see `Silen.Tools.SeedMockData` for that
/// heavier, real-database path). Re-randomized on every call, so tapping the
/// dev button twice in a row shows two different (but always plausible)
/// recaps rather than the exact same numbers/copy each time.
MonthlyAnalytics buildSimulatedMonthlyAnalytics() {
  final random = Random();
  final now = DateTime.now();
  // A monthly overview always looks back at a month that's already over.
  final reportMonth = DateTime(now.year, now.month - 1, 1);

  final scheduledSessions = 22 + random.nextInt(4); // 22-25
  final completedSessions =
      (scheduledSessions - random.nextInt(4)).clamp(14, scheduledSessions);
  final completionRatio = completedSessions / scheduledSessions;

  final totalTonnageKg = (32000 + random.nextInt(18000)).toDouble();
  final avgRpe =
      double.parse((7.0 + random.nextDouble() * 1.6).toStringAsFixed(1));
  final currentStreakDays = 4 + random.nextInt(11); // 4-14
  final weeklyCompliancePercent =
      (completionRatio * 100).round().clamp(45, 100);

  final losingFat = random.nextBool();
  final startWeightKg = losingFat ? 84.5 : 74.2;
  final weightDelta = losingFat
      ? -(1.2 + random.nextDouble() * 1.8)
      : (0.8 + random.nextDouble() * 1.4);
  final endWeightKg =
      double.parse((startWeightKg + weightDelta).toStringAsFixed(1));

  final loggedMealDays = 20 + random.nextInt(9); // 20-28
  const totalDaysInRange = 30;

  final summary = MonthlyAnalyticsSummary(
    completedSessions: completedSessions,
    scheduledSessions: scheduledSessions,
    totalTonnageKg: totalTonnageKg,
    avgRpe: avgRpe,
    currentStreakDays: currentStreakDays,
    weeklyCompliancePercent: weeklyCompliancePercent,
    startWeightKg: startWeightKg,
    endWeightKg: endWeightKg,
    loggedMealDays: loggedMealDays,
    totalDaysInRange: totalDaysInRange,
  );

  final strengths = [
    'You completed $completedSessions of $scheduledSessions scheduled workouts - ${(completionRatio * 100).round()}% adherence.',
    'Current streak sits at $currentStreakDays day${currentStreakDays == 1 ? '' : 's'}, the longest active run this month.',
    'Logged meals on $loggedMealDays of $totalDaysInRange days, keeping nutrition tracking consistent.',
    'Total tonnage lifted crossed ${(totalTonnageKg / 1000).toStringAsFixed(1)}t across every completed session.',
  ]..shuffle(random);

  final improvementPool = [
    const AnalyticsImprovement(
      area: 'Leg Day Consistency',
      recommendation:
          'Leg sessions were skipped most often - try moving them earlier in the week, before energy dips.',
      priority: 'High',
    ),
    const AnalyticsImprovement(
      area: 'Recovery Between Sessions',
      recommendation:
          'A couple of sessions landed back-to-back with under 24h rest - spacing heavy compound days out could bring RPE down.',
      priority: 'Medium',
    ),
    const AnalyticsImprovement(
      area: 'Protein Consistency',
      recommendation:
          'Protein intake dipped on non-training days - keeping it steady even on rest days supports recovery.',
      priority: 'Low',
    ),
    const AnalyticsImprovement(
      area: 'Session Timing',
      recommendation:
          'Workouts logged late in the evening tended to run shorter - an earlier slot may let you push full volume.',
      priority: 'Medium',
    ),
  ]..shuffle(random);

  const focusOptions = [
    'Keep pushing progressive overload on your compound lifts while adding one more leg session per week to close the gap with upper-body volume.',
    'Lock in a consistent bedtime on training days - recovery is the one lever that will move every other number this month.',
    'Nutrition logging is solid; the next win is tightening protein intake on rest days to match training-day totals.',
  ];

  return MonthlyAnalytics(
    missedWorkoutDays: scheduledSessions - completedSessions,
    daysOverCalorieTarget: 3,
    totalCaloriesOverTarget: 740,
    calorieTarget: 2400,
    exercises: [
      MonthlyExercise(
          exerciseId: 'preview-incline',
          exerciseName: 'Incline dumbbell bench press',
          recordWeightKg: 40,
          points: [
            for (var i = 0; i < 4; i++)
              MonthlyExercisePoint(
                  dateUtc: DateTime.utc(
                      reportMonth.year, reportMonth.month, 3 + i * 7),
                  weightKg: [20.0, 22.5, 25.0, 25.0][i],
                  reps: 10,
                  sessionRpe: 7 + i * .3)
          ]),
      MonthlyExercise(
          exerciseId: 'preview-row',
          exerciseName: 'Dumbbell row',
          recordWeightKg: 40,
          points: [
            for (var i = 0; i < 4; i++)
              MonthlyExercisePoint(
                  dateUtc: DateTime.utc(
                      reportMonth.year, reportMonth.month, 2 + i * 7),
                  weightKg: 25,
                  reps: 10,
                  sessionRpe: 7)
          ]),
    ],
    year: reportMonth.year,
    month: reportMonth.month,
    summary: summary,
    strengths: strengths.take(3).toList(),
    improvements: improvementPool.take(2).toList(),
    focusForNextMonth: focusOptions[random.nextInt(focusOptions.length)],
    generatedAtUtc: DateTime.now().toUtc(),
  );
}
