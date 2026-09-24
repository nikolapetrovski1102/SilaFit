import '../../core/api/api_client.dart';
import 'progress_models.dart';

class ProgressRepository {
  final ApiClient _client;

  ProgressRepository(this._client);

  // Short-lived, per-actor cache. Home's day strip, the streak sheet and the
  // Progress tab all request /progress on mount, and a theme change remounts
  // them, so without this the same history is fetched repeatedly. The key
  // includes the bearer token so an account switch can never be served another
  // user's cached data; `force` (pull-to-refresh, timeframe change) bypasses it.
  static const _overviewTtl = Duration(seconds: 30);
  final Map<String, _CachedOverview> _overviewCache = {};

  Future<ProgressOverview> getOverview({int days = 28, bool force = false}) async {
    final key = '$days|${_client.sessionStore.currentToken ?? 'anonymous'}';
    if (!force) {
      final cached = _overviewCache[key];
      if (cached != null &&
          DateTime.now().difference(cached.storedAt) < _overviewTtl) {
        return cached.value;
      }
    }

    final overview = await _client
        .get('/progress', ProgressOverview.fromJson, query: {'days': '$days'});
    _overviewCache[key] = _CachedOverview(overview);
    return overview;
  }

  Future<List<PersonalRecord>> getPersonalRecords({int top = 5}) => _client.get(
        '/progress/personal-records',
        (json) => (json as List<dynamic>)
            .map((e) => PersonalRecord.fromJson(e))
            .toList(),
        query: {'top': '$top'},
      );

  /// PRO/Advanced only - a Free caller gets a 403, which is how the Progress
  /// screen learns it should render locked.
  Future<List<TrackedExercise>> getTrackedExercises() => _client.get(
        '/progress/exercises',
        (json) => (json as List<dynamic>)
            .map((e) => TrackedExercise.fromJson(e))
            .toList(),
      );

  /// PRO/Advanced only - 403 otherwise.
  Future<ExerciseProgress> getExerciseProgress(String exerciseId,
          {required int days}) =>
      _client.get('/progress/exercises/$exerciseId', ExerciseProgress.fromJson,
          query: {'days': '$days'});
}

class _CachedOverview {
  final ProgressOverview value;
  final DateTime storedAt;

  _CachedOverview(this.value) : storedAt = DateTime.now();
}
