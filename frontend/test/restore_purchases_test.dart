import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/api/api_exception.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/features/plans/iap_service.dart';
import 'package:silafit/features/plans/plans_controller.dart';
import 'package:silafit/features/plans/plans_repository.dart';

/// Fails verification for any transaction id listed in [rejections], with
/// that entry's message; verifies everything else.
class _PlansRepository extends PlansRepository {
  final Map<String, String> rejections;

  _PlansRepository({this.rejections = const {}})
      : super(ApiClient(sessionStore: SessionStore()));

  @override
  Future<void> verifyPurchase({
    required String store,
    required String productId,
    required String receiptData,
    String? transactionId,
  }) async {
    final rejection = rejections[transactionId];
    if (rejection != null) throw ApiException(rejection, statusCode: 409);
  }
}

/// Emits [restored] on the purchase stream the way both store plugins do -
/// before restorePurchases returns - then optionally fails like StoreKit 2
/// does when some entitlements couldn't be verified on the device.
class _IapService implements IapService {
  final List<PurchaseDetails> restored;
  final PlatformException? restoreError;
  final _controller = StreamController<List<PurchaseDetails>>.broadcast();
  final syncRequests = <bool>[];

  _IapService({this.restored = const [], this.restoreError});

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> restorePurchases({bool syncWithStore = false}) async {
    syncRequests.add(syncWithStore);
    if (restored.isNotEmpty) _controller.add(restored);
    if (restoreError != null) throw restoreError!;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PurchaseDetails _restored(String id) => PurchaseDetails(
      purchaseID: id,
      productID: 'pro_monthly',
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: 'receipt-$id',
        source: 'test',
      ),
      transactionDate: null,
      status: PurchaseStatus.restored,
    );

void main() {
  test('reports restored once the server verifies a purchase', () async {
    final iap = _IapService(restored: [_restored('t1')]);
    final plans = PlansController(_PlansRepository(), iap);

    expect(await plans.restorePurchases(), RestoreOutcome.restored);
    expect(plans.actionError, isNull);
    expect(iap.syncRequests, [true]);
  });

  test('reports nothing found when the store has no purchases', () async {
    final plans = PlansController(_PlansRepository(), _IapService());

    expect(await plans.restorePurchases(), RestoreOutcome.nothingFound);
    expect(plans.actionError, isNull);
  });

  test('reports the server rejection when nothing verifies', () async {
    final plans = PlansController(
      _PlansRepository(rejections: {'t1': 'Linked to a different account.'}),
      _IapService(restored: [_restored('t1')]),
    );

    expect(await plans.restorePurchases(), RestoreOutcome.failed);
    expect(plans.actionError, 'Linked to a different account.');
  });

  test('still restores a verified purchase when the plugin fails after it',
      () async {
    final plans = PlansController(
      _PlansRepository(),
      _IapService(
        restored: [_restored('t1')],
        restoreError: PlatformException(
          code: 'storekit2_restore_failed',
          message: 'This purchase could not be restored.',
        ),
      ),
    );

    expect(await plans.restorePurchases(), RestoreOutcome.restored);
    expect(plans.actionError, isNull);
  });

  test('shows every distinct failure, not only the last', () async {
    final plans = PlansController(
      _PlansRepository(rejections: {
        't1': 'Linked to a different account.',
        't2': "That purchase isn't currently active.",
      }),
      _IapService(restored: [_restored('t1'), _restored('t2')]),
    );

    expect(await plans.restorePurchases(), RestoreOutcome.failed);
    expect(
      plans.actionError,
      "Linked to a different account.\nThat purchase isn't currently active.",
    );
  });

  test('the silent resume sync never asks the store to sync', () async {
    final iap = _IapService();
    final plans = PlansController(_FreePlanRepository(), iap);

    await plans.syncEntitlements();
    expect(iap.syncRequests, [false]);
  });
}

class _FreePlanRepository extends _PlansRepository {
  @override
  Future<String> getActivePlanCode() async => 'FREE';
}
