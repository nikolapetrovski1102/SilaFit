import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import '../../core/sync/sync_queue.dart';
import 'active_workout_draft_store.dart';
import 'today_models.dart';
import 'today_repository.dart';

/// How a Finish tap ended - [savedOffline] means it's queued on the phone
/// and will upload by itself once the server is reachable again.
enum WorkoutCompletion { saved, savedOffline, failed }

/// Drives the Today screen end to end: loads the dashboard, and applies
/// optimistic local updates for the two quick-log actions before
/// reconciling with the server response.
class TodayController extends ChangeNotifier {
  final TodayRepository _repository;

  ResourceState<TodayDashboard> state = const ResourceState.loading();
  String? actionError;

  /// Load-once + in-flight guard. The app-wide provider survives screen
  /// remounts (e.g. the theme-change rebuild), so an unconditional `load()`
  /// from a fresh `initState` used to re-fetch a dashboard we already had.
  bool _isLoading = false;

  /// Where writes go when the server can't be reached. Null (tests, and
  /// any caller that doesn't care) means a failed write is just an error.
  final SyncQueue? _syncQueue;

  TodayController(this._repository, {SyncQueue? syncQueue})
      : _syncQueue = syncQueue {
    _syncQueue?.syncedVersion.addListener(_onSynced);
  }

  bool _disposed = false;

  /// Set while the dashboard on screen is today's session made up on the
  /// phone ([TodayRepository.getOfflineDashboard]) - finishing that workout
  /// has to tell the server which split day it was.
  OfflineToday? _offlineToday;

  /// A session id the phone made up offline -> the id the server gave
  /// today's session once it answered. A tracker opened on the made-up id
  /// goes through [sessionIdFor] so its draft and its Finish land on the
  /// real session.
  final Map<String, String> _sessionIdRemap = {};

  /// The id to use for [workoutSessionId] now - the server's, if it has
  /// since replaced one the phone made up.
  String sessionIdFor(String workoutSessionId) =>
      _sessionIdRemap[workoutSessionId] ?? workoutSessionId;

  @override
  void dispose() {
    _disposed = true;
    _syncQueue?.syncedVersion.removeListener(_onSynced);
    super.dispose();
  }

  /// A load started by a sync can finish after sign-out has torn this
  /// controller down - its result just has nowhere to go.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// Queued writes just reached the server - swap the locally patched
  /// dashboard for the real one.
  void _onSynced() {
    if (state.hasData) load(force: true);
  }

