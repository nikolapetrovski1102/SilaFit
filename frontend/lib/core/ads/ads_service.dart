import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stack_appodeal_flutter/stack_appodeal_flutter.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';

import '../../features/plans/plans_models.dart';
import '../api/api_config.dart';

/// Ads for Free accounts: an interstitial after every second finished
/// workout, and a rewarded video that opens the Progress screen once. A
/// paying account never starts either SDK.
///
/// Two networks run side by side - Appodeal (its own mediation) and Unity
/// LevelPlay (Unity Ads direct). Both keep an ad loaded; at show time the one
/// that has an ad wins, and when both do, the better-paying one. Either can
/// be switched off by leaving its keys empty (see [ApiConfig]), and the other
/// then serves alone.
///
/// Placement / ad unit names match the dashboards (`workout_complete`,
/// `progress_unlock`); the dashboards own the frequency caps on top of the
/// local ones here.
class AdsService {
  AdsService._();

  static final AdsService instance = AdsService._();

  static const workoutPlacement = 'workout_complete';
  static const progressPlacement = 'progress_unlock';

  static const _workoutsKey = 'ads.workoutsSinceInterstitial';
  static const _lastInterstitialKey = 'ads.lastInterstitialAtMs';
  static const _workoutsPerInterstitial = 2;
  static const _interstitialGap = Duration(minutes: 10);

  // Some networks report the reward just after the close event, so a close
  // without one waits this long before calling the video unfinished.
  static const _lateRewardGrace = Duration(seconds: 2);

  /// Whether a rewarded video is loaded and allowed to show right now - the
  /// Progress lock only offers "watch an ad" while this is true.
  final ValueNotifier<bool> rewardedReady = ValueNotifier(false);

  bool _enabled = false;
  bool _started = false;
  bool _appodealReady = false;

  // The one rewarded video in flight, whichever network plays it.
  Completer<bool>? _rewardedPending;
  bool _rewardEarned = false;

  late final _levelPlayInterstitial = _LevelPlaySlot<LevelPlayInterstitialAd>(
    adUnitId: _pick(ApiConfig.levelPlayIosInterstitialUnit,
        ApiConfig.levelPlayAndroidInterstitialUnit),
    create: (unit, slot) => LevelPlayInterstitialAd(adUnitId: unit)
      ..setListener(_LevelPlayInterstitialListener(slot)),
    load: (ad) => ad.loadAd(),
    checkReady: (ad) => ad.isAdReady(),
    dispose: (ad) => ad.dispose(),
  );

  late final _levelPlayRewarded = _LevelPlaySlot<LevelPlayRewardedAd>(
    adUnitId: _pick(ApiConfig.levelPlayIosRewardedUnit,
        ApiConfig.levelPlayAndroidRewardedUnit),
    create: (unit, slot) => LevelPlayRewardedAd(adUnitId: unit)
      ..setListener(_LevelPlayRewardedListener(slot, this)),
    load: (ad) => ad.loadAd(),
    checkReady: (ad) => ad.isAdReady(),
    dispose: (ad) => ad.dispose(),
    onChanged: () => unawaited(_refreshRewardedReady()),
  );

  static String _pick(String ios, String android) {
    if (Platform.isIOS) return ios;
    if (Platform.isAndroid) return android;
    return '';
  }

  String get _appodealKey =>
      _pick(ApiConfig.appodealIosKey, ApiConfig.appodealAndroidKey);

  String get _levelPlayKey =>
      _pick(ApiConfig.levelPlayIosAppKey, ApiConfig.levelPlayAndroidAppKey);

  /// Follows the account's plan. Null (still checking, or the check failed)
  /// keeps the last decision so a paying user is never shown ads by a
  /// dropped request.
  void sync(CurrentSubscription? plan) {
    if (plan == null) return;
    _apply(paid: plan.isPaid);
  }

