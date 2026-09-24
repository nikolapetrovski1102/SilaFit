import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/features/auth/auth_controller.dart';
import 'package:silafit/features/plans/iap_service.dart';
import 'package:silafit/features/plans/plans_controller.dart';
import 'package:silafit/features/plans/plans_repository.dart';
import 'package:silafit/features/progress/analytics_repository.dart';
import 'package:silafit/features/splits/splits_repository.dart';
import 'package:silafit/features/today/today_controller.dart';
import 'package:silafit/features/today/today_models.dart';
import 'package:silafit/features/today/today_repository.dart';
import 'package:silafit/features/today/today_screen.dart';
import 'package:silafit/features/today/widgets/active_split_card.dart';
import 'package:silafit/features/today/widgets/ai_insights_teaser_card.dart';

class _FakeAuth extends ChangeNotifier implements AuthController {
  @override
  get session => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlans extends PlansRepository {
  _FakePlans() : super(ApiClient(sessionStore: SessionStore()));
  @override
  Future<String> getActivePlanCode() async => 'PRO';
}

class _FakeAnalytics extends AnalyticsRepository {
  _FakeAnalytics() : super(ApiClient(sessionStore: SessionStore()));
}

class _FakeSplits extends SplitsRepository {
  _FakeSplits() : super(ApiClient(sessionStore: SessionStore()));
}

class _FakeTodayRepo extends TodayRepository {
  _FakeTodayRepo() : super(ApiClient(sessionStore: SessionStore()));

  @override
  Future<TodayDashboard> getDashboard() async {
    return TodayDashboard(
      session: const TodaySession(
        workoutSessionId: 'sess-1',
        title: 'Upper Body Power',
        status: 'Scheduled',
        focusLabel: 'CHEST & BACK',
        estimatedMinutes: 45,
        isRestDay: false,
      ),
      targetExercises: [],
      hydrationTotalMl: 1200,
      hydrationTargetMl: 2500,
      currentStreakDays: 5,
      weeklyCompliancePercent: 85,
      weekStatuses: [
        WeekDayStatus(
          date: DateTime(
              DateTime.now().year, DateTime.now().month, DateTime.now().day),
          status: 'Scheduled',
        ),
      ],
      activeSplit: ActiveSplit(
        splitId: 'split-1',
        name: 'Push Pull Legs',
        durationDays: 6,
        activatedAtUtc: DateTime.now(),
      ),
    );
  }
}

class _FakeRestTodayRepo extends TodayRepository {
  _FakeRestTodayRepo() : super(ApiClient(sessionStore: SessionStore()));

  @override
  Future<TodayDashboard> getDashboard() async {
    return TodayDashboard(
      session: const TodaySession(
        workoutSessionId: null,
        title: 'Recovery',
        status: 'ActiveRest',
        focusLabel: 'REST DAY',
        estimatedMinutes: null,
        isRestDay: true,
      ),
      targetExercises: [],
      hydrationTotalMl: 1200,
      hydrationTargetMl: 2500,
      currentStreakDays: 5,
      weeklyCompliancePercent: 85,
      weekStatuses: [
        WeekDayStatus(
          date: DateTime(
              DateTime.now().year, DateTime.now().month, DateTime.now().day),
          status: 'Rest',
        ),
      ],
      activeSplit: ActiveSplit(
        splitId: 'split-1',
        name: 'Push Pull Legs',
        durationDays: 6,
        activatedAtUtc: DateTime.now(),
      ),
    );
  }
}

void main() {
  testWidgets('TodayScreen builds and displays active split and AI review',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final plans = _FakePlans();
    final plansController = PlansController(plans, IapService());
    final todayRepo = _FakeTodayRepo();
    final todayController = TodayController(todayRepo);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>(create: (_) => _FakeAuth()),
          ChangeNotifierProvider.value(value: plansController),
          ChangeNotifierProvider.value(value: todayController),
          Provider<PlansRepository>.value(value: plans),
          Provider<AnalyticsRepository>.value(value: _FakeAnalytics()),
          Provider<SplitsRepository>.value(value: _FakeSplits()),
          Provider<TodayRepository>.value(value: todayRepo),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 900,
              width: 400,
              child: TodayScreen(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final splitFinder = find.byType(ActiveSplitCard);
    expect(splitFinder, findsOneWidget);
    final splitRect = tester.getRect(splitFinder);

    final teaserFinder = find.byType(AiInsightsTeaserCard);
    expect(teaserFinder, findsOneWidget);
    final teaserRect = tester.getRect(teaserFinder);

    expect(splitRect.bottom, lessThan(teaserRect.top));
    expect(teaserRect.bottom, closeTo(828.0, 2.0));
  });

  testWidgets(
      'TodayScreen pins active split and AI review to bottom on rest day',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final plans = _FakePlans();
    final plansController = PlansController(plans, IapService());
    final todayRepo = _FakeRestTodayRepo();
    final todayController = TodayController(todayRepo);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>(create: (_) => _FakeAuth()),
          ChangeNotifierProvider.value(value: plansController),
          ChangeNotifierProvider.value(value: todayController),
          Provider<PlansRepository>.value(value: plans),
          Provider<AnalyticsRepository>.value(value: _FakeAnalytics()),
          Provider<SplitsRepository>.value(value: _FakeSplits()),
          Provider<TodayRepository>.value(value: todayRepo),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 900,
              width: 400,
              child: TodayScreen(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final splitFinder = find.byType(ActiveSplitCard);
    expect(splitFinder, findsOneWidget);
    final splitRect = tester.getRect(splitFinder);

    final teaserFinder = find.byType(AiInsightsTeaserCard);
    expect(teaserFinder, findsOneWidget);
    final teaserRect = tester.getRect(teaserFinder);

    expect(splitRect.bottom, lessThan(teaserRect.top));
    expect(teaserRect.bottom, closeTo(828.0, 2.0));
  });

  testWidgets('TodayScreen renders without overflow on compact screen',
      (tester) async {
    tester.view.physicalSize = const Size(360, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final plans = _FakePlans();
    final plansController = PlansController(plans, IapService());
    final todayRepo = _FakeTodayRepo();
    final todayController = TodayController(todayRepo);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>(create: (_) => _FakeAuth()),
          ChangeNotifierProvider.value(value: plansController),
          ChangeNotifierProvider.value(value: todayController),
          Provider<PlansRepository>.value(value: plans),
          Provider<AnalyticsRepository>.value(value: _FakeAnalytics()),
          Provider<SplitsRepository>.value(value: _FakeSplits()),
          Provider<TodayRepository>.value(value: todayRepo),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              width: 360,
              child: TodayScreen(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final splitFinder = find.byType(ActiveSplitCard);
    expect(splitFinder, findsOneWidget);
    final splitRect = tester.getRect(splitFinder);

    final teaserFinder = find.byType(AiInsightsTeaserCard);
    expect(teaserFinder, findsOneWidget);
    final teaserRect = tester.getRect(teaserFinder);

    expect(tester.takeException(), isNull);
    expect(splitRect.bottom, lessThan(teaserRect.top));
  });
}
