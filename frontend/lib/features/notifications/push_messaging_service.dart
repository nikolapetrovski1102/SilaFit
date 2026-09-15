import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/platform/device_timezone.dart';
import 'notifications_repository.dart';

/// The device half of the push pipeline: it turns the OS notification
/// permission into an FCM registration token stored on the server, and keeps
/// that token fresh afterwards.
///
/// Every method is best-effort and swallows its own errors. Push is an
/// enhancement, so a build with no Firebase app configured (no
/// `android/app/google-services.json` / `ios/.../GoogleService-Info.plist`)
/// must degrade to "no token stored" - exactly the behaviour the pipeline had
/// before - rather than break onboarding, login, or sign-out.
class PushMessagingService {
  final NotificationsRepository _repository;

  PushMessagingService(this._repository);

  bool _initialized = false;
  bool _available = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _cachedToken;

  /// True once Firebase booted and a messaging instance is usable on this
  /// device (i.e. the platform config files above are present).
  bool get isAvailable => _available;

  /// Boots Firebase once and subscribes to token rotation. Safe to call from
  /// anywhere and to call repeatedly; later calls are no-ops.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _available = true;
      // A rotated token must reach the server, or the next reminder is
      // addressed to a dead token and the user silently stops getting pushes.
      _tokenRefreshSubscription =
          FirebaseMessaging.instance.onTokenRefresh.listen(
        (token) {
          _cachedToken = token;
          unawaited(_registerToken(token));
        },
        onError: (Object error) =>
            debugPrint('FCM token refresh stream error: $error'),
      );
    } catch (error) {
      debugPrint('Push messaging unavailable (is Firebase configured?): $error');
      _available = false;
    }
  }

  /// Requests the OS notification permission (idempotent once answered) and
  /// returns the FCM token that should be stored, or null when push is
  /// unavailable or the user did not allow notifications.
  ///
  /// Returns the token instead of storing it so the caller can register the
  /// token, timezone, and opt-in in a single request.
  Future<String?> requestToken() async {
    await initialize();
    if (!_available) return null;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (!_permissionGranted(settings.authorizationStatus)) return null;
      final token = await FirebaseMessaging.instance.getToken();
      _cachedToken = token;
      return token;
    } catch (error) {
      debugPrint('Could not obtain an FCM token: $error');
      return null;
    }
  }

  /// Re-stores the current token without prompting - used on cold start/resume
  /// so a token that rotated while the app was closed still lands on the
  /// server. No-op when push is unavailable or permission was never granted.
  Future<void> syncToken() async {
    await initialize();
    if (!_available) return;
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (!_permissionGranted(settings.authorizationStatus)) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      _cachedToken = token;
      await _registerToken(token);
    } catch (error) {
      debugPrint('Could not refresh the FCM token: $error');
    }
  }

  /// Removes this device from push delivery (sign-out / account deletion).
  /// Best-effort: a failure here only means the server keeps a token that FCM
  /// will eventually report as unregistered anyway.
  Future<void> deactivate() async {
    try {
      await initialize();
      if (!_available) return;
      final token = _cachedToken ?? await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      _cachedToken = null;
      await _repository.deactivateDeviceToken(token);
    } catch (error) {
      debugPrint('Could not deactivate the FCM token: $error');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await _repository.registerDeviceToken(
        token: token,
        platform: devicePlatform(),
        timeZoneId: deviceTimeZoneId(),
      );
    } catch (error) {
      debugPrint('Could not store the FCM token: $error');
    }
  }

  /// FCM reports both `authorized` and `provisional` (iOS quiet notifications)
  /// as "notifications may be shown"; anything else means no token should be
  /// registered.
  static bool _permissionGranted(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  /// Cancels the token-refresh subscription. The service is app-scoped, so
  /// this is only needed when a test tears one down.
  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }
}