  /// A guest session never loads a plan (purchases need an account), and a
  /// guest can't pay, so it always gets the Free experience.
  void syncGuest() => _apply(paid: false);

  void _apply({required bool paid}) {
    _enabled = !paid && (_appodealKey.isNotEmpty || _levelPlayKey.isNotEmpty);
    if (_enabled && !_started) {
      _started = true;
      unawaited(_start());
    }
    unawaited(_refreshRewardedReady());
  }

  Future<void> _start() async {
    try {
      // Apple requires the ATT prompt before anything reads the IDFA. iOS
      // drops the request silently unless the app is active, so wait for
      // that (the first sync can land while launch is still settling).
      if (Platform.isIOS) {
        await _untilActive();
        await Permission.appTrackingTransparency.request();
      }
    } catch (_) {}

    // GDPR / US-state consent - Appodeal's form shows only where the law
    // needs one, and stores the answer as the standard IAB TCF strings,
    // which LevelPlay reads too. Without an Appodeal key there's no form.
    if (_appodealKey.isNotEmpty) {
      final consent = Completer<void>();
      Appodeal.ConsentForm.loadAndShowIfRequired(
        appKey: _appodealKey,
        onConsentFormDismissed: (_) {
          if (!consent.isCompleted) consent.complete();
        },
      );
      await consent.future
          .timeout(const Duration(seconds: 20), onTimeout: () {});
      _startAppodeal();
    }
    if (_levelPlayKey.isNotEmpty) await _startLevelPlay();
  }

