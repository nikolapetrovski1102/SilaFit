/// Mirrors `Silen.Common.Models.UserNutritionTargetsModel`.
class NutritionTargets {
  final int targetCalories;
  final int targetProteinG;
  final int targetCarbsG;
  final int targetFatsG;

  const NutritionTargets({
    required this.targetCalories,
    required this.targetProteinG,
    required this.targetCarbsG,
    required this.targetFatsG,
  });

  factory NutritionTargets.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return NutritionTargets(
      targetCalories: map['targetCalories'] as int,
      targetProteinG: map['targetProteinG'] as int,
      targetCarbsG: map['targetCarbsG'] as int,
      targetFatsG: map['targetFatsG'] as int,
    );
  }
}

/// Mirrors `Silen.Common.Models.MealLogModel`. Planned and logged meals are
/// the same row, differentiated by [status] - no separate "plan" model.
class MealLog {
  final String mealLogId;
  final String logDateUtc; // yyyy-MM-dd
  final String mealType; // Breakfast/Lunch/Dinner/Snack
  final String title;
  final int caloriesKcal;
  final int proteinG;
  final int carbsG;
  final int fatsG;
  final String status; // Planned/Logged
  final String? plannedLocalTime; // HH:mm:ss

  const MealLog({
    required this.mealLogId,
    required this.logDateUtc,
    required this.mealType,
    required this.title,
    required this.caloriesKcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatsG,
    required this.status,
    this.plannedLocalTime,
  });

  bool get isLogged => status == 'Logged';

  factory MealLog.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return MealLog(
      mealLogId: map['mealLogId'] as String,
      logDateUtc: map['logDateUtc'] as String,
      mealType: map['mealType'] as String,
      title: map['title'] as String,
      caloriesKcal: map['caloriesKcal'] as int,
      proteinG: map['proteinG'] as int,
      carbsG: map['carbsG'] as int,
      fatsG: map['fatsG'] as int,
      status: map['status'] as String,
      plannedLocalTime: map['plannedLocalTime'] as String?,
    );
  }

  MealLog copyWith({String? status}) => MealLog(
        mealLogId: mealLogId,
        logDateUtc: logDateUtc,
        mealType: mealType,
        title: title,
        caloriesKcal: caloriesKcal,
        proteinG: proteinG,
        carbsG: carbsG,
        fatsG: fatsG,
        status: status ?? this.status,
        plannedLocalTime: plannedLocalTime,
      );
}

/// Mirrors `Silen.Common.Dtos.MealDayDto` - the composed view the app
/// renders for one day.
class MealDay {
  final NutritionTargets targets;
  final List<MealLog> meals;
  final int consumedCalories;
  final int remainingCalories;
  final int consumedProteinG;
  final int consumedCarbsG;
  final int consumedFatsG;

  const MealDay({
    required this.targets,
    required this.meals,
    required this.consumedCalories,
    required this.remainingCalories,
    required this.consumedProteinG,
    required this.consumedCarbsG,
    required this.consumedFatsG,
  });

  factory MealDay.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return MealDay(
      targets: NutritionTargets.fromJson(map['targets']),
      meals: (map['meals'] as List)
          .map((e) => MealLog.fromJson(e))
          .toList(growable: false),
      consumedCalories: map['consumedCalories'] as int,
      remainingCalories: map['remainingCalories'] as int,
      consumedProteinG: map['consumedProteinG'] as int,
      consumedCarbsG: map['consumedCarbsG'] as int,
      consumedFatsG: map['consumedFatsG'] as int,
    );
  }
}

const kMealTypes = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

/// Mirrors `Silen.Common.Models.MealSuggestionModel` - one curated meal idea
/// from the seeded library, shown in the "Suggested this month" strip.
class MealSuggestion {
  final String mealSuggestionId;
  final String title;
  final String mealType;
  final String? description;
  final int caloriesKcal;
  final int proteinG;
  final int carbsG;
  final int fatsG;

  /// The library's curated position, used only as a stable tie-breaker when
  /// two meals score identically in `meal_recommendation.dart`.
  final int sortOrder;

  /// Person-fit score (0-100) computed server-side against the caller's own
  /// nutrition targets, which derive from their height/weight/age/gender/goal.
  /// Null on payloads that predate this field (or in tests), where ranking
  /// falls back to pure day/time fit.
  final int? matchScore;

  /// Plain-language explanation of [matchScore], shown in the UI.
  final String? matchReason;

  const MealSuggestion({
    required this.mealSuggestionId,
    required this.title,
    required this.mealType,
    this.description,
    required this.caloriesKcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatsG,
    this.sortOrder = 0,
    this.matchScore,
    this.matchReason,
  });

  factory MealSuggestion.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return MealSuggestion(
      mealSuggestionId: map['mealSuggestionId'] as String,
      title: map['title'] as String? ?? '',
      mealType: map['mealType'] as String? ?? '',
      description: map['description'] as String?,
      caloriesKcal: map['caloriesKcal'] as int? ?? 0,
      proteinG: map['proteinG'] as int? ?? 0,
      carbsG: map['carbsG'] as int? ?? 0,
      fatsG: map['fatsG'] as int? ?? 0,
      sortOrder: map['sortOrder'] as int? ?? 0,
      matchScore: map['matchScore'] as int?,
      matchReason: map['matchReason'] as String?,
    );
  }
}
