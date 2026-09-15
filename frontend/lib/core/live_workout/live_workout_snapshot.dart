/// Immutable description of the one in-progress workout session that the
/// OS-level "live" surface should display - the iOS Live Activity / Dynamic
/// Island card, and the Android ongoing foreground-service notification.
///
/// Deliberately primitive-only: every field maps cleanly onto ActivityKit's
/// `Codable` `ContentState` and onto Android Intent extras, so the platform
/// channel never has to agree on anything richer than numbers and strings.
///
/// The elapsed clock is *not* a field. Both native sides compute it from
/// [startedAtEpochMs] and tick it in place (a SwiftUI `Text(timerInterval:)`
/// on iOS, an Android `Chronometer`), so it stays correct and live even while
/// the Flutter isolate is suspended or the app is closed.
class LiveWorkoutSnapshot {
  const LiveWorkoutSnapshot({
    required this.sessionId,
    required this.exerciseName,
    required this.exerciseNumber,
    required this.exerciseCount,
    required this.completedSets,
    required this.totalSets,
    required this.startedAtUtc,
  });

  final String sessionId;
  final String exerciseName;

  /// 1-based position of the current exercise within the session.
  final int exerciseNumber;
  final int exerciseCount;

  /// Completed vs. total sets *for the current exercise* - the same numbers
  /// `ActiveWorkoutTrackerScreen` shows in its set ring.
  final int completedSets;
  final int totalSets;

  /// Wall-clock start of the session, in UTC. Native converts this to an
  /// absolute epoch so the timer survives process death and screen-off.
  final DateTime startedAtUtc;

  /// Sets still to log in the current exercise, clamped at zero so a
  /// removed set can never surface a negative count on the lock screen.
  int get remainingSets {
    final remaining = totalSets - completedSets;
    return remaining < 0 ? 0 : remaining;
  }

  /// Wire shape for the `MethodChannel`. Epoch milliseconds (not an ISO
  /// string) so Java/Kotlin can consume it without parsing, and a flat map so
  /// Swift can read it straight out of `FlutterMethodCall.arguments`.
  Map<String, dynamic> toChannelMap() => <String, dynamic>{
        'sessionId': sessionId,
        'exerciseName': exerciseName,
        'exerciseNumber': exerciseNumber,
        'exerciseCount': exerciseCount,
        'completedSets': completedSets,
        'totalSets': totalSets,
        'remainingSets': remainingSets,
        'startedAtEpochMs': startedAtUtc.millisecondsSinceEpoch,
      };
}
