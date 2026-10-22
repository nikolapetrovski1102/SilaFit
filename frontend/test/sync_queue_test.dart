import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/api/api_exception.dart';
import 'package:silafit/core/api/response_cache.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/core/sync/sync_queue.dart';
import 'package:silafit/core/widgets/offline_pill.dart';
import 'package:silafit/features/meals/meal_controller.dart';
import 'package:silafit/features/meals/meal_models.dart';
import 'package:silafit/features/meals/meal_repository.dart';
import 'package:silafit/features/today/active_workout_draft_store.dart';
import 'package:silafit/features/today/today_controller.dart';
import 'package:silafit/features/today/today_models.dart';
import 'package:silafit/features/today/today_repository.dart';

/// A [SessionStore] stand-in whose user can be switched mid-test.
class _FakeSession implements SessionStore {
  String? userId = 'user-1';

  @override
  SilenSession? get current => userId == null
      ? null
      : SilenSession(
          token: 't', userId: userId!, accountTier: AccountTier.registered);

  @override
  String? get currentToken => current?.token;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Answers every request from [respond]; records what was sent.
class _Server {
  final requests = <http.Request>[];
  http.Response Function(http.Request request) respond =
      (_) => http.Response(jsonEncode({'success': true, 'data': null}), 200);
  bool online = true;

  http.Client get client => MockClient((request) async {
        if (!online) throw const SocketException('no route to host');
        requests.add(request);
        return respond(request);
      });

