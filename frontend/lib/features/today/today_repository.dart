import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../splits/splits_models.dart';
import 'today_models.dart';
import 'widgets/day_preview.dart';

/// Today's dashboard worked out on the phone, with no answer from the
/// server - see [TodayRepository.getOfflineDashboard]. [splitDayId] and
/// [scheduledDateUtc] go with the workout when it's finished, so the server
/// can create the session it never got to.
class OfflineToday {
  final TodayDashboard dashboard;
  final String? splitDayId;
  final DateTime scheduledDateUtc;

  const OfflineToday(this.dashboard, this.splitDayId, this.scheduledDateUtc);
}

/// Talks to `api/today/*` - the one fully-wired vertical slice.
class TodayRepository {
  final ApiClient _client;

  TodayRepository(this._client);

  Future<TodayDashboard> getDashboard() =>
      _client.get('/today', TodayDashboard.fromJson,
          cache: true, sameDayOnly: true);

  /// Today's dashboard as last saved on this device (same-day only), for an
  /// instant paint before [getDashboard] answers - see [ApiClient.cached].
  Future<TodayDashboard?> getCachedDashboard() async =>
      (await _client.cached('/today', TodayDashboard.fromJson,
              sameDayOnly: true))
          ?.value;

  /// The id the phone gives today's session when it has to make it up
  /// offline. Derived from the account and the (UTC) day rather than random,
  /// so an app killed and reopened in the same dead zone hands out the same
  /// id again and the workout draft saved under it still resumes.
  String? offlineSessionId([DateTime? nowUtc]) {
    final userId = _client.sessionStore.current?.userId;
    if (userId == null) return null;
    final day = DateFormat('yyyy-MM-dd').format((nowUtc ?? DateTime.now()).toUtc());
    return const Uuid()
        .v5(Namespace.url.value, 'silen:offline-session:$userId:$day');
  }

  /// Today's session built on the phone, for when the server can't be
  /// reached and nothing was saved today - the lifter who opens the app for
  /// the first time that day in a basement gym. Uses the last dashboard
  /// saved on any day (for the active split) and that split's saved detail,
  /// resolving today's split day the way `usp_WorkoutSession_GetTodayScheduled`
  /// does. Null when either was never saved or there's no active split.
  Future<OfflineToday?> getOfflineDashboard() async {
    final last = (await _client.cached('/today', TodayDashboard.fromJson))
        ?.value;
    final split = last?.activeSplit;
    if (last == null || split == null) return null;
    final detail = (await _client.cached(
            '/splits/${split.splitId}', SplitDetail.fromJson))
        ?.value;
    final sessionId = offlineSessionId();
    if (detail == null || sessionId == null) return null;

    // The server schedules by UTC date - resolve the same day it would.
    final nowUtc = DateTime.now().toUtc();
    final todayUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final resolved = resolveSplitDayWithExercises(todayUtc, split, detail);
    if (resolved == null) return null;
    final day = resolved.day;
    final isRest = day.isRestDay || day.splitDayId.isEmpty;
    final exercises = List.of(resolved.exercises)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return OfflineToday(
      TodayDashboard(
        session: TodaySession(
          workoutSessionId: isRest ? null : sessionId,
          status: 'Scheduled',
          title: isRest ? null : day.title,
          focusLabel: isRest ? null : day.focusLabel,
          estimatedMinutes: isRest ? null : day.estimatedMinutes,
          isRestDay: isRest,
        ),
        targetExercises: isRest
            ? const []
            : [
                for (final e in exercises)
                  TargetExercise(
                    exerciseId: e.exerciseId,
                    name: e.name,
                    muscleGroup: e.muscleGroup,
                    targetSets: e.targetSets,
                    targetRepsLow: e.targetRepsLow,
                    targetRepsHigh: e.targetRepsHigh,
                  ),
              ],
        hydrationTotalMl: 0,
        hydrationTargetMl: last.hydrationTargetMl,
        latestWeightKg: last.latestWeightKg,
        weightDeltaKg: last.weightDeltaKg,
        currentStreakDays: last.currentStreakDays,
        weeklyCompliancePercent: last.weeklyCompliancePercent,
        weekStatuses: last.weekStatuses,
        activeSplit: split,
      ),
      isRest ? null : day.splitDayId,
      todayUtc,
    );
  }

