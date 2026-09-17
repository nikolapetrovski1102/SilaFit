import '../../core/api/api_client.dart';
import 'diet_guide_models.dart';

class DietGuideRepository {
  final ApiClient _client;

  DietGuideRepository(this._client);

  Future<List<DietGuide>> getAll() => _client.get(
      '/diet-guides',
      (json) => (json as List<dynamic>)
          .map(DietGuide.fromJson)
          .toList());

  Future<DietGuideDetail> getDetail(String dietGuideId) =>
      _client.get('/diet-guides/$dietGuideId', DietGuideDetail.fromJson);
}
