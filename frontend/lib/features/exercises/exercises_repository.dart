import '../../core/api/api_client.dart';
import 'exercises_models.dart';

class ExercisesRepository {
  final ApiClient _client;

  ExercisesRepository(this._client);

  Future<List<ExerciseSummary>> search({String? muscleGroup, String? search}) {
    final query = <String, String>{};
    if (muscleGroup != null && muscleGroup.isNotEmpty) {
      query['muscleGroup'] = muscleGroup;
    }
    if (search != null && search.isNotEmpty) {
      query['search'] = search;
    }
    return _client.get(
      '/exercises',
      (json) => (json as List<dynamic>)
          .map((e) => ExerciseSummary.fromJson(e))
          .toList(),
      query: query.isEmpty ? null : query,
    );
  }

  /// Exercises ranked for this user's equipment and experience, best first.
  /// [muscleGroups] scopes and prioritises the list to the coarse groups a
  /// custom split day points at (title first, then previously added exercises);
  /// omitting it keeps the generic "suggested for you" list. Backs the picker
  /// the split builder opens with.
  Future<List<ExerciseSummary>> suggestions({
    List<String>? muscleGroups,
    int? limit,
  }) {
    final query = <String, String>{};
    if (muscleGroups != null && muscleGroups.isNotEmpty) {
      query['muscleGroups'] = muscleGroups.join(',');
    }
    if (limit != null) {
      query['limit'] = '$limit';
    }
    return _client.get(
      '/exercises/suggestions',
      (json) => (json as List<dynamic>)
          .map((e) => ExerciseSummary.fromJson(e))
          .toList(),
      query: query.isEmpty ? null : query,
    );
  }
}