  List<String> get sent => [
        for (final r in requests) '${r.method} ${r.url.path.split('/api').last}'
      ];
}

PendingWrite _write(String kind, String path,
        {String method = 'POST', String? entityId, Map<String, dynamic>? body}) =>
    PendingWrite.create(
        kind: kind,
        method: method,
        path: path,
        entityId: entityId,
        body: body ?? {'n': path});

http.Response _fail(int status, [String message = 'Nope']) => http.Response(
    jsonEncode({'success': false, 'message': message}), status);

void main() {
  late _FakeSession session;
  late _Server server;
  late ApiClient api;
  late Directory cacheDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    session = _FakeSession();
    server = _Server();
    cacheDir = await Directory.systemTemp.createTemp('silen_sync_test');
    api = ApiClient(
        sessionStore: session,
        httpClient: server.client,
        cache: ResponseCache(directory: () async => cacheDir));
  });

  tearDown(() async {
    if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
  });

  group('SyncQueue', () {
    test('uploads queued writes in order and empties', () async {
      final queue = SyncQueue(api);
      await queue.enqueue(_write(SyncQueue.kindBodyweight, '/a'));
      await queue.enqueue(_write(SyncQueue.kindMealUpsert, '/b',
          method: 'PUT', entityId: 'm1'));
      await queue.enqueue(_write(SyncQueue.kindMealDelete, '/c',
          method: 'DELETE', entityId: 'm1'));
      expect(queue.pendingCount.value, 3);

      expect(await queue.flush(), 3);
      expect(server.sent.map((s) => s.split(' ').first),
          ['POST', 'PUT', 'DELETE']);
      expect(server.requests.map((r) => r.url.path.split('/').last),
          ['a', 'b', 'c']);
      expect(queue.pendingCount.value, 0);
      expect(queue.syncedVersion.value, 1);
    });

    test('keeps everything when offline, and survives a restart', () async {
      final queue = SyncQueue(api);
      await queue.enqueue(_write(SyncQueue.kindBodyweight, '/a'));
      server.online = false;
      expect(await queue.flush(), 0);
      expect(queue.pendingCount.value, 1);
      expect(queue.syncedVersion.value, 0);

      // A fresh queue (app restarted) reads it back from disk.
      server.online = true;
      final restarted = SyncQueue(api);
      await restarted.ready();
      expect(restarted.pending.single.path, '/a');
      expect(await restarted.flush(), 1);
      expect(restarted.pending, isEmpty);
    });

    test('a 5xx stops the run without losing or reordering anything',
        () async {
      final queue = SyncQueue(api);
      await queue.enqueue(_write(SyncQueue.kindBodyweight, '/a'));
      await queue.enqueue(_write(SyncQueue.kindBodyweight, '/b'));
      server.respond = (_) => _fail(503);
      expect(await queue.flush(), 0);
      expect(queue.pending.map((w) => w.path), ['/a', '/b']);
      expect(server.requests, hasLength(1));
    });

    test('a write the server chokes on only holds back its own entity',
        () async {
      final queue = SyncQueue(api);
      await queue.enqueue(_write(SyncQueue.kindWorkoutComplete, '/broken',
          entityId: 's1'));
      await queue.enqueue(_write(SyncQueue.kindMealUpsert, '/meal',
          method: 'PUT', entityId: 'm1'));
      await queue.enqueue(_write(SyncQueue.kindMealDelete, '/same-session',
          method: 'DELETE', entityId: 's1'));
      server.respond = (r) => r.url.path.endsWith('/broken')
          ? _fail(500)
          : http.Response(jsonEncode({'success': true}), 200);

      expect(await queue.flush(), 1);
      expect(server.requests.map((r) => r.url.path.split('/').last),
          ['broken', 'meal']);
      expect(queue.pending.map((w) => w.path), ['/broken', '/same-session']);
      expect(queue.pending.first.strikes, 1);
      expect(queue.droppedMessage.value, isNull);

      // The count survives a restart.
      final restarted = SyncQueue(api);
      await restarted.ready();
      expect(restarted.pending.first.strikes, 1);
    });

    test('two 5xx in one run read as the server down - no strikes', () async {
      final queue = SyncQueue(api);
      for (final id in ['a', 'b', 'c']) {
        await queue.enqueue(_write(SyncQueue.kindBodyweight, '/$id',
            entityId: id));
      }
      server.respond = (_) => _fail(503);

      expect(await queue.flush(), 0);
      expect(server.requests, hasLength(2));
      expect(queue.pending, hasLength(3));
      expect(queue.pending.every((w) => w.strikes == 0), isTrue);
      expect(queue.pending.take(2).every((w) => w.serverErrors == 1), isTrue);
    });

    test('a write refused while others get through is dropped in the end',
        () async {
      final queue = SyncQueue(api);
      await queue.enqueue(_write(SyncQueue.kindMealUpsert, '/broken',
          method: 'PUT', entityId: 'm1'));
      server.respond = (r) => r.url.path.endsWith('/broken')
          ? _fail(500, 'Server blew up')
          : http.Response(jsonEncode({'success': true}), 200);

      for (var i = 0; i < SyncQueue.maxStrikes; i++) {
        await queue.enqueue(_write(SyncQueue.kindBodyweight, '/ok$i',
            entityId: 'b$i'));
        await queue.flush();
      }
      expect(queue.pending, isEmpty);
      expect(queue.droppedMessage.value, 'Server blew up');
    });

    test('a 4xx drops just that write and reports it', () async {
      final queue = SyncQueue(api);
      await queue.enqueue(_write(SyncQueue.kindMealUpsert, '/bad',
          method: 'PUT', entityId: 'm1'));
      await queue.enqueue(_write(SyncQueue.kindBodyweight, '/good'));
      server.respond = (r) => r.url.path.endsWith('/bad')
          ? _fail(400, 'Give the meal a name.')
          : http.Response(jsonEncode({'success': true}), 200);

      expect(await queue.flush(), 1);
      expect(queue.pending, isEmpty);
      expect(queue.droppedMessage.value, 'Give the meal a name.');
    });

    test('a newer completion of the same workout replaces the queued one',
        () async {
      final queue = SyncQueue(api);
      await queue.enqueue(_write(SyncQueue.kindWorkoutComplete, '/w',
          entityId: 's1', body: {'v': 1}));
      await queue.enqueue(_write(SyncQueue.kindWorkoutComplete, '/w',
          entityId: 's2', body: {'v': 2}));
      await queue.enqueue(_write(SyncQueue.kindWorkoutComplete, '/w',
          entityId: 's1', body: {'v': 3}));
      expect(queue.pending.map((w) => w.body!['v']), [2, 3]);
    });

    test('queues are per account and clear() forgets them all', () async {
      final queue = SyncQueue(api);
      await queue.enqueue(_write(SyncQueue.kindBodyweight, '/mine'));

      session.userId = 'user-2';
      await queue.ready();
      expect(queue.pending, isEmpty);
      expect(queue.pendingCount.value, 0);

      session.userId = 'user-1';
      await queue.ready();
      expect(queue.pending.single.path, '/mine');

      await queue.clear();
      final restarted = SyncQueue(api);
      await restarted.ready();
      expect(restarted.pending, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('silen.sync_queue.')),
          isEmpty);
    });

    test('does nothing while signed out', () async {
      final queue = SyncQueue(api);
      session.userId = null;
      await queue.enqueue(_write(SyncQueue.kindBodyweight, '/a'));
      expect(await queue.flush(), 0);
      expect(server.requests, isEmpty);
    });

    test('retries by itself once the connection comes back', () async {
      final queue = SyncQueue(api);
      server.online = false;
      queue.start();
      await queue.enqueue(_write(SyncQueue.kindBodyweight, '/a'));
      await queue.flush();
      expect(api.isOffline.value, isTrue);

      server.online = true;
      // Any request getting through flips isOffline back.
      await api.get('/ping', (_) => null);
      for (var i = 0; i < 50 && queue.pendingCount.value > 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(queue.pendingCount.value, 0);
      queue.stop();
    });
  });

  test('ApiException.isRetryable covers network errors and 5xx only', () {
    expect(const ApiException('x', isNetworkError: true).isRetryable, isTrue);
    expect(const ApiException('x', statusCode: 502).isRetryable, isTrue);
    expect(const ApiException('x', statusCode: 400).isRetryable, isFalse);
    expect(const ApiException('x', statusCode: 409).isRetryable, isFalse);
  });

  test('offline pill wording', () {
    expect(OfflinePill.label(offline: false, pending: 0), isNull);
    expect(OfflinePill.label(offline: true, pending: 0),
        'Offline · showing saved data');
    expect(OfflinePill.label(offline: true, pending: 1),
        'Offline · 1 change saved on phone');
    expect(OfflinePill.label(offline: false, pending: 3), 'Syncing 3 changes…');
  });

  group('TodayController offline writes', () {
    TodayDashboard dashboard() => TodayDashboard(
          session: const TodaySession(
            workoutSessionId: 'sess-1',
            title: 'Upper',
            status: 'Scheduled',
            focusLabel: 'CHEST',
            estimatedMinutes: 45,
            isRestDay: false,
          ),
          targetExercises: const [],
          hydrationTotalMl: 0,
          hydrationTargetMl: 0,
          currentStreakDays: 0,
          weeklyCompliancePercent: 0,
          weekStatuses: [
            WeekDayStatus(
                date: DateTime(DateTime.now().year, DateTime.now().month,
                    DateTime.now().day),
                status: 'Scheduled'),
          ],
          latestWeightKg: 80,
        );

    test('a workout finished offline is queued and reads as done', () async {
      final queue = SyncQueue(api);
      final repo = _TodayRepo(api, dashboard);
      final controller = TodayController(repo, syncQueue: queue);
      await controller.load();
      expect(controller.state.data!.session.status, 'Scheduled');

      server.online = false;
      final outcome = await controller.completeWorkout(
          workoutSessionId: 'sess-1', durationMinutes: 40);
      expect(outcome, WorkoutCompletion.savedOffline);
      expect(controller.state.data!.session.status, 'Completed');
      expect(controller.state.data!.weekStatuses.single.status, 'Completed');

      final queued = queue.pending.single;
      expect(queued.kind, SyncQueue.kindWorkoutComplete);
      expect(queued.body!['completedAtUtc'], isNotNull);

      // Reloading (cached/stale server data) still shows it done.
      await controller.load(force: true);
      expect(controller.state.data!.session.status, 'Completed');

      // Back online: it uploads, and Home re-fetches the real thing.
      server.online = true;
      expect(await queue.flush(), 1);
      expect(server.sent.last, 'POST ${TodayRepository.completeWorkoutPath}');
      controller.dispose();
    });

    test('a refused completion is an error, not queued', () async {
      final queue = SyncQueue(api);
      final controller =
          TodayController(_TodayRepo(api, dashboard), syncQueue: queue);
      await controller.load();
      server.respond = (_) => _fail(400, 'That workout is not yours.');
      final outcome = await controller.completeWorkout(
          workoutSessionId: 'sess-1', durationMinutes: 40);
      expect(outcome, WorkoutCompletion.failed);
      expect(controller.actionError, 'That workout is not yours.');
      expect(queue.pending, isEmpty);
      controller.dispose();
    });

    test('a weight logged offline shows as the latest', () async {
      final queue = SyncQueue(api);
      final controller =
          TodayController(_TodayRepo(api, dashboard), syncQueue: queue);
      await controller.load();

      server.online = false;
      expect(await controller.logBodyweight(79.4), isTrue);
      expect(controller.state.data!.latestWeightKg, 79.4);
      expect(controller.state.data!.weightDeltaKg, closeTo(-0.6, 1e-9));
      final body = queue.pending.single.body!;
      expect(body['bodyweightLogId'], isNotNull);
      expect(body['loggedAtUtc'], isNotNull);
      controller.dispose();
    });
  });

  group('Today made up offline (app not opened yet today)', () {
    /// What an earlier day left behind: a dashboard naming the active split
    /// (Day 1 on Monday 2026-01-05, a 7-day rotation) and that split's
    /// detail, every day a training day.
    Future<void> seedEarlierDay({bool withSplitDetail = true}) async {
      await api.updateCached('/today', {
        'session': {
          'workoutSessionId': 'yesterday',
          'status': 'Completed',
          'isRestDay': false
        },
        'targetExercises': const [],
        'currentStreakDays': 4,
        'weeklyCompliancePercent': 50,
        'weekStatuses': const [],
        'latestWeightKg': 80.0,
        'activeSplit': {
          'splitId': 'split-1',
          'name': 'PPL',
          'durationDays': 7,
          'activatedAtUtc': '2026-01-05T00:00:00Z',
        },
      });
      if (!withSplitDetail) return;
      await api.updateCached('/splits/split-1', {
        'split': {'splitId': 'split-1', 'durationDays': 7},
        'days': [
          for (var i = 1; i <= 7; i++)
            {
              'day': {
                'splitDayId': 'day-$i',
                'dayIndex': i,
                'title': 'Day $i',
                'estimatedMinutes': 45,
                'isRestDay': false,
              },
              'exercises': [
                {
                  'exerciseId': 'ex-row',
                  'name': 'Row',
                  'sortOrder': 2,
                  'targetSets': 3,
                  'targetRepsLow': 8,
                  'targetRepsHigh': 10,
                },
                {
                  'exerciseId': 'ex-bench',
                  'name': 'Bench',
                  'sortOrder': 1,
                  'targetSets': 4,
                  'targetRepsLow': 6,
                  'targetRepsHigh': 8,
                },
              ],
            },
        ],
      });
    }

    // Anchored on a Monday with a 7-day rotation, today's UTC weekday is
    // the day number.
    String todaysSplitDayId() => 'day-${DateTime.now().toUtc().weekday}';

    test('builds today\'s session from the saved split', () async {
      await seedEarlierDay();
      final repo = TodayRepository(api);

      final offline = (await repo.getOfflineDashboard())!;
      final session = offline.dashboard.session;
      expect(session.workoutSessionId, repo.offlineSessionId());
      expect(session.status, 'Scheduled');
      expect(session.isRestDay, isFalse);
      expect(offline.splitDayId, todaysSplitDayId());
      expect(offline.dashboard.targetExercises.map((e) => e.name),
          ['Bench', 'Row']);
      expect(offline.dashboard.currentStreakDays, 4);

      // Same account, same day: the same id, so a draft still resumes
      // after the app is killed and reopened offline.
      expect((await repo.getOfflineDashboard())!.dashboard.session
          .workoutSessionId, session.workoutSessionId);
    });

    test('nothing to build from without the split detail', () async {
      await seedEarlierDay(withSplitDetail: false);
      expect(await TodayRepository(api).getOfflineDashboard(), isNull);
    });

    test('a workout on it uploads with its split day, and moves to the real '
        'session when the server answers', () async {
      await seedEarlierDay();
      final queue = SyncQueue(api);
      final repo = _NoTodayYetRepo(api, server);
      final controller = TodayController(repo, syncQueue: queue);
      final offlineId = repo.offlineSessionId()!;

      server.online = false;
      await controller.load();
      expect(controller.state.error, isNull);
      expect(controller.state.data!.session.workoutSessionId, offlineId);

      // A draft saved by the tracker under the made-up id.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('silen.active_workout_draft',
          jsonEncode({'workoutSessionId': offlineId, 'exerciseIndex': 1}));

      final outcome = await controller.completeWorkout(
          workoutSessionId: offlineId, durationMinutes: 40);
      expect(outcome, WorkoutCompletion.savedOffline);
      final body = queue.pending.single.body!;
      expect(body['workoutSessionId'], offlineId);
      expect(body['splitDayId'], todaysSplitDayId());
      final nowUtc = DateTime.now().toUtc();
      expect(
          body['scheduledDateUtc'],
          '${nowUtc.year.toString().padLeft(4, '0')}-'
          '${nowUtc.month.toString().padLeft(2, '0')}-'
          '${nowUtc.day.toString().padLeft(2, '0')}');

      // Signal's back: the server has its own session for today.
      server.online = true;
      await controller.load(force: true);
      final session = controller.state.data!.session;
      expect(session.workoutSessionId, 'sess-real');
      // The queued workout still shows - the server attaches it on upload.
      expect(session.status, 'Completed');
      expect(controller.sessionIdFor(offlineId), 'sess-real');
      expect(
          jsonDecode(prefs.getString('silen.active_workout_draft')!)[
              'workoutSessionId'],
          'sess-real');
      controller.dispose();
    });

    test('rekey leaves a draft for another session alone', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('silen.active_workout_draft',
          jsonEncode({'workoutSessionId': 'other'}));
      await ActiveWorkoutDraftStore.instance.rekey('offline', 'real');
      expect(
          jsonDecode(prefs.getString('silen.active_workout_draft')!)[
              'workoutSessionId'],
          'other');
    });
  });

  group('MealController offline writes', () {
    MealDay day(List<MealLog> meals) => MealDay.fromJson({
          'targets': {
            'targetCalories': 2000,
            'targetProteinG': 150,
            'targetCarbsG': 200,
            'targetFatsG': 60,
          },
          'meals': const [],
          'consumedCalories': 0,
          'remainingCalories': 2000,
          'consumedProteinG': 0,
          'consumedCarbsG': 0,
          'consumedFatsG': 0,
        }).withMeals(meals);

    test('a meal added offline is queued, shown, and counted', () async {
      final queue = SyncQueue(api);
      final repo = _MealRepo(api, () => day(const []));
      final controller = MealController(repo, syncQueue: queue);
      await controller.load();

      server.online = false;
      expect(
          await controller.addMeal(
              mealType: 'Lunch',
              title: 'Rice bowl',
              caloriesKcal: 600,
              proteinG: 40,
              carbsG: 70,
              fatsG: 15),
          isTrue);
      expect(controller.actionError, isNull);
      expect(controller.state.data!.meals.single.title, 'Rice bowl');
      expect(controller.state.data!.consumedCalories, 600);

      final write = queue.pending.single;
      expect(write.method, 'PUT');
      expect(write.path, MealRepository.logPath(write.entityId!));

      // Survives a reload from the stale server copy.
      await controller.load(force: true);
      expect(controller.state.data!.meals.single.title, 'Rice bowl');

      // Deleting it offline removes it from the day too.
      await controller.deleteMeal(write.entityId!);
      expect(controller.state.data!.meals, isEmpty);
      expect(queue.pending.map((w) => w.method), ['PUT', 'DELETE']);
      controller.dispose();
    });

    test('ticking off a planned meal offline keeps its time and foods',
        () async {
      final planned = MealLog(
        mealLogId: 'meal-1',
        logDateUtc: MealRepository.isoDate(DateTime.now()),
        mealType: 'Breakfast',
        title: 'Oats',
        caloriesKcal: 400,
        proteinG: 20,
        carbsG: 60,
        fatsG: 8,
        status: 'Planned',
        plannedLocalTime: '08:30:00',
        items: const [
          MealLogItem(
              name: 'Oats',
              grams: 100,
              caloriesKcal: 400,
              proteinG: 20,
              carbsG: 60,
              fatsG: 8),
        ],
      );
      final queue = SyncQueue(api);
      final controller =
          MealController(_MealRepo(api, () => day([planned])), syncQueue: queue);
      await controller.load();

      server.online = false;
      await controller.logMeal(planned);
      final meal = controller.state.data!.meals.single;
      expect(meal.status, 'Logged');
      expect(meal.plannedLocalTime, '08:30:00');
      expect(meal.items, hasLength(1));
      expect(controller.state.data!.consumedCalories, 400);
      expect(queue.pending.single.body!['plannedLocalTime'], '08:30:00');
      controller.dispose();
    });
  });
}

