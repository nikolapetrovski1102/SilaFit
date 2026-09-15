import '../../core/api/api_client.dart';
import '../../core/platform/device_timezone.dart';

/// Talks to `api/notifications` - the client half of the push reminder
/// pipeline: registering the device token + timezone captured at onboarding,
/// and telling the server "the user is here" so the quiet-then-comeback backoff
/// can measure real engagement.
class NotificationsRepository {
  final ApiClient _client;

  NotificationsRepository(this._client);

  /// Registers (or refreshes) the push token and the timezone/opt-in that go
  /// with it. Every field is optional: call it on permission grant with just
  /// the timezone, then again once FCM hands back a token.
  Future<void> registerDeviceToken({
    String? token,
    String? platform,
    String? timeZoneId,
    bool? notificationsEnabled,
  }) =>
      _post('/notifications/device-token', {
        if (token != null) 'token': token,
        'platform': platform ?? devicePlatform(),
        if (timeZoneId != null) 'timeZoneId': timeZoneId,
        if (notificationsEnabled != null) 'notificationsEnabled': notificationsEnabled,
      });

  Future<void> deactivateDeviceToken(String token) => _client.delete<void>(
        '/notifications/device-token',
        (_) {},
        body: {'token': token},
      );

  /// Sent on cold start / resume, and when a notification is tapped. Also
  /// carries the current timezone so a zone change is picked up even without
  /// re-running onboarding.
  Future<void> recordInteraction({String? timeZoneId, String? notificationId}) =>
      _post('/notifications/interaction', {
        if (timeZoneId != null) 'timeZoneId': timeZoneId,
        if (notificationId != null) 'notificationId': notificationId,
      });

  /// "Still in the gym" ping while a workout is open - lets the server time a
  /// "log your sets" nudge around actual idle time.
  Future<void> sendWorkoutHeartbeat({String? workoutSessionId}) =>
      _post('/notifications/workout-heartbeat', {
        if (workoutSessionId != null) 'workoutSessionId': workoutSessionId,
      });

  Future<void> _post(String path, Map<String, dynamic> body) =>
      _client.post<void>(path, (_) {}, body: body);
}
