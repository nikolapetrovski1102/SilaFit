import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/api/api_exception.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/features/plans/iap_service.dart';
import 'package:silafit/features/plans/plans_controller.dart';
import 'package:silafit/features/plans/plans_models.dart';
import 'package:silafit/features/plans/plans_repository.dart';

class _FakeProduct implements ProductDetails {
  @override
  final String id;

  _FakeProduct(this.id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Serves [_plan]'s catalogue and accepts only `SILEN30`, which unlocks the
/// `silen30` Play offer; anything else is turned down the way the API does.
class _PlansRepository extends PlansRepository {
  _PlansRepository() : super(ApiClient(sessionStore: SessionStore()));

  @override
  Future<List<PlanCatalogEntry>> getCatalog() async =>
      const [PlanCatalogEntry(plan: _plan, features: [])];

  @override
  Future<PromoCode> redeemPromoCode(String code) async {
    if (code != 'SILEN30') {
      throw const ApiException('That code isn\'t valid.', statusCode: 400);
    }
    return const PromoCode(code: 'SILEN30', playOfferId: 'silen30');
  }
}

/// Play's side: [promoProducts] are the products the code's offer is live on.
class _IapService implements IapService {
  final Set<String> promoProducts;
  final requestedOffers = <String?>[];

  _IapService({this.promoProducts = const {}});

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Map<String, StoreQuote>> loadQuotes(Set<String> productIds,
      {String? promoOfferId}) async {
    requestedOffers.add(promoOfferId);
    return {
      for (final id in productIds)
        id: StoreQuote(
          product: _FakeProduct(id),
          isPromoCode: promoOfferId != null && promoProducts.contains(id),
        ),
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _plan = SubscriptionPlan(
  planId: 'pro',
  code: 'PRO',
  name: 'Pro',
  monthlyPrice: 2.99,
  yearlyPrice: 24.99,
  isFeatured: true,
  playStoreMonthlyProductId: 'pro_monthly',
  playStoreYearlyProductId: 'pro_yearly',
);

void main() {
  test('an accepted code re-prices the plans with its Play offer', () async {
    final iap = _IapService(promoProducts: {'pro_monthly', 'pro_yearly'});
    final plans = PlansController(_PlansRepository(), iap);

    expect(await plans.applyPromoCode(' SILEN30 '), isNull);
    expect(plans.promoCode?.playOfferId, 'silen30');
    expect(iap.requestedOffers.last, 'silen30');
    expect(plans.quoteFor(_plan)?.isPromoCode, isTrue);
  });

  test('switches to the billing cycle the discount covers', () async {
    final plans = PlansController(
        _PlansRepository(), _IapService(promoProducts: {'pro_monthly'}));
    expect(plans.isYearly, isTrue);

    expect(await plans.applyPromoCode('SILEN30'), isNull);
    expect(plans.isYearly, isFalse);
  });

  test('a code the server turns down shows its reason', () async {
    final plans = PlansController(_PlansRepository(), _IapService());

    expect(await plans.applyPromoCode('NOPE'), 'That code isn\'t valid.');
    expect(plans.promoCode, isNull);
  });

  test('a valid code whose offer is live on no product is refused', () async {
    final plans = PlansController(_PlansRepository(), _IapService());

    expect(await plans.applyPromoCode('SILEN30'),
        'This code doesn\'t apply to any plan right now.');
    expect(plans.promoCode, isNull);
  });
}