extension on MealDay {
  MealDay withMeals(List<MealLog> meals) => MealDay(
        targets: targets,
        meals: meals,
        consumedCalories: consumedCalories,
        remainingCalories: remainingCalories,
        consumedProteinG: consumedProteinG,
        consumedCarbsG: consumedCarbsG,
        consumedFatsG: consumedFatsG,
      );
}

/// Serves [build] for reads; writes go through the real repository (and so
/// the test's fake server).
class _TodayRepo extends TodayRepository {
  final TodayDashboard Function() build;
  _TodayRepo(super.client, this.build);

  @override
  Future<TodayDashboard?> getCachedDashboard() async => null;

  @override
  Future<TodayDashboard> getDashboard() async => build();
}

class _MealRepo extends MealRepository {
  final MealDay Function() build;
  _MealRepo(super.client, this.build);

  @override
  Future<MealDay> getDay(DateTime date) async => build();

  @override
  Future<List<MealSuggestion>> getSuggestions({int? month}) async => const [];
}

/// Nothing saved today; the server answers only while [server] is online,
/// with its own session for today.
class _NoTodayYetRepo extends TodayRepository {
  final _Server server;
  _NoTodayYetRepo(super.client, this.server);

  @override
  Future<TodayDashboard?> getCachedDashboard() async => null;

  @override
  Future<TodayDashboard> getDashboard() async {
    if (!server.online) {
      throw const ApiException('Cannot reach the server.',
          isNetworkError: true);
    }
    return const TodayDashboard(
      session: TodaySession(
          workoutSessionId: 'sess-real',
          status: 'Scheduled',
          title: 'Day 1',
          isRestDay: false),
      targetExercises: [],
      hydrationTotalMl: 0,
      hydrationTargetMl: 0,
      currentStreakDays: 4,
      weeklyCompliancePercent: 50,
      weekStatuses: [],
    );
  }
}