  /// [force] is for the explicit paths - pull-to-refresh, retry, or a write
  /// that just changed the dashboard - which must re-fetch even when data is
  /// already present.
  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && state.hasData) return;
    _isLoading = true;

    // Only drop to the loading spinner on the very first load, when there's
    // no dashboard to show yet. On a pull-to-refresh, `state` already has
    // data - keep showing it while refetching instead of wiping it to
    // `loading()`. Doing that swaps ResourceBuilder over to a differently-
    // shaped widget for a beat, which tears down FitHeight's element (and
    // the fitted scale it had already settled on) and remounts it fresh
    // once the new dashboard lands - visible as a one-frame flash at the
    // wrong scale, with dead space where the old, correctly-scaled content
    // used to be. RefreshIndicator's own spinner already communicates
    // "refreshing"; the body doesn't need to blank out too.
    if (!state.hasData) {
      // Paint today's last saved dashboard straight away when there is one -
      // in a gym with patchy signal that's the difference between "Continue
      // Workout" now and a skeleton until the request times out. The fetch
      // below still runs and replaces it.
      // Nothing saved today: build today's session from the active split
      // saved on an earlier day, so a lifter who first opens the app in a
      // gym with no signal can still train. Replaced by the server's answer
      // as soon as there is one.
      final cached = await _repository.getCachedDashboard();
      final offline =
          cached == null ? await _repository.getOfflineDashboard() : null;
      _offlineToday = offline;
      final paint = cached ?? offline?.dashboard;
      state = paint != null
          ? ResourceState.data(await _withPendingWrites(paint))
          : const ResourceState.loading();
      notifyListeners();
    }
    try {
      final dashboard = await _repository.getDashboard();
      await _adoptServerSession(dashboard);
      state = ResourceState.data(await _withPendingWrites(dashboard));
    } on ApiException catch (e) {
      // Still offline with a session built on the phone: keep showing it
      // like a saved copy (the offline pill says so) rather than an error.
      state = e.isRetryable && _offlineToday != null && state.hasData
          ? ResourceState.data(state.data!)
          : ResourceState.error(e.userMessage, staleData: state.data);
    } catch (_) {
      state = ResourceState.error(ApiException.genericMessage,
          staleData: state.data);
    } finally {
      _isLoading = false;
    }
    notifyListeners();
  }

  Future<void> logHydration(int amountMl) async {
    final current = state.data;
    if (current == null) return;

    // Optimistic bump so the UI feels instant, per the mockup's micro-interaction.
    state = ResourceState.data(current.copyWith(
        hydrationTotalMl: current.hydrationTotalMl + amountMl));
    notifyListeners();

    try {
      final total = await _repository.logHydration(amountMl);
      state = ResourceState.data(state.data!.copyWith(hydrationTotalMl: total));
    } on ApiException catch (e) {
      state = ResourceState.data(current); // roll back
      actionError = e.userMessage;
    } catch (_) {
      state = ResourceState.data(current);
      actionError = ApiException.genericMessage;
    }
    notifyListeners();
  }

  /// The server has answered with today's real session. If the phone had
  /// made one up offline, point its id at the real one and move any workout
  /// draft across, so sets logged before the signal came back aren't lost.
  Future<void> _adoptServerSession(TodayDashboard dashboard) async {
    _offlineToday = null;
    final realId = dashboard.session.workoutSessionId;
    final offlineId = _repository.offlineSessionId();
    if (realId == null || offlineId == null || realId == offlineId) return;
    _sessionIdRemap[offlineId] = realId;
    try {
      await ActiveWorkoutDraftStore.instance.rekey(offlineId, realId);
    } catch (_) {}
  }

  /// Writes still waiting in the offline queue, laid over [dashboard] - which
  /// (served from the server or its saved copy) can't include them yet. A
  /// workout finished offline must read as done on Home, not offer "Start
  /// Workout" again, and a weight logged offline must show as the latest.
  Future<TodayDashboard> _withPendingWrites(TodayDashboard dashboard) async {
    final queue = _syncQueue;
    if (queue == null) return dashboard;
    await queue.ready();
    var result = dashboard;

    final sessionId = dashboard.session.workoutSessionId;
    // A workout finished on a session the phone made up counts for today's
    // real session too - the server attaches it there on upload.
    final offlineId = _repository.offlineSessionId();
    final workoutQueued = sessionId != null &&
        queue.pending.any((w) =>
            w.kind == SyncQueue.kindWorkoutComplete &&
            (w.entityId == sessionId || w.entityId == offlineId));
    if (workoutQueued) result = _markCompleted(result);

    final weights = [
      for (final w in queue.pending)
        if (w.kind == SyncQueue.kindBodyweight)
          (w.body?['weightKg'] as num?)?.toDouble()
    ].whereType<double>().toList();
    if (weights.isNotEmpty) {
      final previous = weights.length > 1
          ? weights[weights.length - 2]
          : dashboard.latestWeightKg;
      result = result.copyWith(
          latestWeightKg: weights.last,
          weightDeltaKg: previous == null ? null : weights.last - previous);
    }
    return result;
  }

  /// Today's session (and today's slot in the week strip) as Completed.
  static TodayDashboard _markCompleted(TodayDashboard dashboard) {
    final now = DateTime.now();
    return dashboard.copyWith(
      session: dashboard.session.copyWith(status: 'Completed'),
      weekStatuses: [
        for (final day in dashboard.weekStatuses)
          day.date.year == now.year &&
                  day.date.month == now.month &&
                  day.date.day == now.day
              ? WeekDayStatus(date: day.date, status: 'Completed')
              : day,
      ],
    );
  }

  Future<bool> logBodyweight(double weightKg) async {
    final current = state.data;
    if (current == null) return false;
    // The id goes with the entry from the start, so if this request times
    // out after the server stored it, the queued retry is a no-op.
    final body = TodayRepository.bodyweightBody(
        weightKg: weightKg,
        entryId: const Uuid().v4(),
        loggedAtUtc: DateTime.now().toUtc());
    try {
      final result = await _repository.logBodyweight(body);
      state = ResourceState.data(current.copyWith(
          latestWeightKg: result.latestWeightKg,
          weightDeltaKg: result.deltaKg));
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      final queue = _syncQueue;
      if (e.isRetryable && queue != null) {
        await queue.enqueue(PendingWrite.create(
          kind: SyncQueue.kindBodyweight,
          method: 'POST',
          path: TodayRepository.bodyweightPath,
          body: body,
          entityId: body['bodyweightLogId'] as String,
        ));
        state = ResourceState.data(await _withPendingWrites(current));
        notifyListeners();
        return true;
      }
      actionError = e.userMessage;
    } catch (_) {
      actionError = ApiException.genericMessage;
    }
    notifyListeners();
    return false;
  }

  /// Submits a finished workout. With no signal it's queued on the phone
  /// instead ([WorkoutCompletion.savedOffline]) and Home shows it done right
  /// away - the queue uploads it, with the time it really ended, once the
  /// server can be reached.
  Future<WorkoutCompletion> completeWorkout({
    required String workoutSessionId,
    required int durationMinutes,
    int? caloriesEstimate,
    double? rpeScore,
    double? tonnageKg,
    List<SetLogEntry>? setLogs,
  }) async {
    workoutSessionId = sessionIdFor(workoutSessionId);
    final offline = _offlineToday;
    final madeUpOffline = offline != null &&
        offline.dashboard.session.workoutSessionId == workoutSessionId;
    final body = TodayRepository.completeWorkoutBody(
      workoutSessionId: workoutSessionId,
      splitDayId: madeUpOffline ? offline.splitDayId : null,
      scheduledDateUtc: madeUpOffline ? offline.scheduledDateUtc : null,
      durationMinutes: durationMinutes,
      completedAtUtc: DateTime.now().toUtc(),
      caloriesEstimate: caloriesEstimate,
      rpeScore: rpeScore,
      tonnageKg: tonnageKg,
      setLogs: setLogs,
    );
    try {
      await _repository.completeWorkout(body);
      await load(force: true);
      return WorkoutCompletion.saved;
    } on ApiException catch (e) {
      final queue = _syncQueue;
      if (e.isRetryable && queue != null) {
        await queue.enqueue(PendingWrite.create(
          kind: SyncQueue.kindWorkoutComplete,
          method: 'POST',
          path: TodayRepository.completeWorkoutPath,
          body: body,
          entityId: workoutSessionId,
        ));
        final current = state.data;
        if (current != null &&
            current.session.workoutSessionId == workoutSessionId) {
          state = ResourceState.data(_markCompleted(current));
        }
        notifyListeners();
        return WorkoutCompletion.savedOffline;
      }
      actionError = e.userMessage;
    } catch (_) {
      actionError = ApiException.genericMessage;
    }
    notifyListeners();
    return WorkoutCompletion.failed;
  }
}
