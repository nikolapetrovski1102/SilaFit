import '../../core/api/api_client.dart';
import 'settings_models.dart';

/// Talks to `api/settings` - preferences (units, appearance, reminders),
/// open to any authenticated tier including guests.
class SettingsRepository {
  final ApiClient _client;

  SettingsRepository(this._client);

  Future<UserSettings> getSettings() =>
      _client.get('/settings', UserSettings.fromJson);

  Future<UserSettings> updateSettings(UserSettings settings) => _client.put(
        '/settings',
        UserSettings.fromJson,
        body: settings.toUpdateJson(),
      );
}