  /// Returns the new running total in ml.
  Future<int> logHydration(int amountMl) => _client.post(
        '/today/hydration',
        (json) => json as int,
        body: {'amountMl': amountMl},
      );

  static const bodyweightPath = '/today/bodyweight';
  static const completeWorkoutPath = '/today/workout/complete';

  /// [entryId] (client-generated) and [loggedAtUtc] let the same entry be
  /// re-sent from the offline queue without being stored twice.
  static Map<String, dynamic> bodyweightBody(
          {required double weightKg,
          required String entryId,
          required DateTime loggedAtUtc}) =>
      {
        'weightKg': weightKg,
        'bodyweightLogId': entryId,
        'loggedAtUtc': loggedAtUtc.toUtc().toIso8601String(),
      };

  Future<BodyweightLogResult> logBodyweight(Map<String, dynamic> body) =>
      _client.post(bodyweightPath, BodyweightLogResult.fromJson,
          body: body, timeout: queuedWriteTimeout);

  /// [completedAtUtc] is when the lifter actually finished - the same body
  /// may be uploaded much later from the offline queue. [splitDayId] and
  /// [scheduledDateUtc] are only for a session made up offline (see
  /// [OfflineToday]).
  static Map<String, dynamic> completeWorkoutBody({
    required String workoutSessionId,
    required int durationMinutes,
    required DateTime completedAtUtc,
    int? caloriesEstimate,
    double? rpeScore,
    double? tonnageKg,
    List<SetLogEntry>? setLogs,
    String? splitDayId,
    DateTime? scheduledDateUtc,
  }) =>
      {
        'workoutSessionId': workoutSessionId,
        'durationMinutes': durationMinutes,
        'completedAtUtc': completedAtUtc.toUtc().toIso8601String(),
        if (caloriesEstimate != null) 'caloriesEstimate': caloriesEstimate,
        if (rpeScore != null) 'rpeScore': rpeScore,
        if (tonnageKg != null) 'tonnageKg': tonnageKg,
        if (setLogs != null && setLogs.isNotEmpty)
          'setLogs': setLogs.map((s) => s.toJson()).toList(),
        if (splitDayId != null) 'splitDayId': splitDayId,
        if (scheduledDateUtc != null)
          'scheduledDateUtc': DateFormat('yyyy-MM-dd').format(scheduledDateUtc),
      };

  Future<void> completeWorkout(Map<String, dynamic> body) =>
      _client.post(completeWorkoutPath, (_) => null,
          body: body, timeout: queuedWriteTimeout);

  /// Every set logged for the session scheduled on [date] - powers Home's
  /// "View set history" button on a completed past day.
  Future<List<SetLogHistoryEntry>> getWorkoutHistory(DateTime date) =>
      _client.get(
        '/today/workout/history',
        (json) => (json as List<dynamic>)
            .map((e) => SetLogHistoryEntry.fromJson(e))
            .toList(),
        query: {'date': DateFormat('yyyy-MM-dd').format(date)},
        cache: true,
      );

  /// Every set ever logged for [exerciseId], most recent session first -
  /// powers the Active Workout Tracker's gated "Last time" card. PRO/
  /// Advanced only; throws [ApiException] with status 403 otherwise.
  Future<List<SetLogHistoryEntry>> getExerciseHistory(String exerciseId) =>
      _client.get(
        '/today/exercises/$exerciseId/history',
        (json) => (json as List<dynamic>)
            .map((e) => SetLogHistoryEntry.fromJson(e))
            .toList(),
        cache: true,
      );
}
