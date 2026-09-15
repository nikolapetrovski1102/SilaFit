import '../../core/api/api_client.dart';

/// Self-service account deletion (Apple/Google in-app deletion requirement)
/// and full "download my data" export - the two endpoints behind
/// Settings' "Export my data" row and its Delete Account flow.
class AccountRepository {
  final ApiClient _client;

  AccountRepository(this._client);

  /// Raw export payload, kept as the untyped JSON the server returns rather
  /// than parsed into models - it's written straight to a file for sharing,
  /// never displayed or edited in the app.
  Future<Map<String, dynamic>> exportData() =>
      _client.get('/account/export', (json) => json as Map<String, dynamic>);

  Future<void> deleteAccount() => _client.delete('/account', (_) => null);
}
