/// Mirrors `Silen.Common.Models.DietPlanModels` / `Silen.Common.Dtos.DietPlanDtos` -
/// the meal-planning equivalent of `splits_models.dart`, field-for-field.
class DietPlan {
  final String dietPlanId;
  final String name;
  final String? description;
  final String? heroImageUrl;
  final String periodType;
  final int durationDays;
  final bool isSystemDefault;
  final String visibility;

  // True only when this caller built the plan themselves via the in-app
  // builder. Trainer-assigned and system plans are never editable.
  final bool isEditableByMe;

  // True when Silen.Tools.WeeklyPlanGeneration wrote this plan rather than
  // the user building it by hand. aiKeptAtUtc is null while it's still
  // eligible to be overwritten by next Sunday's run; once the user taps
  // "Keep this plan" it's permanent and a new one is generated separately.
  final bool isAiGenerated;
  final DateTime? aiKeptAtUtc;

  const DietPlan({
    required this.dietPlanId,
    required this.name,
    this.description,
    this.heroImageUrl,
    required this.periodType,
    required this.durationDays,
    required this.isSystemDefault,
    this.visibility = 'Public',
    this.isEditableByMe = false,
    this.isAiGenerated = false,
    this.aiKeptAtUtc,
  });

  factory DietPlan.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return DietPlan(
      dietPlanId: map['dietPlanId'] as String,
      name: map['name'] as String? ?? '',
      description: map['description'] as String?,
      heroImageUrl: map['heroImageUrl'] as String?,
      periodType: map['periodType'] as String? ?? 'Weekly',
      durationDays: map['durationDays'] as int? ?? 0,
      isSystemDefault: map['isSystemDefault'] as bool? ?? false,
      visibility: map['visibility'] as String? ?? 'Public',
      isEditableByMe: map['isEditableByMe'] as bool? ?? false,
      isAiGenerated: map['isAiGenerated'] as bool? ?? false,
      aiKeptAtUtc: map['aiKeptAtUtc'] != null
          ? DateTime.parse(map['aiKeptAtUtc'] as String)
          : null,
    );
  }
}

class DietPlanDay {
  final String dietPlanDayId;
  final int dayIndex;
  final String? title;

  const DietPlanDay({
    required this.dietPlanDayId,
    required this.dayIndex,
    this.title,
  });

  factory DietPlanDay.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return DietPlanDay(
      dietPlanDayId: map['dietPlanDayId'] as String,
      dayIndex: map['dayIndex'] as int? ?? 0,
      title: map['title'] as String?,
    );
  }
}

/// One meal slot within a diet-plan day, carrying the referenced
/// MealSuggestions row's fields so the UI can render it with no second lookup.
class DietPlanMeal {
  final String dietPlanDayId;
  final String dietPlanMealId;
  final String mealType;
  final String mealSuggestionId;
  final String title;
  final String? description;
  final int caloriesKcal;
  final int proteinG;
  final int carbsG;
  final int fatsG;
  final int sortOrder;

  const DietPlanMeal({
    required this.dietPlanDayId,
    required this.dietPlanMealId,
    required this.mealType,
    required this.mealSuggestionId,
    required this.title,
    this.description,
    required this.caloriesKcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatsG,
    required this.sortOrder,
  });

  factory DietPlanMeal.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return DietPlanMeal(
      dietPlanDayId: map['dietPlanDayId'] as String,
      dietPlanMealId: map['dietPlanMealId'] as String,
      mealType: map['mealType'] as String? ?? '',
      mealSuggestionId: map['mealSuggestionId'] as String,
      title: map['title'] as String? ?? '',
      description: map['description'] as String?,
      caloriesKcal: map['caloriesKcal'] as int? ?? 0,
      proteinG: map['proteinG'] as int? ?? 0,
      carbsG: map['carbsG'] as int? ?? 0,
      fatsG: map['fatsG'] as int? ?? 0,
      sortOrder: map['sortOrder'] as int? ?? 0,
    );
  }
}

class DietPlanDayWithMeals {
  final DietPlanDay day;
  final List<DietPlanMeal> meals;

  const DietPlanDayWithMeals({required this.day, required this.meals});

  factory DietPlanDayWithMeals.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return DietPlanDayWithMeals(
      day: DietPlanDay.fromJson(map['day']),
      meals: (map['meals'] as List<dynamic>? ?? [])
          .map((e) => DietPlanMeal.fromJson(e))
          .toList(),
    );
  }
}

class DietPlanDetail {
  final DietPlan plan;
  final List<DietPlanDayWithMeals> days;

  /// Quantity-aggregated ingredient lines across the plan's meals - the
  /// week's shopping list. Empty when the meals have no ingredient data.
  final List<String> shoppingList;

  const DietPlanDetail({
    required this.plan,
    required this.days,
    this.shoppingList = const [],
  });

  factory DietPlanDetail.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return DietPlanDetail(
      plan: DietPlan.fromJson(map['plan']),
      days: (map['days'] as List<dynamic>? ?? [])
          .map((e) => DietPlanDayWithMeals.fromJson(e))
          .toList(),
      shoppingList: (map['shoppingList'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
    );
  }
}
