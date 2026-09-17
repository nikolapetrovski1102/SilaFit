import '../../core/api/api_client.dart';

/// Self-service account deletion (Apple/Google in-app deletion requirement)
/// and full "download my data" export - the two endpoints behind
/// Settings' "Export my data" row and its Delete Account flow.
class AccountRepository {
  final ApiClient _client;

  AccountRepository(this._client);

  /// Triggers the server to email the full data export to the account's
  /// address; returns that address so the UI can confirm where it went.
  Future<String> exportData() => _client.post(
      '/account/export', (json) => (json as Map<String, dynamic>)['email'] as String);

  Future<void> deleteAccount() => _client.delete('/account', (_) => null);
}
