import '../../core/api/api_client.dart';
import 'today_models.dart';

/// Talks to `api/today/*` - the one fully-wired vertical slice.
class TodayRepository {
  final ApiClient _client;

  TodayRepository(this._client);

  Future<TodayDashboard> getDashboard() =>
      _client.get('/today', TodayDashboard.fromJson);

  /// Returns the new running total in ml.
  Future<int> logHydration(int amountMl) => _client.post(
        '/today/hydration',
        (json) => json as int,
        body: {'amountMl': amountMl},
      );

  Future<BodyweightLogResult> logBodyweight(double weightKg) => _client.post(
        '/today/bodyweight',
        BodyweightLogResult.fromJson,
        body: {'weightKg': weightKg},
      );

  Future<void> completeWorkout({
    required String workoutSessionId,
    required int durationMinutes,
    int? caloriesEstimate,
    double? rpeScore,
    double? tonnageKg,
  }) =>
      _client.post(
        '/today/workout/complete',
        (_) => null,
        body: {
          'workoutSessionId': workoutSessionId,
          'durationMinutes': durationMinutes,
          if (caloriesEstimate != null) 'caloriesEstimate': caloriesEstimate,
          if (rpeScore != null) 'rpeScore': rpeScore,
          if (tonnageKg != null) 'tonnageKg': tonnageKg,
        },
      );
}
