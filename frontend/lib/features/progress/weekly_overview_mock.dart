import '../meals/meal_models.dart';
import '../splits/splits_models.dart';
import 'analytics_models.dart';
import 'monthly_overview_mock.dart';

/// On-device mocks for the dev-only weekly recap preview (see the Settings
/// developer section). Mirrors `monthly_overview_mock.dart`: nothing here
/// touches the network, so the weekly slides - including the meal/split
/// recommendation slides - can be previewed before a week of real history
/// exists.
WeeklyAnalytics buildSimulatedWeeklyAnalytics() {
  final base = buildSimulatedMonthlyAnalytics();
  final now = DateTime.now();
  final weekStart = DateTime.utc(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  final weekEnd = weekStart.add(const Duration(days: 6));

  return WeeklyAnalytics(
    exercises: base.exercises,
    // A week holds ~a quarter of a month's activity, so scale the monthly
    // mock numbers down rather than claiming a full month's worth.
    missedWorkoutDays: base.missedWorkoutDays == null
        ? null
        : (base.missedWorkoutDays! / 4).round(),
    daysOverCalorieTarget: base.daysOverCalorieTarget == null ? null : 1,
    totalCaloriesOverTarget: base.totalCaloriesOverTarget,
    calorieTarget: base.calorieTarget,
    year: weekStart.year,
    weekNumber: _isoWeekNumber(weekStart),
    weekStartUtc: weekStart,
    weekEndUtc: weekEnd,
    summary: base.summary,
    strengths: base.strengths.take(2).toList(),
    improvements: base.improvements.take(2).toList(),
    focusForNextWeek: base.focusForNextMonth,
    generatedAtUtc: DateTime.now().toUtc(),
  );
}

List<MealSuggestion> simulatedMealSuggestions() => const [
      MealSuggestion(
        mealSuggestionId: 'preview-meal-chicken',
        title: 'Grilled chicken & rice bowl',
        mealType: 'Lunch',
        description:
            'Lean protein with slow carbs - an easy post-training lunch.',
        caloriesKcal: 620,
        proteinG: 48,
        carbsG: 62,
        fatsG: 18,
        ingredientPreview: 'Chicken breast · brown rice · broccoli · olive oil',
        ingredientCount: 6,
        matchScore: 94,
        matchReason: 'High protein · fits your lunch calorie target',
      ),
      MealSuggestion(
        mealSuggestionId: 'preview-meal-oats',
        title: 'Protein oats with berries',
        mealType: 'Breakfast',
        description:
            'Quick breakfast that keeps protein high without a heavy start.',
        caloriesKcal: 430,
        proteinG: 32,
        carbsG: 54,
        fatsG: 10,
        ingredientPreview: 'Rolled oats · whey protein · berries · milk',
        ingredientCount: 4,
        matchScore: 89,
        matchReason: 'Balanced macros · matches your breakfast window',
      ),
      MealSuggestion(
        mealSuggestionId: 'preview-meal-salmon',
        title: 'Baked salmon & greens',
        mealType: 'Dinner',
        description:
            'Omega-3 rich dinner that stays inside your evening budget.',
        caloriesKcal: 540,
        proteinG: 42,
        carbsG: 24,
        fatsG: 28,
        ingredientPreview: 'Salmon · spinach · asparagus · lemon',
        ingredientCount: 5,
        matchScore: 86,
        matchReason: 'Protein-forward · keeps dinner under target',
      ),
    ];

WorkoutSplit simulatedRecommendedSplit() => const WorkoutSplit(
      splitId: 'preview-split-ppl',
      name: 'Push · Pull · Legs',
      category: 'PushPullLegs',
      level: 'Intermediate',
      durationDays: 6,
      description:
          'Six-day rotation balancing pressing, pulling, and lower body.',
      isSystemDefault: true,
      recommendedGoal: 'BuildMuscle',
      matchesGoal: true,
      matchScore: 92,
      matchReason: 'Matched to your Build Muscle goal · Intermediate · 6 days',
    );

/// ISO-8601 week number - Dart's DateTime has no built-in, and the preview
/// only needs a plausible label.
int _isoWeekNumber(DateTime date) {
  final thursday = date.add(Duration(days: 4 - date.weekday));
  final firstThursday = DateTime.utc(thursday.year, 1, 1).add(
      Duration(days: (4 - DateTime.utc(thursday.year, 1, 1).weekday + 7) % 7));
  return ((thursday.difference(firstThursday).inDays) / 7).floor() + 1;
}
