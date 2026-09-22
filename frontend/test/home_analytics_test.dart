import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/features/auth/auth_controller.dart';
import 'package:silafit/features/plans/iap_service.dart';
import 'package:silafit/features/plans/plans_controller.dart';
import 'package:silafit/features/plans/plans_repository.dart';
import 'package:silafit/features/progress/analytics_models.dart';
import 'package:silafit/features/progress/analytics_repository.dart';
import 'support/analytics_fixtures.dart';
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
}

class FakeAnalytics extends AnalyticsRepository {
  int monthly = 0;
  int weekly = 0;
  FakeAnalytics() : super(ApiClient(sessionStore: SessionStore()));
  @override
  Future<MonthlyAnalytics> getMonthly(
      {int? year, int? month, bool refresh = false}) async {
    monthly++;
    return monthlyAnalyticsFixture();
  }

  @override
  Future<WeeklyAnalytics> getWeekly(
      {int? year, int? week, bool refresh = false}) async {
    weekly++;
    return weeklyAnalyticsFixture();
  }
}

void main() {
  for (final tier in ['FREE', 'PRO', 'ADVANCED']) {
    testWidgets(
        'Home selects the correct recap for $tier and updates on purchase',
        (tester) async {
      final plans = FakePlans(tier);
      final controller = PlansController(plans, IapService());
      final analytics = FakeAnalytics();
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthController>(create: (_) => FakeAuth()),
            ChangeNotifierProvider(
                create: (_) => TodayController(
                    TodayRepository(ApiClient(sessionStore: SessionStore())))),
            ChangeNotifierProvider.value(value: controller),
            Provider<PlansRepository>.value(value: plans),
            Provider<AnalyticsRepository>.value(value: analytics),
          ],
          child:
              const MaterialApp(home: Scaffold(body: AiInsightsTeaserCard()))));
      await tester.pumpAndSettle();
      // Home resolves the subscription only; report details stay unloaded
      // until the user explicitly opens the monthly/weekly overview.
      expect(analytics.monthly, 0);
      expect(analytics.weekly, 0);
      expect(
          find.text(tier == 'FREE'
              ? 'AI TRAINING REVIEWS'
              : tier == 'PRO'
                  ? 'MONTHLY AI REVIEW'
                  : 'WEEKLY AI REVIEW'),
          findsOneWidget);
      // Purchases now require a real native IAP round-trip that can't be
      // driven from a widget test, so simulate the post-purchase state
      // directly: the repository reporting the new plan code plus the
      // revision bump the controller fires after a verified purchase.
      plans.code = 'ADVANCED';
      controller.purchaseRevision++;
      controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('WEEKLY AI REVIEW'), findsOneWidget);
      expect(find.text('UNLOCK'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
