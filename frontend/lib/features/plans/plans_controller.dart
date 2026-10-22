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

  /// Bumped whenever the user's entitlement changes - a verified purchase or
  /// restore, or [refreshCurrent] noticing the plan moved (renewed or lapsed
  /// outside the app). Every surface that gates on the plan watches this.
  int purchaseRevision = 0;
  String? actionError;

  /// The caller's plan - the one copy every screen reads, so a purchase
  /// shows up everywhere at once instead of wherever happened to refetch.
  /// Null while the first check is in flight or after it failed (see
  /// [currentFailed]), so nothing claims "Free" for a paying user it just
  /// couldn't reach.
  CurrentSubscription? current;
  bool currentFailed = false;
  int _currentRequest = 0;

  // Purchases the store says went through but the server couldn't be reached
  // to confirm, keyed by transaction. Left unfinished with the store (which
  // redelivers them on the next launch) and retried here on resume, so a
  // dropped connection mid-purchase never leaves a paying user locked out.
  final Map<String, PurchaseDetails> _unconfirmed = {};

  // A plan unlocked by something other than the paywall's own buy button -
  // a redeemed code, an Ask to Buy approval, a purchase that was pending -
  // waiting for RootShell to celebrate it (see [takeCelebration]).
  CurrentSubscription? _celebration;
  bool _explicitRestore = false;

  // Store-side quotes (localized price + eligible intro offer) keyed by
  // product id. Prices on the paywall come from here, never from the
  // catalogue's USD figures, so what's shown is what the store charges.
  Map<String, StoreQuote> _quotes = const {};

  /// The Silen promo code applied this session (Google Play only) - its
  /// offer replaces the intro offer on every product that carries it.
  PromoCode? promoCode;

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

  /// Re-reads the caller's plan from the server. [quiet] keeps the last
  /// known plan on screen while it loads (and if it fails) instead of
  /// dropping to the "checking" state - for refreshes the user didn't ask
  /// for. Returns the fresh plan, or null when it couldn't be fetched.
  Future<CurrentSubscription?> refreshCurrent({bool quiet = false}) async {
    final request = ++_currentRequest;
    final previous = current;
    if (!quiet) {
      current = null;
      currentFailed = false;
      notifyListeners();
    }
    CurrentSubscription? fresh;
    try {
      fresh = await _repository.getCurrent();
    } catch (_) {}
    // A newer refresh, or a purchase landing meanwhile, owns the answer now.
    if (request != _currentRequest) return fresh;
    if (fresh == null) {
      if (!quiet) currentFailed = true;
    } else {
      current = fresh;
      currentFailed = false;
      if (previous != null && !_samePlan(previous, fresh)) purchaseRevision++;
    }
    notifyListeners();
    return fresh;
  }

  static bool _samePlan(CurrentSubscription a, CurrentSubscription b) =>
      a.planCode == b.planCode && a.billingCycle == b.billingCycle;

  /// Hands over (once) a plan that was just unlocked outside the paywall's
  /// purchase flow, which celebrates its own purchases.
  CurrentSubscription? takeCelebration() {
    final celebration = _celebration;
    _celebration = null;
    return celebration;
  }

  /// [planCode]'s catalogue perks, highlighted ones first - empty until the
  /// catalogue has loaded.
  List<String> perksFor(String planCode) {
    final features = [
      for (final entry in state.data ?? const <PlanCatalogEntry>[])
        if (entry.plan.code.toUpperCase() == planCode.toUpperCase())
          ...entry.features,
    ];
    // Two passes rather than sort(): List.sort isn't stable, and the
    // catalogue order within each group is deliberate.
    return [
      for (final f in features)
        if (f.isHighlighted) f.featureText,
      for (final f in features)
        if (!f.isHighlighted) f.featureText,
    ];
  }

  /// Opens the store's own code redemption (see [IapService.presentRedeemCode])
  /// - Apple offer codes on iOS, Play's free-time promo codes on Android.
  Future<void> redeemCode() async {
    // Whatever the store grants, look for it on the very next resume rather
    // than after the usual throttle.
    _lastSilentSync = null;
    await _iapService.presentRedeemCode();
  }

  /// Claims a Silen promo code and re-prices the paywall with the Play offer
  /// it unlocks. Returns the reason it can't be used, or null once applied.
  Future<String?> applyPromoCode(String code) async {
    final PromoCode promo;
    try {
      promo = await _repository.redeemPromoCode(code.trim());
    } on ApiException catch (e) {
      return e.userMessage;
    } catch (_) {
      return ApiException.genericMessage;
    }

    if (state.data == null) await load(force: true);
    final catalog = state.data;
    if (catalog == null) return ApiException.genericMessage;
    try {
      if (!await _iapService.isAvailable()) {
        return 'In-app purchases are not available on this device.';
      }
      final quotes = await _iapService.loadQuotes(_productIds(catalog),
          promoOfferId: promo.playOfferId);
      // The server knows the code; only Play knows which products carry the
      // offer - a code whose offer isn't live on any of them is no discount.
      if (!quotes.values.any((q) => q.isPromoCode)) {
        return 'This code doesn\'t apply to any plan right now.';
      }
      promoCode = promo;
      _quotes = quotes;
    } catch (_) {
      return ApiException.genericMessage;
    }

    // Land on a billing cycle the discount actually covers.
    bool discounted(bool yearly) => catalog
        .any((e) => quoteFor(e.plan, yearly: yearly)?.isPromoCode == true);
    if (!discounted(isYearly) && discounted(!isYearly)) isYearly = !isYearly;
    notifyListeners();
    return null;
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

  Set<String> _productIds(List<PlanCatalogEntry> catalog) => {
        for (final entry in catalog)
          for (final yearly in const [true, false])
            if (_productIdFor(entry.plan, yearly: yearly) case final id?) id,
      };

  Future<void> _loadQuotes(List<PlanCatalogEntry> catalog) async {
    final ids = _productIds(catalog);
    if (ids.isEmpty) return;
    try {
      if (!await _iapService.isAvailable()) return;
      _quotes = await _iapService.loadQuotes(ids,
          promoOfferId: promoCode?.playOfferId);
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
          (await _iapService.loadQuotes({productId},
              promoOfferId: promoCode?.playOfferId))[productId];
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
    _explicitRestore = true;
    actionError = null;
    notifyListeners();
    final outcome = await _runRestore(syncWithStore: true);
    _explicitRestore = false;
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
    // Not throttled: these are purchases the user already paid for.
    await _retryUnconfirmed();
    final now = DateTime.now();
    if (_lastSilentSync != null &&
        now.difference(_lastSilentSync!) < _silentSyncMinGap) {
      return;
    }
    _lastSilentSync = now;
    isRestoring = true;
    final previousError = actionError;
    try {
      final plan = await refreshCurrent(quiet: true);
      if (plan == null || plan.isPaid) return;
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
      // Play reports a dismissed or failed purchase sheet with an empty
      // productID, so a terminal non-purchase event without one belongs to
      // whichever purchase is in flight - otherwise the button spins forever.
      final isAnonymousFailure = purchase.productID.isEmpty &&
          (purchase.status == PurchaseStatus.canceled ||
              purchase.status == PurchaseStatus.error);
      final isTracked = _pendingPurchase != null &&
          (purchase.productID == _pendingProductId || isAnonymousFailure);
      switch (purchase.status) {
        case PurchaseStatus.pending:
          continue;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Known to be on Free beforehand - not merely unknown, or every
          // renewal StoreKit redelivers at launch would look like an unlock.
          final wasFree = current != null && !current!.isPaid;
          final error = await _verifyAndComplete(purchase);
          if (error == null) {
            verified++;
            // Only a fresh purchase that really moved Free -> paid is an
            // unlock. A `restored` one is the quiet launch sync redelivering
            // history (expired transactions included, which leave the user on
            // Free) - celebrating those meant a "welcome" on every login.
            final isUnlock = purchase.status == PurchaseStatus.purchased &&
                wasFree &&
                current != null &&
                current!.isPaid;
            if (!isTracked && !_explicitRestore && isUnlock) {
              _celebration = current;
            }
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

  static const _unconfirmedMessage =
      'Your purchase went through, but we couldn\'t confirm it with our '
      'server yet. It will unlock automatically once you\'re back online.';

  /// Sends a purchased/restored transaction to the server for receipt
  /// validation, then completes it on the platform side once the server has
  /// given a verdict - verified or refused. Completing a refused one matters:
  /// otherwise StoreKit/Play Billing keeps redelivering it forever. But one
  /// the server never got to see (offline, timed out, 5xx) is left open and
  /// queued in [_unconfirmed], because a completed transaction is never
  /// redelivered and the user would have paid for nothing. Returns the
  /// user-facing error, or null once the server has verified it.
  Future<String?> _verifyAndComplete(PurchaseDetails purchase) async {
    final key = purchase.purchaseID ??
        purchase.verificationData.serverVerificationData;
    try {
      current = await _repository.verifyPurchase(
        store: Platform.isIOS ? 'AppStore' : 'PlayStore',
        productId: purchase.productID,
        receiptData: purchase.verificationData.serverVerificationData,
        transactionId: purchase.purchaseID,
      );
      currentFailed = false;
      // Supersede any /plans/current read already in flight - it may have
      // been answered before the server activated this purchase.
      _currentRequest++;
      purchaseRevision++;
      _unconfirmed.remove(key);
      await _iapService.completePurchase(purchase);
      return null;
    } on ApiException catch (e) {
      if (e.isRetryable) {
        _unconfirmed[key] = purchase;
        return _unconfirmedMessage;
      }
      _unconfirmed.remove(key);
      await _iapService.completePurchase(purchase);
      return e.userMessage;
    } catch (_) {
      _unconfirmed.remove(key);
      await _iapService.completePurchase(purchase);
      return ApiException.genericMessage;
    }
  }

  /// Gives every purchase stuck in [_unconfirmed] another go at the server.
  Future<void> _retryUnconfirmed() async {
    if (_unconfirmed.isEmpty) return;
    final pending = _unconfirmed.values.toList();
    var verified = 0;
    for (final purchase in pending) {
      if (await _verifyAndComplete(purchase) == null) verified++;
    }
    if (verified > 0) notifyListeners();
  }

  void _resolvePending(bool result) {
    _pendingPurchase?.complete(result);
    _pendingPurchase = null;
    _pendingProductId = null;
  }
}
