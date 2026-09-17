import '../../core/api/api_client.dart';
import 'diet_plan_models.dart';

class DietPlanRepository {
  final ApiClient _client;

  DietPlanRepository(this._client);

  Future<List<DietPlan>> getAll() => _client.get(
      '/diet-plans',
      (json) =>
          (json as List<dynamic>).map((e) => DietPlan.fromJson(e)).toList());

  Future<DietPlanDetail> getDetail(String dietPlanId) =>
      _client.get('/diet-plans/$dietPlanId', DietPlanDetail.fromJson);

  /// The caller's active plan with days/meals, or null when none is active.
  Future<DietPlanDetail?> getActive() => _client.get(
      '/diet-plans/active',
      (json) => json == null ? null : DietPlanDetail.fromJson(json));

  /// Makes any visible plan the caller's active plan.
  Future<void> activate(String dietPlanId) =>
      _client.post('/diet-plans/$dietPlanId/activate', (_) => null);

  /// Builds a fresh weekly plan from the caller's calorie/macro targets and
  /// activates it, returning the generated plan.
  Future<DietPlanDetail> generate() =>
      _client.post('/diet-plans/generate', DietPlanDetail.fromJson);

  /* ----------------------------- user-owned diet plans ----------------------------- */

  Future<List<DietPlan>> getMine() => _client.get(
      '/diet-plans/mine',
      (json) =>
          (json as List<dynamic>).map((e) => DietPlan.fromJson(e)).toList());

  Future<String?> createOrUpdate({
    String? dietPlanId,
    required String name,
    String? description,
    String? heroImageUrl,
    required String periodType,
    required int durationDays,
  }) =>
      _client.post(
        '/diet-plans',
        (json) => (json as Map<String, dynamic>)['id'] as String?,
        body: {
          'dietPlanId': dietPlanId,
          'name': name,
          'description': description,
          'heroImageUrl': heroImageUrl,
          'periodType': periodType,
          'durationDays': durationDays,
        },
      );

  Future<void> delete(String dietPlanId) =>
      _client.delete('/diet-plans/$dietPlanId', (_) => null);

  Future<void> keep(String dietPlanId) =>
      _client.post('/diet-plans/mine/$dietPlanId/keep', (_) => null);

  Future<String?> saveDay({
    String? dietPlanDayId,
    required String dietPlanId,
    required int dayIndex,
    String? title,
  }) =>
      _client.post(
        '/diet-plans/days',
        (json) => (json as Map<String, dynamic>)['id'] as String?,
        body: {
          'dietPlanDayId': dietPlanDayId,
          'dietPlanId': dietPlanId,
          'dayIndex': dayIndex,
          'title': title,
        },
      );

  Future<void> deleteDay(String dietPlanDayId) =>
      _client.delete('/diet-plans/days/$dietPlanDayId', (_) => null);

  Future<String?> saveMeal({
    String? dietPlanMealId,
    required String dietPlanDayId,
    required String mealType,
    required String mealSuggestionId,
    required int sortOrder,
  }) =>
      _client.post(
        '/diet-plans/meals',
        (json) => (json as Map<String, dynamic>)['id'] as String?,
        body: {
          'dietPlanMealId': dietPlanMealId,
          'dietPlanDayId': dietPlanDayId,
          'mealType': mealType,
          'mealSuggestionId': mealSuggestionId,
          'sortOrder': sortOrder,
        },
      );

  Future<void> deleteMeal(String dietPlanMealId) =>
      _client.delete('/diet-plans/meals/$dietPlanMealId', (_) => null);
}