  static Future<void> _untilActive() async {
    final binding = WidgetsBinding.instance;
    if (binding.lifecycleState != AppLifecycleState.resumed) {
      final active = Completer<void>();
      final listener = AppLifecycleListener(onResume: () {
        if (!active.isCompleted) active.complete();
      });
      await active.future;
      listener.dispose();
    }
    // Let the first frame (and any system sheet) settle before prompting.
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  void _startAppodeal() {
    Appodeal.setTesting(kDebugMode);
    Appodeal.setAutoCache(AppodealAdType.Interstitial, true);
    Appodeal.setAutoCache(AppodealAdType.RewardedVideo, true);
    Appodeal.setRewardedVideoCallbacks(
      onRewardedVideoLoaded: (_) => _refreshRewardedReady(),
      onRewardedVideoFailedToLoad: () => _refreshRewardedReady(),
      onRewardedVideoExpired: () => _refreshRewardedReady(),
      onRewardedVideoShowFailed: () => _finishRewarded(false),
      onRewardedVideoFinished: (_, __) => _rewardEarned = true,
      onRewardedVideoClosed: (isFinished) =>
          _finishRewarded(isFinished || _rewardEarned),
    );
    Appodeal.initialize(
      appKey: _appodealKey,
      adTypes: const [
        AppodealAdType.Interstitial,
        AppodealAdType.RewardedVideo,
      ],
      onInitializationFinished: (_) {
        _appodealReady = true;
        unawaited(_refreshRewardedReady());
      },
    );
  }

  Future<void> _startLevelPlay() async {
    try {
      if (kDebugMode) await LevelPlay.setAdaptersDebug(true);
      await LevelPlay.init(
        initRequest: LevelPlayInitRequest.builder(_levelPlayKey).build(),
        initListener: _LevelPlayInitListener(() {
          _levelPlayInterstitial.start();
          _levelPlayRewarded.start();
        }),
      );
    } catch (_) {}
  }

  Future<bool> _appodealCanShow(AppodealAdType type, String placement) async {
    if (!_appodealReady) return false;
    try {
      return await Appodeal.canShow(type, placement);
    } catch (_) {
      return false;
    }
  }

  /// Which network should play the next [type] ad: whichever has one, and
  /// when both do, the higher expected payout. Null when neither has one.
  Future<_Network?> _choose(AppodealAdType type, String placement,
      _LevelPlaySlot levelPlay) async {
    final viaAppodeal = await _appodealCanShow(type, placement);
    final viaLevelPlay = await levelPlay.isReady();
    if (viaAppodeal && viaLevelPlay) {
      // LevelPlay reports this impression's revenue in USD; Appodeal
      // predicts eCPM, which is USD per thousand.
      final levelPlayEcpm = (levelPlay.loadedRevenue ?? 0) * 1000;
      var appodealEcpm = 0.0;
      try {
        appodealEcpm = await Appodeal.getPredictedEcpm(type);
      } catch (_) {}
      return levelPlayEcpm >= appodealEcpm
          ? _Network.levelPlay
          : _Network.appodeal;
    }
    if (viaLevelPlay) return _Network.levelPlay;
    if (viaAppodeal) return _Network.appodeal;
    return null;
  }

  Future<void> _refreshRewardedReady() async {
    var ready = false;
    if (_enabled && _rewardedPending == null) {
      ready = _levelPlayRewarded.loadedRevenue != null ||
          await _appodealCanShow(
              AppodealAdType.RewardedVideo, progressPlacement);
    }
    rewardedReady.value = ready;
  }

  void _onLevelPlayRewarded() {
    _rewardEarned = true;
  }

  void _onLevelPlayRewardedClosed() {
    if (_rewardEarned) {
      _finishRewarded(true);
    } else {
      Future.delayed(_lateRewardGrace, () => _finishRewarded(_rewardEarned));
    }
  }

  void _finishRewarded(bool earned) {
    final pending = _rewardedPending;
    _rewardedPending = null;
    if (pending != null && !pending.isCompleted) pending.complete(earned);
    unawaited(_refreshRewardedReady());
  }

  /// Plays the Progress rewarded video. True only when the user watched it
  /// through - closing early, or no ad to show, is false.
  Future<bool> showRewarded() async {
    if (!_enabled || _rewardedPending != null) return false;
    final pending = _rewardedPending = Completer<bool>();
    _rewardEarned = false;
    rewardedReady.value = false;
    try {
      switch (await _choose(AppodealAdType.RewardedVideo, progressPlacement,
          _levelPlayRewarded)) {
        case _Network.levelPlay:
          await _levelPlayRewarded.show(
              (ad) => ad.showAd(placementName: progressPlacement));
        case _Network.appodeal:
          if (!await Appodeal.show(
              AppodealAdType.RewardedVideo, progressPlacement)) {
            _finishRewarded(false);
          }
        case null:
          _finishRewarded(false);
      }
    } catch (_) {
      _finishRewarded(false);
    }
    return pending.future;
  }

  /// Called after a workout is logged: every second one, and never within
  /// [_interstitialGap] of the last, shows an interstitial. Best-effort - a
  /// missing ad just waits for the next workout.
  Future<void> maybeShowWorkoutInterstitial() async {
    if (!_enabled) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final workouts = (prefs.getInt(_workoutsKey) ?? 0) + 1;
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = prefs.getInt(_lastInterstitialKey);
      final due = workouts >= _workoutsPerInterstitial &&
          (last == null || now - last >= _interstitialGap.inMilliseconds);
      var shown = false;
      if (due) {
        switch (await _choose(AppodealAdType.Interstitial, workoutPlacement,
            _levelPlayInterstitial)) {
          case _Network.levelPlay:
            shown = await _levelPlayInterstitial
                .show((ad) => ad.showAd(placementName: workoutPlacement));
          case _Network.appodeal:
            shown = await Appodeal.show(
                AppodealAdType.Interstitial, workoutPlacement);
          case null:
            break;
        }
      }
      if (shown) {
        await prefs.setInt(_workoutsKey, 0);
        await prefs.setInt(_lastInterstitialKey, now);
      } else {
        await prefs.setInt(_workoutsKey, workouts);
      }
    } catch (_) {}
  }
}

enum _Network { appodeal, levelPlay }

