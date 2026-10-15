import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:silafit/core/api/api_client.dart';
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

/// Answers every buy() by emitting [response] on the purchase stream, the
/// way the store plugins report a closed purchase sheet.
class _IapService implements IapService {
  final PurchaseDetails Function(String productId) response;
  final _controller = StreamController<List<PurchaseDetails>>.broadcast();

  _IapService(this.response);

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Map<String, StoreQuote>> loadQuotes(Set<String> productIds) async =>
      {for (final id in productIds) id: StoreQuote(product: _FakeProduct(id))};

  @override
  Future<bool> buy(StoreQuote quote) async {
    scheduleMicrotask(() => _controller.add([response(quote.product.id)]));
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PurchaseDetails _closed(String productId, PurchaseStatus status) =>
    PurchaseDetails(
      purchaseID: '',
      productID: productId,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: '',
        source: 'test',
      ),
      transactionDate: null,
      status: status,
    );

const _plan = SubscriptionPlan(
  planId: 'pro',
  code: 'PRO',
  name: 'Pro',
  monthlyPrice: 2.99,
  yearlyPrice: 24.99,
  isFeatured: true,
  appStoreMonthlyProductId: 'pro.monthly',
  appStoreYearlyProductId: 'pro.yearly',
  playStoreMonthlyProductId: 'pro_monthly',
  playStoreYearlyProductId: 'pro_yearly',
);

void main() {
  final repository = PlansRepository(ApiClient(sessionStore: SessionStore()));

  for (final status in [PurchaseStatus.canceled, PurchaseStatus.error]) {
    test('stops loading when Play reports $status without a product id',
        () async {
      final plans = PlansController(
          repository, _IapService((_) => _closed('', status)));

      expect(await plans.purchase(_plan), isFalse);
      expect(plans.isPurchasing, isFalse);
    });
  }

  test('stops loading when the store cancels with the product id', () async {
    final plans = PlansController(repository,
        _IapService((id) => _closed(id, PurchaseStatus.canceled)));

    expect(await plans.purchase(_plan), isFalse);
    expect(plans.isPurchasing, isFalse);
    expect(plans.actionError, isNull);
  });
}
