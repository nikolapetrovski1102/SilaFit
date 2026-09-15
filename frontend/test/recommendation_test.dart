import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/features/meals/meal_models.dart';
import 'package:silafit/features/meals/meal_recommendation.dart';
import 'package:silafit/features/splits/split_recommendation.dart';
import 'package:silafit/features/splits/splits_models.dart';

WorkoutSplit _split(
  String id, {
  String? recommendedGoal,
  bool matchesGoal = false,
  bool isSystemDefault = false,
  String category = 'FullBody',
  String level = 'Beginner',
  int durationDays = 3,
  int? matchScore,
  String? matchReason,
}) =>
    WorkoutSplit(
      splitId: id,
      name: id,
      category: category,
      level: level,
      durationDays: durationDays,
      isSystemDefault: isSystemDefault,
      recommendedGoal: recommendedGoal,
      matchesGoal: matchesGoal,
      matchScore: matchScore,
      matchReason: matchReason,
    );

MealSuggestion _meal(
  String id, {
  String mealType = 'Lunch',
  int caloriesKcal = 500,
  int proteinG = 30,
  int sortOrder = 0,
  int? matchScore,
  String? matchReason,
}) =>
    MealSuggestion(
      mealSuggestionId: id,
      title: id,
      mealType: mealType,
      caloriesKcal: caloriesKcal,
      proteinG: proteinG,
      carbsG: 40,
      fatsG: 15,
      sortOrder: sortOrder,
      matchScore: matchScore,
      matchReason: matchReason,
    );

MealDay _day({
  required int remainingCalories,
  required int targetProteinG,
  required int consumedProteinG,
}) =>
    MealDay(
      targets: NutritionTargets(
        targetCalories: 2000,
        targetProteinG: targetProteinG,
        targetCarbsG: 200,
        targetFatsG: 70,
      ),
      meals: const [],
      consumedCalories: 2000 - remainingCalories,
      remainingCalories: remainingCalories,
      consumedProteinG: consumedProteinG,
      consumedCarbsG: 0,
      consumedFatsG: 0,
    );

void main() {
  group('rankSplitMatches', () {
    test('goal-matched split outranks an unmatched featured one', () {
      final ranked = rankSplitMatches([
        _split('featured', isSystemDefault: true),
        _split('match',
            recommendedGoal: 'BuildMuscle',
            matchesGoal: true,
            isSystemDefault: true),
      ]);

      expect(ranked.first.split.splitId, 'match');
      expect(ranked.first.reason, contains('Build Muscle'));
    });

    test('falls back to a featured starter when nothing matches the goal', () {
      final ranked = rankSplitMatches([
        _split('plain'),
        _split('featured', isSystemDefault: true),
      ]);

      expect(ranked.first.split.splitId, 'featured');
      expect(ranked.first.reason, contains('Featured'));
    });

    test('prefers the backend person-fit score and its reason when present',
        () {
      final ranked = rankSplitMatches([
        // On the legacy scale this would win (goal match + featured), but the
        // whole payload is server-scored, so the backend's person fit decides.
        _split('local-pick',
            matchesGoal: true, isSystemDefault: true, matchScore: 300),
        _split('server-pick',
            matchScore: 900, matchReason: 'Matched to your Build Muscle goal'),
      ]);

      expect(ranked.first.split.splitId, 'server-pick');
      expect(ranked.first.reason, 'Matched to your Build Muscle goal');
    });
  });

  group('rankMealMatches', () {
    test('prefers the meal that fits remaining calories and protein gap', () {
      final ranked = rankMealMatches(
        [
          _meal('oversized', caloriesKcal: 900, proteinG: 40),
          _meal('fits', caloriesKcal: 480, proteinG: 45),
        ],
        day: _day(
            remainingCalories: 500, targetProteinG: 150, consumedProteinG: 100),
        now: DateTime(2026, 1, 1, 12),
      );

      expect(ranked.first.suggestion.mealSuggestionId, 'fits');
      expect(ranked.first.reason, contains('500 kcal remaining'));
    });

    test('time of day breaks ties between otherwise identical meals', () {
      final ranked = rankMealMatches(
        [
          _meal('dinner', mealType: 'Dinner'),
          _meal('breakfast', mealType: 'Breakfast'),
        ],
        now: DateTime(2026, 1, 1, 8),
      );

      expect(ranked.first.suggestion.mealSuggestionId, 'breakfast');
      expect(ranked.first.reason, contains('Breakfast'));
    });

    test('falls back to a sensible pick when the day has not loaded', () {
      final ranked = rankMealMatches(
        [
          _meal('small', proteinG: 10),
          _meal('protein-heavy', proteinG: 40),
        ],
        now: DateTime(2026, 1, 1, 12),
      );

      expect(ranked.first.suggestion.mealSuggestionId, 'protein-heavy');
      expect(ranked.first.reason, contains('protein'));
    });

    test('person-fit score can outrank a marginally better day fit', () {
      final ranked = rankMealMatches(
        [
          _meal('generic', caloriesKcal: 490, proteinG: 30, matchScore: 20),
          _meal('personalized',
              caloriesKcal: 520, proteinG: 30, matchScore: 100),
        ],
        day: _day(
            remainingCalories: 500, targetProteinG: 150, consumedProteinG: 100),
        now: DateTime(2026, 1, 1, 12),
      );

      expect(ranked.first.suggestion.mealSuggestionId, 'personalized');
    });

    test('shows the backend person-fit reason alongside the day context', () {
      final ranked = rankMealMatches(
        [
          _meal('personalized',
              matchScore: 90,
              matchReason: 'High protein toward your 160g target'),
        ],
        day: _day(
            remainingCalories: 500, targetProteinG: 160, consumedProteinG: 100),
        now: DateTime(2026, 1, 1, 12),
      );

      expect(ranked.first.reason, contains('160g target'));
      expect(ranked.first.reason, contains('500 kcal left'));
    });
  });
}
