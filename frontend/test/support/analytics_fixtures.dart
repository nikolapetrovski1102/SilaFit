import 'package:silafit/features/progress/analytics_models.dart';

MonthlyAnalytics monthlyAnalyticsFixture() {
  const summary = MonthlyAnalyticsSummary(
    completedSessions: 20,
    scheduledSessions: 22,
    totalTonnageKg: 42000,
    avgRpe: 7.5,
    currentStreakDays: 8,
    weeklyCompliancePercent: 91,
    startWeightKg: 84.5,
    endWeightKg: 82.9,
    loggedMealDays: 24,
    totalDaysInRange: 30,
  );

  return MonthlyAnalytics(
    missedWorkoutDays: 2,
    daysOverCalorieTarget: 3,
    totalCaloriesOverTarget: 740,
    calorieTarget: 2400,
    exercises: [
      MonthlyExercise(
        exerciseId: 'incline',
        exerciseName: 'Incline dumbbell bench press',
        recordWeightKg: 40,
        points: [
          for (var i = 0; i < 4; i++)
            MonthlyExercisePoint(
              dateUtc: DateTime.utc(2026, 8, 3 + i * 7),
              weightKg: [20.0, 22.5, 25.0, 25.0][i],
              reps: 10,
              sessionRpe: 7 + i * .3,
            ),
        ],
      ),
      MonthlyExercise(
        exerciseId: 'row',
        exerciseName: 'Dumbbell row',
        recordWeightKg: 40,
        points: [
          for (var i = 0; i < 4; i++)
            MonthlyExercisePoint(
              dateUtc: DateTime.utc(2026, 8, 2 + i * 7),
              weightKg: 25,
              reps: 10,
              sessionRpe: 7,
            ),
        ],
      ),
    ],
    year: 2026,
    month: 8,
    summary: summary,
    strengths: const [
      'You completed 20 of 22 scheduled workouts.',
      'Your current streak is 8 days.',
      'You logged meals on 24 of 30 days.',
    ],
    improvements: const [
      AnalyticsImprovement(
        area: 'Leg Day Consistency',
        recommendation: 'Move leg sessions earlier in the week.',
        priority: 'High',
      ),
      AnalyticsImprovement(
        area: 'Recovery Between Sessions',
        recommendation: 'Space heavy compound days out.',
        priority: 'Medium',
      ),
    ],
    focusForNextMonth: 'Keep progressing your compound lifts.',
    generatedAtUtc: DateTime.utc(2026, 9, 1),
  );
}

WeeklyAnalytics weeklyAnalyticsFixture() {
  final monthly = monthlyAnalyticsFixture();
  return WeeklyAnalytics(
    exercises: monthly.exercises,
    missedWorkoutDays: 1,
    daysOverCalorieTarget: 1,
    totalCaloriesOverTarget: monthly.totalCaloriesOverTarget,
    calorieTarget: monthly.calorieTarget,
    year: 2026,
    weekNumber: 37,
    weekStartUtc: DateTime.utc(2026, 9, 7),
    weekEndUtc: DateTime.utc(2026, 9, 13),
    summary: monthly.summary,
    strengths: monthly.strengths.take(2).toList(),
    improvements: monthly.improvements,
    focusForNextWeek: monthly.focusForNextMonth,
    generatedAtUtc: DateTime.utc(2026, 9, 13, 12),
  );
}