/// One LevelPlay ad unit kept loaded: a fresh ad object per impression,
/// reloaded after each show, and retried with backoff when a load fails.
class _LevelPlaySlot<T extends Object> {
  final String adUnitId;
  final T Function(String adUnitId, _LevelPlaySlot<T> slot) create;
  final Future<void> Function(T ad) load;
  final Future<bool> Function(T ad) checkReady;
  final Future<void> Function(T ad) dispose;
  final VoidCallback? onChanged;

  _LevelPlaySlot({
    required this.adUnitId,
    required this.create,
    required this.load,
    required this.checkReady,
    required this.dispose,
    this.onChanged,
  });

  T? _ad;
  int _failures = 0;
  Timer? _retry;

  /// The loaded ad's revenue in USD, or null when nothing is loaded.
  double? loadedRevenue;

  void start() {
    if (adUnitId.isEmpty || _ad != null) return;
    _reload();
  }

  void _reload() {
    _retry?.cancel();
    final old = _ad;
    if (old != null) unawaited(dispose(old).catchError((_) {}));
    loadedRevenue = null;
    final ad = _ad = create(adUnitId, this);
    unawaited(load(ad).catchError((_) => onLoadFailed()));
    onChanged?.call();
  }

  void onLoaded(LevelPlayAdInfo info) {
    _failures = 0;
    loadedRevenue = info.revenue;
    onChanged?.call();
  }

  void onLoadFailed() {
    loadedRevenue = null;
    _failures++;
    // 30s, 60s, 120s ... capped at 10 minutes.
    final delay = Duration(seconds: math.min(600, 30 << (_failures - 1)));
    _retry?.cancel();
    _retry = Timer(delay, _reload);
    onChanged?.call();
  }

  /// The shown (or failed) ad is spent - line up the next one.
  void onFinished() => _reload();

  Future<bool> isReady() async {
    final ad = _ad;
    if (ad == null || loadedRevenue == null) return false;
    try {
      return await checkReady(ad);
    } catch (_) {
      return false;
    }
  }

  Future<bool> show(Future<void> Function(T ad) showAd) async {
    final ad = _ad;
    if (ad == null) return false;
    loadedRevenue = null;
    await showAd(ad);
    return true;
  }
}

class _LevelPlayInitListener implements LevelPlayInitListener {
  final VoidCallback onReady;

  _LevelPlayInitListener(this.onReady);

  @override
  void onInitSuccess(LevelPlayConfiguration configuration) => onReady();

  @override
  void onInitFailed(LevelPlayInitError error) {}
}

class _LevelPlayInterstitialListener
    implements LevelPlayInterstitialAdListener {
  final _LevelPlaySlot<LevelPlayInterstitialAd> slot;

  _LevelPlayInterstitialListener(this.slot);

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) => slot.onLoaded(adInfo);

  @override
  void onAdLoadFailed(LevelPlayAdError error) => slot.onLoadFailed();

  @override
  void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) =>
      slot.onFinished();

  @override
  void onAdClosed(LevelPlayAdInfo adInfo) => slot.onFinished();

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdInfoChanged(LevelPlayAdInfo adInfo) {}
}

class _LevelPlayRewardedListener implements LevelPlayRewardedAdListener {
  final _LevelPlaySlot<LevelPlayRewardedAd> slot;
  final AdsService service;

  _LevelPlayRewardedListener(this.slot, this.service);

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) => slot.onLoaded(adInfo);

  @override
  void onAdLoadFailed(LevelPlayAdError error) => slot.onLoadFailed();

  @override
  void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) {
    service._finishRewarded(false);
    slot.onFinished();
  }

  @override
  void onAdRewarded(LevelPlayReward reward, LevelPlayAdInfo adInfo) =>
      service._onLevelPlayRewarded();

  @override
  void onAdClosed(LevelPlayAdInfo adInfo) {
    service._onLevelPlayRewardedClosed();
    slot.onFinished();
  }

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdInfoChanged(LevelPlayAdInfo adInfo) {}
}
