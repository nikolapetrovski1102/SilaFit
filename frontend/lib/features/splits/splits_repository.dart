import '../../core/api/api_client.dart';
import 'splits_models.dart';

class SplitsRepository {
  final ApiClient _client;

  SplitsRepository(this._client);

  static List<WorkoutSplit> _parseSplits(dynamic json) =>
      (json as List<dynamic>).map((e) => WorkoutSplit.fromJson(e)).toList();

  Future<List<WorkoutSplit>> getAll() =>
      _client.get('/splits', _parseSplits, cache: true);

  /// [getAll]'s saved copy, for painting before it answers.
  Future<List<WorkoutSplit>?> getCachedAll() async =>
      (await _client.cached('/splits', _parseSplits))?.value;

  Future<SplitDetail> getDetail(String splitId) =>
      _client.get('/splits/$splitId', SplitDetail.fromJson, cache: true);

  /// [getDetail]'s saved copy, for painting before it answers.
  Future<SplitDetail?> getCachedDetail(String splitId) async =>
      (await _client.cached('/splits/$splitId', SplitDetail.fromJson))?.value;

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
          .toList(),
      cache: true);

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

  /// Copies one of the user's own splits, days and exercises included.
  /// PRO/Advanced only, and counts toward the plan's split limit - both
  /// refusals come back as 403.
  Future<String?> duplicate(String splitId) => _client.post(
        '/splits/mine/$splitId/duplicate',
        (json) => (json as Map<String, dynamic>)['id'] as String?,
      );

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

  /// Copies a day (and its exercises) in right after itself, pushing the
  /// later days back one.
  Future<String?> duplicateDay(String splitDayId) => _client.post(
        '/splits/days/$splitDayId/duplicate',
        (json) => (json as Map<String, dynamic>)['id'] as String?,
      );

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
