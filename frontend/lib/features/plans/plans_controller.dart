import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import 'iap_service.dart';
import 'plans_models.dart';
import 'plans_repository.dart';

/// What a restore actually achieved once the server has verified everything
/// the store handed back - not merely that the store accepted the request.
enum RestoreOutcome { restored, nothingFound, failed }

typedef _BatchResult = ({int verified, List<String> errors});

class PlansController extends ChangeNotifier {
  final PlansRepository _repository;
  final IapService _iapService;

  ResourceState<List<PlanCatalogEntry>> state = const ResourceState.loading();
  bool isYearly = true;
  bool isPurchasing = false;
  bool isRestoring = false;
  int purchaseRevision = 0;
  String? actionError;

  // Store-side quotes (localized price + eligible intro offer) keyed by
  // product id. Prices on the paywall come from here, never from the
  // catalogue's USD figures, so what's shown is what the store charges.
  Map<String, StoreQuote> _quotes = const {};

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  Completer<bool>? _pendingPurchase;
  String? _pendingProductId;

  // Stream batches still being verified, collected only while a restore is in
  // flight so it can report the server's verdict rather than just "requested".
  List<Future<_BatchResult>>? _restoreBatches;

  // Google asks apps to re-query purchases on start/resume (promo codes
  // redeemed in the Play Store, purchases that were pending when the app
  // closed). Throttled so rapid background/resume cycling doesn't hammer it.
  static const _silentSyncMinGap = Duration(minutes: 10);
  DateTime? _lastSilentSync;

