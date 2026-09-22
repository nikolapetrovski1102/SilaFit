import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import 'iap_service.dart';
import 'plans_models.dart';
import 'plans_repository.dart';

class PlansController extends ChangeNotifier {
  final PlansRepository _repository;
  final IapService _iapService;

  ResourceState<List<PlanCatalogEntry>> state = const ResourceState.loading();
  bool isYearly = true;
  bool isPurchasing = false;
  bool isRestoring = false;
  int purchaseRevision = 0;
  String? actionError;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  Completer<bool>? _pendingPurchase;
  String? _pendingProductId;

  PlansController(this._repository, this._iapService) {
    _purchaseSub =
        _iapService.purchaseStream.listen(_onPurchaseUpdate, onError: (_) {});
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  // App-wide provider: skip a repeat catalogue load and never overlap loads.
  bool _isLoading = false;

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && state.hasData) return;
    _isLoading = true;
    state = const ResourceState.loading();
    notifyListeners();
    try {
      final catalog = await _repository.getCatalog();
      state = ResourceState.data(catalog);
    } on ApiException catch (e) {
      state = ResourceState.error(e.userMessage);
    } catch (_) {
      state = const ResourceState.error(ApiException.genericMessage);
    } finally {
      _isLoading = false;
    }
    notifyListeners();
  }

  void setBillingCycle({required bool yearly}) {
    isYearly = yearly;
    notifyListeners();
  }

  String? _productIdFor(SubscriptionPlan plan) {
    if (Platform.isIOS) {
      return isYearly
          ? plan.appStoreYearlyProductId
          : plan.appStoreMonthlyProductId;
    }
    return isYearly
        ? plan.playStoreYearlyProductId
        : plan.playStoreMonthlyProductId;
  }

  Future<bool> purchase(SubscriptionPlan plan) async {
    if (isPurchasing) return false;
    isPurchasing = true;
    actionError = null;
    notifyListeners();

    final productId = _productIdFor(plan);
    if (productId == null) {
      actionError = 'This plan is not available for purchase yet.';
      isPurchasing = false;
      notifyListeners();
      return false;
    }

    try {
      if (!await _iapService.isAvailable()) {
        actionError = 'In-app purchases are not available on this device.';
        isPurchasing = false;
        notifyListeners();
        return false;
      }

      final response = await _iapService.queryProducts({productId});
      if (response.productDetails.isEmpty ||
          response.notFoundIDs.contains(productId)) {
        actionError = ApiException.genericMessage;
        isPurchasing = false;
        notifyListeners();
        return false;
      }

      _pendingProductId = productId;
      _pendingPurchase = Completer<bool>();
      final started = await _iapService.buy(response.productDetails.first);
      if (!started) {
        _pendingProductId = null;
        _pendingPurchase = null;
        actionError = ApiException.genericMessage;
        isPurchasing = false;
        notifyListeners();
        return false;
      }

      final ok = await _pendingPurchase!.future;
      isPurchasing = false;
      notifyListeners();
      return ok;
    } catch (_) {
      _pendingProductId = null;
      _pendingPurchase = null;
      actionError = ApiException.genericMessage;
      isPurchasing = false;
      notifyListeners();
      return false;
    }
  }

  /// Re-delivers past purchases (App Store Review 3.1.1 requires an explicit
  /// entry point for this). Results arrive the same way a fresh purchase
  /// does, through [purchaseStream] - handled by [_onPurchaseUpdate].
  Future<void> restorePurchases() async {
    if (isRestoring) return;
    isRestoring = true;
    actionError = null;
    notifyListeners();
    try {
      await _iapService.restorePurchases();
    } catch (_) {
      actionError = ApiException.genericMessage;
    }
    isRestoring = false;
    notifyListeners();
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final isTracked =
          _pendingPurchase != null && purchase.productID == _pendingProductId;
      switch (purchase.status) {
        case PurchaseStatus.pending:
          continue;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final ok = await _verifyAndComplete(purchase);
          if (isTracked) _resolvePending(ok);
          notifyListeners();
          break;
        case PurchaseStatus.error:
          await _iapService.completePurchase(purchase);
          if (isTracked) {
            actionError = purchase.error?.message ?? ApiException.genericMessage;
            _resolvePending(false);
            notifyListeners();
          }
          break;
        case PurchaseStatus.canceled:
          if (isTracked) {
            _resolvePending(false);
            notifyListeners();
          }
          break;
      }
    }
  }

  /// Sends a purchased/restored transaction to the server for receipt
  /// validation, then always completes it on the platform side regardless
  /// of whether verification succeeded - otherwise StoreKit/Play Billing
  /// keeps redelivering a transaction the store already recorded.
  Future<bool> _verifyAndComplete(PurchaseDetails purchase) async {
    var verified = false;
    try {
      await _repository.verifyPurchase(
        store: Platform.isIOS ? 'AppStore' : 'PlayStore',
        productId: purchase.productID,
        receiptData: purchase.verificationData.serverVerificationData,
        transactionId: purchase.purchaseID,
      );
      purchaseRevision++;
      verified = true;
    } on ApiException catch (e) {
      actionError = e.userMessage;
    } catch (_) {
      actionError = ApiException.genericMessage;
    }
    await _iapService.completePurchase(purchase);
    return verified;
  }

  void _resolvePending(bool result) {
    _pendingPurchase?.complete(result);
    _pendingPurchase = null;
    _pendingProductId = null;
  }
}
