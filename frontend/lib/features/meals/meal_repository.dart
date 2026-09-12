import '../../core/api/api_client.dart';
import 'meal_models.dart';

/// Talks to `api/meals/*` - meal planning/logging and nutrition targets,
/// open to any authenticated tier including guests.
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
        },
      );

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
}
