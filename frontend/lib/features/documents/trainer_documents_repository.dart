import '../../core/api/api_client.dart';
import 'trainer_document_models.dart';

/// `api/documents` - the trainer documents this user holds, and opening one.
class TrainerDocumentsRepository {
  final ApiClient _client;

  TrainerDocumentsRepository(this._client);

  /// Documents the trainer gave this user for one split / diet plan. Not
  /// cached: a revoked document must disappear, and they only open online.
  Future<List<TrainerDocument>> getFor(
          TrainerDocumentKind kind, String targetId) =>
      _client.get(
        '/documents',
        (json) => (json as List<dynamic>)
            .map((e) => TrainerDocument.fromJson(e))
            .toList(),
        query: {'kind': kind.wire, 'targetId': targetId},
      );

  /// A viewer URL carrying a ticket that's good for a few minutes - mint a
  /// fresh one every time the document is opened.
  Future<String> open(String grantId) => _client.post(
        '/documents/$grantId/open',
        (json) => (json as Map<String, dynamic>)['viewerUrl'] as String,
      );
}
