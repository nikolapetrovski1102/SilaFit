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
}
