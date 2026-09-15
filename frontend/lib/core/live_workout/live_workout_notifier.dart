import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

import 'live_workout_snapshot.dart';

/// Dart bridge to the native live-workout surfaces:
///
/// * **iOS** - an `ActivityKit` Live Activity (Lock Screen banner + Dynamic
///   Island), driven by `WorkoutLiveActivityPlugin.swift` in the app target
///   and rendered by the `SilaFitLiveActivity` widget extension.
/// * **Android** - an ongoing foreground-service notification
///   (`WorkoutLiveService.kt`) rendered from a custom `RemoteViews` layout
///   with a native `Chronometer` and a "Log set" action button.
///
/// One channel, one snapshot shape, two native implementations. Every call is
/// best-effort: a platform with no handler (web, desktop, or a build produced
/// before the native side landed) simply no-ops, because a live surface
/// failing must never take the workout screen down with it.
///
/// ## "Log set" from the surface
///
/// Neither platform can call back into a suspended Flutter isolate the instant
/// the surface's button is tapped: on iOS the button runs in the widget
/// extension's own process, and on Android it is a plain broadcast with no
/// `FlutterEngine` reference. Both sides therefore:
///
/// 1. update the *visible* surface immediately (so the set counter and timer
///    refresh on the Lock Screen / in the shade without the app in the
///    foreground), and
/// 2. record the tap for [drainLoggedSets] to replay later.
///
/// The tracker screen drains on resume, on every ticker tick, and before
/// finishing, so a tap made while the app was backgrounded still persists the
/// corresponding set exactly once.
class LiveWorkoutNotifier {
  LiveWorkoutNotifier._();
  static final LiveWorkoutNotifier instance = LiveWorkoutNotifier._();

  static const MethodChannel _channel =
      MethodChannel('com.nikolapetrovski.silafit/live_workout');

  /// Whether the current platform has a native live-workout surface. Uses
  /// [defaultTargetPlatform] rather than `dart:io`'s `Platform` so this file
  /// stays safe to compile for web, matching `permission_handler`'s own
  /// platform guards elsewhere in the app.
  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Starts (or refreshes) the live surface for [snapshot]. Idempotent on both
  /// platforms - calling it while one is already showing updates it in place
  /// instead of stacking a second one.
  Future<void> start(LiveWorkoutSnapshot snapshot) async {
    if (!isSupported) return;
    await _invoke('start', snapshot.toChannelMap());
  }

  /// Pushes new exercise/set state into an already-visible live surface. The
  /// native side ignores this if no surface is showing, so callers don't have
  /// to track whether [start] succeeded.
  Future<void> update(LiveWorkoutSnapshot snapshot) async {
    if (!isSupported) return;
    await _invoke('update', snapshot.toChannelMap());
  }

  /// Dismisses the live surface - called when a session is finished, left, or
  /// otherwise no longer in progress.
  Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // Best-effort, same contract as [_invoke].
    }
  }

  /// Claims every "Log set" tap the native live surface recorded for
  /// [sessionId] since the last drain, returning how many sets to replay.
  ///
  /// Bounded and idempotent: each native side atomically reads-and-clears its
  /// pending count, so the same tap is never replayed twice, and a launch
  /// where the surface never showed simply returns 0.
  Future<int> drainLoggedSets(String sessionId) async {
    if (!isSupported || sessionId.isEmpty) return 0;
    try {
      final count = await _channel.invokeMethod<int>(
        'drainLoggedSets',
        {'sessionId': sessionId},
      );
      return count ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  Future<void> _invoke(String method, Map<String, dynamic> arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // No native handler in this build - nothing to keep alive.
    } on PlatformException {
      // Swallowed on purpose: see the class doc.
    }
  }
}
