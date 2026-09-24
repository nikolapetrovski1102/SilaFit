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

  /// The foods this meal was built from in the meal tracker. Empty for
  /// planned diet-plan meals and anything logged as a single macro total.
  final List<MealLogItem> items;

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
    this.items = const [],
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
      items: (map['items'] as List? ?? const [])
          .map((e) => MealLogItem.fromJson(e))
          .toList(growable: false),
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
        items: items,
      );
}

double _toDouble(Object? value) => (value as num?)?.toDouble() ?? 0;
double? _toNullableDouble(Object? value) => (value as num?)?.toDouble();

/// Mirrors `Silen.Common.Models.FoodNutritionModel` - one row from the
/// nutrition catalog (or a food the user added themselves). Every nutrient is
/// per 100 g; [MealLogItem.fromFood] scales it to the grams actually eaten.
class FoodItem {
  final int foodNutritionId;
  final String name;
  final String? brandName;
  final String sourceName;
  final double? servingSizeG;
  final double caloriesKcal;
  final double proteinG;
  final double carbohydrateG;
  final double fatG;
  final double? fiberG;
  final double? sugarG;
  final double? sodiumMg;
  final bool isCustom;

  const FoodItem({
    required this.foodNutritionId,
    required this.name,
    this.brandName,
    this.sourceName = '',
    this.servingSizeG,
    required this.caloriesKcal,
    required this.proteinG,
    required this.carbohydrateG,
    required this.fatG,
    this.fiberG,
    this.sugarG,
    this.sodiumMg,
    this.isCustom = false,
  });

  factory FoodItem.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return FoodItem(
      foodNutritionId: map['foodNutritionId'] as int,
      name: map['name'] as String? ?? '',
      brandName: map['brandName'] as String?,
      sourceName: map['sourceName'] as String? ?? '',
      servingSizeG: _toNullableDouble(map['servingSizeG']),
      caloriesKcal: _toDouble(map['caloriesKcal']),
      proteinG: _toDouble(map['proteinG']),
      carbohydrateG: _toDouble(map['carbohydrateG']),
      fatG: _toDouble(map['fatG']),
      fiberG: _toNullableDouble(map['fiberG']),
      sugarG: _toNullableDouble(map['sugarG']),
      sodiumMg: _toNullableDouble(map['sodiumMg']),
      isCustom: map['isCustom'] as bool? ?? false,
    );
  }

  /// A sensible starting amount when the food is added to a meal: its
  /// labelled serving when the catalog has one, otherwise 100 g.
  double get defaultGrams =>
      servingSizeG != null && servingSizeG! > 0 ? servingSizeG! : 100;
}

/// Mirrors `Silen.Common.Models.MealLogItemModel` - one food in a logged
/// meal. Macros are for [grams] (already scaled), snapshotted when logged so
/// a later catalog change never rewrites what the user ate.
class MealLogItem {
  final int? foodNutritionId;
  final String name;
  final String? brandName;
  final double grams;
  final double caloriesKcal;
  final double proteinG;
  final double carbsG;
  final double fatsG;
  final double? fiberG;
  final double? sugarG;
  final double? sodiumMg;

  /// The per-100 g source, kept client-side only so editing the grams of a
  /// food added this session rescales exactly. Items loaded from the server
  /// rescale from their own stored ratio instead (see [withGrams]).
  final FoodItem? food;

  const MealLogItem({
    this.foodNutritionId,
    required this.name,
    this.brandName,
    required this.grams,
    required this.caloriesKcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatsG,
    this.fiberG,
    this.sugarG,
    this.sodiumMg,
    this.food,
  });

  factory MealLogItem.fromFood(FoodItem food, double grams) {
    final f = grams / 100;
    double? scale(double? v) => v == null ? null : v * f;
    return MealLogItem(
      foodNutritionId: food.foodNutritionId,
      name: food.name,
      brandName: food.brandName,
      grams: grams,
      caloriesKcal: food.caloriesKcal * f,
      proteinG: food.proteinG * f,
      carbsG: food.carbohydrateG * f,
      fatsG: food.fatG * f,
      fiberG: scale(food.fiberG),
      sugarG: scale(food.sugarG),
      sodiumMg: scale(food.sodiumMg),
      food: food,
    );
  }

