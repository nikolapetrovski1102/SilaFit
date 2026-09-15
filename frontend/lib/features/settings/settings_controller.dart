import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/platform/device_timezone.dart';
import '../../core/session/session_store.dart';
import '../../core/state/resource_state.dart';
import 'settings_models.dart';
import 'settings_repository.dart';

/// Drives the Settings screen: loads preferences, and applies optimistic
/// local updates for every toggle/picker before reconciling with the server
/// response - same pattern as `TodayController`'s hydration quick-log.
///
/// Also mirrors the resolved appearance mode into [SessionStore]'s
/// synchronous cache on every successful load/update, so the next cold
/// start can paint the right theme before this controller's own network
/// call has a chance to resolve.
class SettingsController extends ChangeNotifier {
  final SettingsRepository _repository;
  final SessionStore _sessionStore;

  ResourceState<UserSettings> state = const ResourceState.loading();
  String? actionError;

  SettingsController(this._repository, this._sessionStore);

  // Guards the cold-start + Settings-screen double-trigger and retry spam.
  bool _isLoading = false;

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && state.hasData) return;
    _isLoading = true;
    state = const ResourceState.loading();
    notifyListeners();
    try {
      final settings = await _repository.getSettings();
      state = ResourceState.data(settings);
      unawaited(_sessionStore.cacheAppearanceMode(settings.appearanceMode));
    } on ApiException catch (e) {
      state = ResourceState.error(e.userMessage);
    } catch (_) {
      state = const ResourceState.error(ApiException.genericMessage);
    } finally {
      _isLoading = false;
    }
    notifyListeners();
  }

  Future<void> _update(UserSettings Function(UserSettings current) transform) async {
    final previous = state.data;
    if (previous == null) return;

    final optimistic = transform(previous);
    state = ResourceState.data(optimistic);
    if (optimistic.appearanceMode != previous.appearanceMode) {
      unawaited(_sessionStore.cacheAppearanceMode(optimistic.appearanceMode));
    }
    notifyListeners();

    try {
      final result = await _repository.updateSettings(optimistic);
      state = ResourceState.data(result);
      unawaited(_sessionStore.cacheAppearanceMode(result.appearanceMode));
    } on ApiException catch (e) {
      state = ResourceState.data(previous);
      actionError = e.userMessage;
      unawaited(_sessionStore.cacheAppearanceMode(previous.appearanceMode));
    } catch (_) {
      state = ResourceState.data(previous);
      actionError = ApiException.genericMessage;
      unawaited(_sessionStore.cacheAppearanceMode(previous.appearanceMode));
    }
    notifyListeners();
  }

  Future<void> setAppearanceMode(String mode) =>
      _update((s) => s.copyWith(appearanceMode: mode));

  Future<void> setWeightUnit(String unit) =>
      _update((s) => s.copyWith(weightUnit: unit));

  Future<void> setDistanceUnit(String unit) =>
      _update((s) => s.copyWith(distanceUnit: unit));

  Future<void> setRestTimerSoundEnabled(bool value) =>
      _update((s) => s.copyWith(restTimerSoundEnabled: value));

  Future<void> setBarbellStandardKg(double value) =>
      _update((s) => s.copyWith(barbellStandardKg: value));

  // Turning reminders on also refreshes the stored timezone from the device,
  // so they keep landing on the user's clock even if they skipped onboarding or
  // the device has since changed zones.
  Future<void> setNotificationsEnabled(bool value) => _update((s) => s.copyWith(
        notificationsEnabled: value,
        timeZoneId: value ? deviceTimeZoneId() : s.timeZoneId,
      ));

  Future<void> setNotificationLocalTime(String value) =>
      _update((s) => s.copyWith(notificationLocalTime: value));
}
