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

  /// "Did you mean" picks for a search that found nothing - catalogue names a
  /// typo or two away from [search]. Empty means nothing is close.
  Future<List<ExerciseSummary>> closeMatches(String search) {
    return _client.get(
      '/exercises/close-matches',
      (json) => (json as List<dynamic>)
          .map((e) => ExerciseSummary.fromJson(e))
          .toList(),
      query: {'search': search},
    );
  }

  /// Adds an exercise the catalogue doesn't have; private to this user. If the
  /// catalogue (or the user) already has that name, the server returns that
  /// exercise instead of a duplicate.
  Future<ExerciseSummary> createCustom({
    required String name,
    required String muscleGroup,
    required String equipmentType,
    required bool isCompound,
  }) =>
      _client.post(
        '/exercises',
        ExerciseSummary.fromJson,
        body: {
          'name': name,
          'muscleGroup': muscleGroup,
          'equipmentType': equipmentType,
          'isCompound': isCompound,
        },
      );
}
