import '../../core/api/api_client.dart';
import 'splits_models.dart';

class SplitsRepository {
  final ApiClient _client;

  SplitsRepository(this._client);

  Future<List<WorkoutSplit>> getAll() => _client.get(
      '/splits',
      (json) => (json as List<dynamic>)
          .map((e) => WorkoutSplit.fromJson(e))
          .toList());

  Future<SplitDetail> getDetail(String splitId) =>
      _client.get('/splits/$splitId', SplitDetail.fromJson);

  Future<void> activate(String splitId) => _client.post(
        '/splits/activate',
        (_) => null,
        body: {'splitId': splitId},
      );

  /* ----------------------------- user-owned splits ----------------------------- */

  Future<List<WorkoutSplit>> getMine() => _client.get(
      '/splits/mine',
      (json) => (json as List<dynamic>)
          .map((e) => WorkoutSplit.fromJson(e))
          .toList());

  Future<String?> createOrUpdate({
    String? splitId,
    required String name,
    required String category,
    required String level,
    required int durationDays,
    String? description,
    String? heroImageUrl,
    String? recommendedGoal,
  }) =>
      _client.post(
        '/splits',
        (json) => (json as Map<String, dynamic>)['id'] as String?,
        body: {
          'splitId': splitId,
          'name': name,
          'category': category,
          'level': level,
          'durationDays': durationDays,
          'description': description,
          'heroImageUrl': heroImageUrl,
          'recommendedGoal': recommendedGoal,
        },
      );

  Future<void> delete(String splitId) =>
      _client.delete('/splits/$splitId', (_) => null);

  Future<void> keep(String splitId) =>
      _client.post('/splits/mine/$splitId/keep', (_) => null);

  Future<String?> saveDay({
    String? splitDayId,
    required String splitId,
    required int dayIndex,
    required String title,
    String? focusLabel,
    int estimatedMinutes = 60,
    bool isRestDay = false,
  }) =>
      _client.post(
        '/splits/days',
        (json) => (json as Map<String, dynamic>)['id'] as String?,
        body: {
          'splitDayId': splitDayId,
          'splitId': splitId,
          'dayIndex': dayIndex,
          'title': title,
          'focusLabel': focusLabel,
          'estimatedMinutes': estimatedMinutes,
          'isRestDay': isRestDay,
        },
      );

  Future<void> deleteDay(String splitDayId) =>
      _client.delete('/splits/days/$splitDayId', (_) => null);

  Future<String?> saveDayExercise({
    String? splitDayExerciseId,
    required String splitDayId,
    required String exerciseId,
    required int sortOrder,
    required int targetSets,
    required int targetRepsLow,
    required int targetRepsHigh,
  }) =>
      _client.post(
        '/splits/day-exercises',
        (json) => (json as Map<String, dynamic>)['id'] as String?,
        body: {
          'splitDayExerciseId': splitDayExerciseId,
          'splitDayId': splitDayId,
          'exerciseId': exerciseId,
          'sortOrder': sortOrder,
          'targetSets': targetSets,
          'targetRepsLow': targetRepsLow,
          'targetRepsHigh': targetRepsHigh,
        },
      );

  Future<void> deleteDayExercise(String splitDayExerciseId) =>
      _client.delete('/splits/day-exercises/$splitDayExerciseId', (_) => null);
}