  factory MealLogItem.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return MealLogItem(
      foodNutritionId: map['foodNutritionId'] as int?,
      name: map['name'] as String? ?? '',
      brandName: map['brandName'] as String?,
      grams: _toDouble(map['grams']),
      caloriesKcal: _toDouble(map['caloriesKcal']),
      proteinG: _toDouble(map['proteinG']),
      carbsG: _toDouble(map['carbsG']),
      fatsG: _toDouble(map['fatsG']),
      fiberG: _toNullableDouble(map['fiberG']),
      sugarG: _toNullableDouble(map['sugarG']),
      sodiumMg: _toNullableDouble(map['sodiumMg']),
    );
  }

  Map<String, dynamic> toJson() => {
        'foodNutritionId': foodNutritionId,
        'name': name,
        'brandName': brandName,
        'grams': _round(grams),
        'caloriesKcal': _round(caloriesKcal),
        'proteinG': _round(proteinG),
        'carbsG': _round(carbsG),
        'fatsG': _round(fatsG),
        'fiberG': fiberG == null ? null : _round(fiberG!),
        'sugarG': sugarG == null ? null : _round(sugarG!),
        'sodiumMg': sodiumMg?.roundToDouble(),
      };

  static double _round(double v) => (v * 10).roundToDouble() / 10;

  /// The same food at a different amount - rescaled from the per-100 g
  /// source when known, else proportionally from the stored values.
  MealLogItem withGrams(double newGrams) {
    if (food != null) return MealLogItem.fromFood(food!, newGrams);
    final f = grams <= 0 ? 0.0 : newGrams / grams;
    double? scale(double? v) => v == null ? null : v * f;
    return MealLogItem(
      foodNutritionId: foodNutritionId,
      name: name,
      brandName: brandName,
      grams: newGrams,
      caloriesKcal: caloriesKcal * f,
      proteinG: proteinG * f,
      carbsG: carbsG * f,
      fatsG: fatsG * f,
      fiberG: scale(fiberG),
      sugarG: scale(sugarG),
      sodiumMg: scale(sodiumMg),
    );
  }
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

/// Sums of a list of [MealLogItem]s - the meal tracker's running readout and
/// the totals a food-by-food meal is saved with.
class MealTotals {
  /// Combined weight of every food in the meal.
  final double grams;
  final double caloriesKcal;
  final double proteinG;
  final double carbsG;
  final double fatsG;
  final double? fiberG;
  final double? sugarG;
  final double? sodiumMg;

  const MealTotals({
    this.grams = 0,
    this.caloriesKcal = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatsG = 0,
    this.fiberG,
    this.sugarG,
    this.sodiumMg,
  });

  factory MealTotals.of(List<MealLogItem> items) {
    double? sumOptional(double? Function(MealLogItem) pick) {
      final values = items.map(pick).whereType<double>();
      return values.isEmpty ? null : values.fold<double>(0, (a, b) => a + b);
    }

    return MealTotals(
      grams: items.fold(0, (a, i) => a + i.grams),
      caloriesKcal: items.fold(0, (a, i) => a + i.caloriesKcal),
      proteinG: items.fold(0, (a, i) => a + i.proteinG),
      carbsG: items.fold(0, (a, i) => a + i.carbsG),
      fatsG: items.fold(0, (a, i) => a + i.fatsG),
      fiberG: sumOptional((i) => i.fiberG),
      sugarG: sumOptional((i) => i.sugarG),
      sodiumMg: sumOptional((i) => i.sodiumMg),
    );
  }
}

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
  final String? ingredientPreview;
  final int ingredientCount;

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
    this.ingredientPreview,
    this.ingredientCount = 0,
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
      ingredientPreview: map['ingredientPreview'] as String?,
      ingredientCount: map['ingredientCount'] as int? ?? 0,
      sortOrder: map['sortOrder'] as int? ?? 0,
      matchScore: map['matchScore'] as int?,
      matchReason: map['matchReason'] as String?,
    );
  }

  /// Four ingredients at most, followed by a count instead of expanding into
  /// the complete recipe inside compact recommendation surfaces.
  String? get compactIngredientSummary {
    final preview = ingredientPreview?.trim();
    if (preview == null || preview.isEmpty) return null;
    final remaining = ingredientCount - 4;
    return remaining > 0 ? '$preview · +$remaining more' : preview;
  }
}
