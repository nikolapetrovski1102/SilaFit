import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/features/auth/auth_controller.dart';
import 'package:silafit/features/plans/plans_controller.dart';
import 'package:silafit/features/plans/plans_repository.dart';
import 'package:silafit/features/progress/analytics_models.dart';
import 'package:silafit/features/progress/analytics_repository.dart';
import 'package:silafit/features/progress/monthly_overview_mock.dart';
import 'package:silafit/features/progress/weekly_overview_mock.dart';
import 'package:silafit/features/today/today_controller.dart';
import 'package:silafit/features/today/today_repository.dart';
import 'package:silafit/features/today/widgets/ai_insights_teaser_card.dart';

class FakeAuth extends ChangeNotifier implements AuthController {
  @override
  get session => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlans extends PlansRepository {
  String code;
  FakePlans(this.code) : super(ApiClient(sessionStore: SessionStore()));
  @override
  Future<String> getActivePlanCode() async => code;
  @override
  Future<void> purchase(
      {required String planId, required String billingCycle}) async {
    code = planId;
  }
}

class FakeAnalytics extends AnalyticsRepository {
  int monthly = 0;
  int weekly = 0;
  FakeAnalytics() : super(ApiClient(sessionStore: SessionStore()));
  @override
  Future<MonthlyAnalytics> getMonthly(
      {int? year, int? month, bool refresh = false}) async {
    monthly++;
    return buildSimulatedMonthlyAnalytics();
  }

  @override
  Future<WeeklyAnalytics> getWeekly(
      {int? year, int? week, bool refresh = false}) async {
    weekly++;
    return buildSimulatedWeeklyAnalytics();
  }
}

void main() {
  for (final tier in ['FREE', 'PRO', 'ADVANCED']) {
    testWidgets(
        'Home selects the correct recap for $tier and updates on purchase',
        (tester) async {
      final plans = FakePlans(tier);
      final controller = PlansController(plans);
      final analytics = FakeAnalytics();
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthController>(create: (_) => FakeAuth()),
            ChangeNotifierProvider(
                create: (_) => TodayController(TodayRepository(ApiClient(sessionStore: SessionStore())))),
            ChangeNotifierProvider.value(value: controller),
            Provider<PlansRepository>.value(value: plans),
            Provider<AnalyticsRepository>.value(value: analytics),
          ],
          child:
              const MaterialApp(home: Scaffold(body: AiInsightsTeaserCard()))));
      await tester.pumpAndSettle();
      expect(analytics.monthly, tier == 'PRO' ? 1 : 0);
      expect(analytics.weekly, tier == 'ADVANCED' ? 1 : 0);
      expect(
          find.text(tier == 'FREE'
              ? 'AI TRAINING REVIEWS'
              : tier == 'PRO'
                  ? 'MONTHLY AI REVIEW'
                  : 'WEEKLY AI REVIEW'),
          findsOneWidget);
      await controller.purchase('ADVANCED');
      await tester.pumpAndSettle();
      expect(find.text('WEEKLY AI REVIEW'), findsOneWidget);
      expect(find.text('UNLOCK'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
