import '../../core/api/api_client.dart';
import 'meal_models.dart';

/// Talks to `api/meals/*` (meal planning/logging and nutrition targets) and
/// `api/foods/*` (the food catalog the meal tracker searches) - both open to
/// any authenticated tier including guests.
class MealRepository {
  final ApiClient _client;

  MealRepository(this._client);

  String _isoDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<MealDay> getDay(DateTime date) => _client.get(
        '/meals/day',
        MealDay.fromJson,
        query: {'date': _isoDate(date)},
      );

  Future<MealLog> createLog({
    required DateTime logDate,
    required String mealType,
    required String title,
    required int caloriesKcal,
    required int proteinG,
    required int carbsG,
    required int fatsG,
    String status = 'Planned',
    List<MealLogItem>? items,
  }) =>
      _client.post(
        '/meals/log',
        MealLog.fromJson,
        body: {
          'logDateUtc': _isoDate(logDate),
          'mealType': mealType,
          'title': title,
          'caloriesKcal': caloriesKcal,
          'proteinG': proteinG,
          'carbsG': carbsG,
          'fatsG': fatsG,
          'status': status,
          if (items != null) 'items': [for (final i in items) i.toJson()],
        },
      );

  /// Saves [meal] as-is. Its [MealLog.items] are only sent when non-empty:
  /// the server keeps a meal's stored foods when none are sent, so a status
  /// flip never drops them.
  Future<MealLog> updateLog(MealLog meal) => _client.put(
        '/meals/log/${meal.mealLogId}',
        MealLog.fromJson,
        body: {
          'logDateUtc': meal.logDateUtc,
          'mealType': meal.mealType,
          'title': meal.title,
          'caloriesKcal': meal.caloriesKcal,
          'proteinG': meal.proteinG,
          'carbsG': meal.carbsG,
          'fatsG': meal.fatsG,
          'status': meal.status,
          if (meal.items.isNotEmpty)
            'items': [for (final i in meal.items) i.toJson()],
        },
      );

  Future<void> deleteLog(String mealLogId) =>
      _client.delete('/meals/log/$mealLogId', (_) => null);

  /// Curated meal ideas for [month] (1-12); the backend defaults to the
  /// current UTC month when omitted.
  Future<List<MealSuggestion>> getSuggestions({int? month}) => _client.get(
        '/meals/suggestions',
        (json) => (json as List)
            .map((e) => MealSuggestion.fromJson(e))
            .toList(growable: false),
        query: month != null ? {'month': '$month'} : null,
      );

  /// Catalog search behind the meal tracker (`api/foods/search`) - the shared
  /// nutrition database plus foods this user added. Prefix match on the name.
  Future<List<FoodItem>> searchFoods(String query, {int take = 25}) =>
      _client.get(
        '/foods/search',
        (json) => (json as List)
            .map((e) => FoodItem.fromJson(e))
            .toList(growable: false),
        query: {'q': query, 'take': '$take'},
      );

  /// Adds a food the catalog doesn't have; private to this user. All
  /// nutrients are per 100 g.
  Future<FoodItem> createCustomFood({
    required String name,
    String? brandName,
    double? servingSizeG,
    required double caloriesKcal,
    required double proteinG,
    required double carbohydrateG,
    required double fatG,
    double? fiberG,
    double? sugarG,
    double? sodiumMg,
  }) =>
      _client.post(
        '/foods',
        FoodItem.fromJson,
        body: {
          'name': name,
          'brandName': brandName,
          'servingSizeG': servingSizeG,
          'caloriesKcal': caloriesKcal,
          'proteinG': proteinG,
          'carbohydrateG': carbohydrateG,
          'fatG': fatG,
          'fiberG': fiberG,
          'sugarG': sugarG,
          'sodiumMg': sodiumMg,
        },
      );
}