  PlansController(this._repository, this._iapService) {
    _purchaseSub = _iapService.purchaseStream.listen((purchases) {
      final batch = _onPurchaseUpdate(purchases);
      _restoreBatches?.add(batch);
    }, onError: (_) {});
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
      unawaited(_loadQuotes(catalog));
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

  String? _productIdFor(SubscriptionPlan plan, {bool? yearly}) {
    final y = yearly ?? isYearly;
    if (Platform.isIOS) {
      return y ? plan.appStoreYearlyProductId : plan.appStoreMonthlyProductId;
    }
    return y ? plan.playStoreYearlyProductId : plan.playStoreMonthlyProductId;
  }

  /// The store's quote for [plan] on the given (default: current) billing
  /// cycle - null until the store has answered, or if it doesn't sell it.
  StoreQuote? quoteFor(SubscriptionPlan plan, {bool? yearly}) {
    final id = _productIdFor(plan, yearly: yearly);
    return id == null ? null : _quotes[id];
  }

  /// Whether the store offers this user an intro price on any product.
  bool get hasIntroOffer => _quotes.values.any((q) => q.intro != null);

  /// Yearly-vs-12x-monthly saving for the featured paid tier, from the
  /// store's own prices - null until both are known, so the toggle never
  /// claims a saving the store's price points don't deliver.
  int? get yearlySavingsPercent {
    final catalog = state.data;
    if (catalog == null) return null;
    final paid = catalog.where((e) => e.plan.monthlyPrice > 0).toList();
    if (paid.isEmpty) return null;
    final plan = paid
        .firstWhere((e) => e.plan.isFeatured, orElse: () => paid.first)
        .plan;
    final monthly = quoteFor(plan, yearly: false)?.rawPrice;
    final yearly = quoteFor(plan, yearly: true)?.rawPrice;
    if (monthly == null || yearly == null || monthly <= 0) return null;
    final pct = ((1 - yearly / (monthly * 12)) * 100).floor();
    return pct > 0 ? pct : null;
  }

  Future<void> _loadQuotes(List<PlanCatalogEntry> catalog) async {
    final ids = <String>{
      for (final entry in catalog)
        for (final yearly in const [true, false])
          if (_productIdFor(entry.plan, yearly: yearly) case final id?) id,
    };
    if (ids.isEmpty) return;
    try {
      if (!await _iapService.isAvailable()) return;
      _quotes = await _iapService.loadQuotes(ids);
      notifyListeners();
    } catch (_) {
      // The paywall falls back to the catalogue price; purchase() re-queries.
    }
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

      final quote = _quotes[productId] ??
          (await _iapService.loadQuotes({productId}))[productId];
      if (quote == null) {
        actionError = ApiException.genericMessage;
        isPurchasing = false;
        notifyListeners();
        return false;
      }

      _pendingProductId = productId;
      _pendingPurchase = Completer<bool>();
      final started = await _iapService.buy(quote);
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
  /// does, through [purchaseStream] - handled by [_onPurchaseUpdate] - and
  /// this waits for the server to verify them before reporting an outcome.
  /// Returns null if a restore is already running.
  Future<RestoreOutcome?> restorePurchases() async {
    if (isRestoring) return null;
    isRestoring = true;
    actionError = null;
    notifyListeners();
    final outcome = await _runRestore(syncWithStore: true);
    if (outcome == RestoreOutcome.failed) {
      actionError ??= ApiException.genericMessage;
    }
    isRestoring = false;
    notifyListeners();
    return outcome;
  }

  /// Quietly picks up a purchase that completed outside the app. Only worth
  /// a store round-trip for a signed-in user the server has on the free
  /// plan; errors are swallowed so nothing surfaces in the UI.
  Future<void> syncEntitlements() async {
    if (isRestoring || isPurchasing) return;
    final now = DateTime.now();
    if (_lastSilentSync != null &&
        now.difference(_lastSilentSync!) < _silentSyncMinGap) {
      return;
    }
    _lastSilentSync = now;
    isRestoring = true;
    final previousError = actionError;
    try {
      if (await _repository.getActivePlanCode() != 'FREE') return;
      if (!await _iapService.isAvailable()) return;
      await _runRestore();
    } catch (_) {
      // Best-effort - the explicit Restore button is the fallback.
    } finally {
      actionError = previousError;
      isRestoring = false;
      notifyListeners();
    }
  }

  Future<RestoreOutcome> _runRestore({bool syncWithStore = false}) async {
    final batches = _restoreBatches = [];
    final errors = <String>[];
    try {
      try {
        await _iapService.restorePurchases(syncWithStore: syncWithStore);
      } on PlatformException catch (e) {
        // StoreKit 2 sends the purchases it could verify before failing on
        // the rest, so this still has to count what already arrived.
        errors.add(e.message ?? ApiException.genericMessage);
      } catch (_) {
        errors.add(ApiException.genericMessage);
      }
      // Both plugins push restored purchases onto the stream before this
      // returns, but over a separate platform channel - give that event a
      // moment to land before collecting the verifications it started.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final results = await Future.wait(batches);
      final verified = results.fold(0, (n, r) => n + r.verified);
      errors.addAll(results.expand((r) => r.errors));
      if (verified > 0) {
        actionError = null;
        return RestoreOutcome.restored;
      }
      if (errors.isEmpty) return RestoreOutcome.nothingFound;
      // Every distinct reason, not just whichever verification lost the race.
      actionError = errors.toSet().join('\n');
      return RestoreOutcome.failed;
    } catch (_) {
      return RestoreOutcome.failed;
    } finally {
      _restoreBatches = null;
    }
  }

  Future<_BatchResult> _onPurchaseUpdate(
      List<PurchaseDetails> purchases) async {
    var verified = 0;
    final errors = <String>[];
    for (final purchase in purchases) {
      final isTracked =
          _pendingPurchase != null && purchase.productID == _pendingProductId;
      switch (purchase.status) {
        case PurchaseStatus.pending:
          continue;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final error = await _verifyAndComplete(purchase);
          if (error == null) {
            verified++;
          } else {
            errors.add(error);
            actionError = error;
          }
          if (isTracked) _resolvePending(error == null);
          notifyListeners();
          break;
        case PurchaseStatus.error:
          await _iapService.completePurchase(purchase);
          if (isTracked) {
            actionError =
                purchase.error?.message ?? ApiException.genericMessage;
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
    return (verified: verified, errors: errors);
  }

  /// Sends a purchased/restored transaction to the server for receipt
  /// validation, then always completes it on the platform side regardless
  /// of whether verification succeeded - otherwise StoreKit/Play Billing
  /// keeps redelivering a transaction the store already recorded. Returns
  /// the user-facing error, or null once the server has verified it.
  Future<String?> _verifyAndComplete(PurchaseDetails purchase) async {
    String? error;
    try {
      await _repository.verifyPurchase(
        store: Platform.isIOS ? 'AppStore' : 'PlayStore',
        productId: purchase.productID,
        receiptData: purchase.verificationData.serverVerificationData,
        transactionId: purchase.purchaseID,
      );
      purchaseRevision++;
    } on ApiException catch (e) {
      error = e.userMessage;
    } catch (_) {
      error = ApiException.genericMessage;
    }
    await _iapService.completePurchase(purchase);
    return error;
  }

  void _resolvePending(bool result) {
    _pendingPurchase?.complete(result);
    _pendingPurchase = null;
    _pendingProductId = null;
  }
}
