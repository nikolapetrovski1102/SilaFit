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
        .get('/progress', ProgressOverview.fromJson,
            query: {'days': '$days'}, cache: true);
    _overviewCache[key] = _CachedOverview(overview);
    return overview;
  }

  /// [getOverview]'s saved copy, for painting before it answers.
  Future<ProgressOverview?> getCachedOverview({int days = 28}) async =>
      (await _client.cached('/progress', ProgressOverview.fromJson,
              query: {'days': '$days'}))
          ?.value;

  static List<PersonalRecord> _parseRecords(dynamic json) =>
      (json as List<dynamic>).map((e) => PersonalRecord.fromJson(e)).toList();

  Future<List<PersonalRecord>> getPersonalRecords({int top = 5}) => _client.get(
        '/progress/personal-records',
        _parseRecords,
        query: {'top': '$top'},
        cache: true,
      );

  /// [getPersonalRecords]' saved copy, for painting before it answers.
  Future<List<PersonalRecord>?> getCachedPersonalRecords({int top = 5}) async =>
      (await _client.cached('/progress/personal-records', _parseRecords,
              query: {'top': '$top'}))
          ?.value;

  /// PRO/Advanced only - a Free caller gets a 403, which is how the Progress
  /// screen learns it should render locked. [cache] is off while viewing on
  /// an ad pass, so the offline copy can't keep the screen open after it.
  Future<List<TrackedExercise>> getTrackedExercises({bool cache = true}) =>
      _client.get(
        '/progress/exercises',
        (json) => (json as List<dynamic>)
            .map((e) => TrackedExercise.fromJson(e))
            .toList(),
        cache: cache,
      );

  /// PRO/Advanced only - 403 otherwise. [cache] as on [getTrackedExercises].
  Future<ExerciseProgress> getExerciseProgress(String exerciseId,
          {required int days, bool cache = true}) =>
      _client.get('/progress/exercises/$exerciseId', ExerciseProgress.fromJson,
          query: {'days': '$days'}, cache: cache);

  /// Opens the per-exercise Progress endpoints for a Free account that just
  /// watched a rewarded video. 429 once the day's passes are used up. True
  /// when a pass was granted; false for a Pro account, which needs none.
  Future<bool> grantAdPass() => _client.post('/progress/ad-pass',
      (json) => json is Map && json['expiresAtUtc'] != null);

  /// Ends the ad pass - the user left the Progress screen.
  Future<void> endAdPass() => _client.delete('/progress/ad-pass', (_) {});
}

class _CachedOverview {
  final ProgressOverview value;
  final DateTime storedAt;

  _CachedOverview(this.value) : storedAt = DateTime.now();
}
