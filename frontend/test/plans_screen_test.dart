import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/core/state/resource_state.dart';
import 'package:silafit/features/plans/iap_service.dart';
import 'package:silafit/features/plans/plans_controller.dart';
import 'package:silafit/features/plans/plans_models.dart';
import 'package:silafit/features/plans/plans_repository.dart';
import 'package:silafit/features/plans/plans_screen.dart';

class _PlansRepository extends PlansRepository {
  _PlansRepository() : super(ApiClient(sessionStore: SessionStore()));
}

// The real service opens a Play Billing connection with no platform side in
// widget tests; its async failure then lands on whichever test runs next.
class _IapService implements IapService {
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();

  @override
  Future<bool> isAvailable() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _catalog = [
  PlanCatalogEntry(
    plan: SubscriptionPlan(
      planId: 'pro',
      code: 'PRO',
      name: 'Pro',
      monthlyPrice: 4.99,
      yearlyPrice: 39.99,
      isFeatured: true,
    ),
    features: [
      PlanFeature(featureText: 'Monthly insights', isHighlighted: true),
    ],
  ),
];

void main() {
  late PlansController controller;

  setUp(() {
    controller = PlansController(_PlansRepository(), _IapService())
      ..state = const ResourceState.data(_catalog);
  });

  tearDown(() => controller.dispose());

  Future<void> pumpPlans(WidgetTester tester, {required bool welcomeOffer}) {
    return tester.pumpWidget(
      ChangeNotifierProvider<PlansController>.value(
        value: controller,
        child: MaterialApp(
          home: PlansScreen(isWelcomeOffer: welcomeOffer),
        ),
      ),
    );
  }

  testWidgets('welcome offer starts with the title and a close control',
      (tester) async {
    await pumpPlans(tester, welcomeOffer: true);
    await tester.pump();

    expect(find.byTooltip('Back'), findsNothing);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(
        find.text('NEW MEMBER · 50% OFF FIRST BILLING PERIOD'), findsNothing);
    expect(find.text('Choose Your Protocol'), findsOneWidget);
    expect(
        tester.getTopLeft(find.text('Choose Your Protocol')).dy, lessThan(8));
  });

  testWidgets('welcome offer stays dismissible while the catalogue is loading',
      (tester) async {
    controller.state = const ResourceState.loading();
    await pumpPlans(tester, welcomeOffer: true);
    await tester.pump();

    expect(find.text('Continue with Free Plan'), findsNothing);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('regular plans keep their back control without a context chip',
      (tester) async {
    await pumpPlans(tester, welcomeOffer: false);
    await tester.pump();

    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('SYSTEM TELEMETRY & ACCESS'), findsNothing);
    expect(find.text('Choose Your Protocol'), findsOneWidget);
  });
}
