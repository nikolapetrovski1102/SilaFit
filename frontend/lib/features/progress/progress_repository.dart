import '../../core/api/api_client.dart';
import 'progress_models.dart';

class ProgressRepository {
  final ApiClient _client;

  ProgressRepository(this._client);

  Future<ProgressOverview> getOverview({int days = 28}) => _client
      .get('/progress', ProgressOverview.fromJson, query: {'days': '$days'});
}
