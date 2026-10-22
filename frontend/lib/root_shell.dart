import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

export 'core/widgets/silen_ambient_backdrop.dart';

import 'core/ads/ads_service.dart';
import 'core/api/api_client.dart';
import 'core/platform/device_timezone.dart';
import 'core/sync/sync_queue.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_spacing.dart';
import 'core/widgets/bottom_nav_bar.dart';
import 'core/widgets/offline_pill.dart';
import 'core/widgets/silen_ambient_backdrop.dart';
import 'features/auth/account_gate.dart';
import 'features/auth/auth_controller.dart';
import 'features/diet_plans/diet_plan_controller.dart';
import 'features/meals/meal_controller.dart';
import 'features/meals/meal_planning_screen.dart';
import 'features/notifications/notifications_repository.dart';
import 'features/onboarding/widgets/tour_guide_card.dart';
import 'features/plans/plans_controller.dart';
import 'features/plans/plans_screen.dart';
import 'features/plans/subscription_celebration.dart';
import 'features/progress/analytics_controller.dart';
import 'features/progress/exercise_progress_controller.dart';
import 'features/progress/progress_controller.dart';
import 'features/progress/weekly_analytics_controller.dart';
import 'features/progress/progress_screen.dart';
import 'features/settings/settings_controller.dart';
import 'features/settings/settings_screen.dart';
import 'features/splits/splits_controller.dart';
import 'features/splits/splits_screen.dart';
import 'features/today/today_controller.dart';
import 'features/today/today_screen.dart';

/// The four-tab shell every top-level screen lives inside. Owns the bottom
/// nav (there's no shared header bar - each screen carries its own large
/// title), and is the one place that enforces "Progress requires a linked
/// account" before switching tabs - the backend also enforces this (403
/// without it), this is just the friendlier UX layer. Plans/pricing is
/// reached from Settings' Subscription row, and workout splits from the
/// active-split card on Home - neither is a tab.
class RootShell extends StatefulWidget {
  /// When true, the feature tour overlay is shown on first mount, highlighting
  /// tabs and key elements before presenting the welcome offer.
  final bool showFeatureTour;

  const RootShell({super.key, this.showFeatureTour = false});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  late final PlansController _plans;
  late int _seenPurchaseRevision;
  static const _tabSwitchDuration = Duration(milliseconds: 320);
  static const _tabSwitchCurve = Curves.easeInOutCubic;

  final _pageController = PageController();
  int _index = 0;

  // Feature tour state
  bool _showingTour = false;
  int _tourStep =
      0; // 0: Home, 1: Splits, 2: Progress, 3: Nutrition, 4: Settings

  // The interaction ping exists to say "the user is here", so rapid
  // background/resume cycling doesn't need a request each time. Throttled to
  // one report per window; genuinely long absences still land.
  static const _interactionMinGap = Duration(seconds: 30);
  DateTime? _lastInteractionReportUtc;

  /// The offline outbox; null only in tests that don't provide one.
  SyncQueue? _syncQueue;

  // Spotlight keys for each tab
  final _homeSpotlightKey = GlobalKey();
  final _progressSpotlightKey = GlobalKey();
  final _nutritionSpotlightKey = GlobalKey();
  final _settingsSpotlightKey = GlobalKey();

  GlobalKey? get _currentSpotlightKey {
    switch (_tourStep) {
      case 0:
        return _homeSpotlightKey;
      case 2:
        return _progressSpotlightKey;
      case 3:
        return _nutritionSpotlightKey;
      case 4:
        return _settingsSpotlightKey;
      default:
        return null;
    }
  }

  List<Widget> get _screens => [
        TodayScreen(
            overviewSpotlightKey: _showingTour ? _homeSpotlightKey : null),
        ProgressScreen(
            spotlightKey: _showingTour ? _progressSpotlightKey : null),
    MealPlanningScreen(
        spotlightKey: _showingTour ? _nutritionSpotlightKey : null),
        SettingsScreen(
            spotlightKey: _showingTour ? _settingsSpotlightKey : null),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncQueue = context.read<SyncQueue?>();
    _syncQueue?.droppedMessage.addListener(_onSyncDropped);
    _plans = context.read<PlansController>();
    _seenPurchaseRevision = _plans.purchaseRevision;
    _plans.addListener(_onPlansChanged);
    AdsService.instance.sync(_plans.current);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportInteraction();
      _syncEntitlements();
      if (widget.showFeatureTour) {
        // Pre-warm data for subsequent tour steps so they render instantly
        unawaited(context.read<ProgressController>().load().catchError((_) {}));
        unawaited(context.read<MealController>().load().catchError((_) {}));
        unawaited(context.read<SettingsController>().load().catchError((_) {}));
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              _showingTour = true;
              _tourStep = 0;
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncQueue?.droppedMessage.removeListener(_onSyncDropped);
    _plans.removeListener(_onPlansChanged);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reportInteraction();
      _syncEntitlements();
      _recheckIfOffline();
      if (_syncQueue != null) unawaited(_syncQueue!.flush());
    }
  }

  /// A queued offline write the server refused once it was reachable again
  /// (say, the meal was deleted on another device) - say so, rather than
  /// let it vanish silently.
  void _onSyncDropped() {
    final message = _syncQueue?.droppedMessage.value;
    if (!mounted || message == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content:
            Text('A change saved offline couldn\'t be uploaded: $message')));
  }

  /// Back from the background while the last request had no signal - try
  /// Home again, so the lifter who just walked out of the gym gets fresh
  /// data (and the offline pill clears) without having to do anything.
  void _recheckIfOffline() {
    if (!mounted || !context.read<ApiClient>().isOffline.value) return;
    unawaited(context.read<TodayController>().load(force: true));
  }

  /// The app-lifetime controllers behind paid features each remember being
  /// refused (a 403) and stay locked until asked again. Re-ask every one of
  /// them the moment the entitlement changes - a purchase, a restore, or a
  /// plan that moved outside the app - whether or not its screen is open.
  void _onPlansChanged() {
    AdsService.instance.sync(_plans.current);
    final revision = _plans.purchaseRevision;
    if (revision == _seenPurchaseRevision) return;
    _seenPurchaseRevision = revision;
    unawaited(context.read<AnalyticsController>().load(force: true));
    unawaited(context.read<WeeklyAnalyticsController>().load(force: true));
    unawaited(context.read<ExerciseProgressController>().load(force: true));
    unawaited(context.read<SplitsController>().load(force: true));
    unawaited(context.read<DietPlansController>().load(force: true));

    final unlocked = _plans.takeCelebration();
    if (unlocked != null) {
      unawaited(showSubscriptionCelebration(context,
          planName: unlocked.planName,
          perks: _plans.perksFor(unlocked.planCode)));
    }
  }

  /// Picks up a subscription bought or renewed outside the app (a Play Store
  /// promo code, a purchase that was still pending when the app closed).
  /// Guests can't hold a subscription, so there's nothing to sync for them.
  void _syncEntitlements() {
    if (!mounted) return;
    if (!context.read<AuthController>().isRegistered) {
      AdsService.instance.syncGuest();
      return;
    }
    unawaited(context.read<PlansController>().syncEntitlements());
  }

  /// Tells the server the user is actually here (and refreshes the timezone).
  /// This is what keeps the reminder backoff honest: a few quiet days pause
  /// normal reminders, then a single comeback message fires. Best-effort - the
  /// app must never block on it.
  void _reportInteraction() {
    if (!mounted) return;
    final now = DateTime.now();
    if (_lastInteractionReportUtc != null &&
        now.difference(_lastInteractionReportUtc!) < _interactionMinGap) {
      return;
    }
    _lastInteractionReportUtc = now;
    final repository = context.read<NotificationsRepository>();
    unawaited(repository
        .recordInteraction(timeZoneId: deviceTimeZoneId())
        .catchError((_) {}));
  }

  /// Tap path (bottom nav): gate *before* the page starts moving, so a
  /// declined gate never shows so much as a peek of Progress.
  Future<void> _onTabSelected(int index) async {
    if (index == _index) return;
    if (index == 1 && !_showingTour && !await _ensureProgressUnlocked()) {
      return;
    }
    if (!mounted) return;
    await _pageController.animateToPage(index,
        duration: _tabSwitchDuration, curve: _tabSwitchCurve);
  }

  /// Swipe path: the drag has already landed on the new page by the time
  /// this fires, so the gate can only run after the fact - if it's
  /// declined, slide straight back to where the swipe started.
  void _onPageChanged(int index) {
    final previous = _index;
    HapticFeedback.selectionClick();
    setState(() => _index = index);
    // An ad pass buys one look at Progress - leaving the tab spends it.
    if (previous == 1 && index != 1) {
      unawaited(context.read<ExerciseProgressController>().endAdPass());
    }
    if (index == 1 &&
        !_showingTour &&
        !context.read<AuthController>().isRegistered) {
      _ensureProgressUnlocked().then((unlocked) {
        if (!unlocked && mounted) {
          _pageController.animateToPage(previous,
              duration: _tabSwitchDuration, curve: _tabSwitchCurve);
        }
      });
    }
  }

  Future<bool> _ensureProgressUnlocked() async {
    if (context.read<AuthController>().isRegistered) return true;
    return AccountGate.ensure(context);
  }

  void _nextTourStep() {
    HapticFeedback.lightImpact();
    if (_tourStep == 0) {
      // Step 0 (Home) -> Step 1 (Splits screen)
      setState(() => _tourStep = 1);
      Navigator.of(context)
          .push(
        MaterialPageRoute(
          builder: (_) => SplitsScreen(
            isTour: true,
            onTourNext: () {
              Navigator.of(context).pop();
              _advanceToProgress();
            },
            onTourSkip: () {
              Navigator.of(context).pop();
              _skipToChooseProtocol();
            },
          ),
        ),
      ).then((_) {
        // Safety net: if the Splits step is ever dismissed without its tour
        // card (Next/Skip both move _tourStep off 1 first), carry on to the
        // next step instead of leaving the shell stuck with no overlay.
        if (mounted && _showingTour && _tourStep == 1) _advanceToProgress();
      });
    } else if (_tourStep == 2) {
      // Step 2 (Progress) -> Step 3 (Nutrition)
      setState(() => _tourStep = 3);
      _pageController.animateToPage(2,
          duration: _tabSwitchDuration, curve: _tabSwitchCurve);
    } else if (_tourStep == 3) {
      // Step 3 (Nutrition) -> Step 4 (Settings)
      setState(() => _tourStep = 4);
      _pageController.animateToPage(3,
          duration: _tabSwitchDuration, curve: _tabSwitchCurve);
    } else if (_tourStep == 4) {
      // Step 4 (Settings) -> Choose Your Protocol!
      _skipToChooseProtocol();
    }
  }

  void _advanceToProgress() {
    if (!mounted) return;
    setState(() => _tourStep = 2);
    _pageController.animateToPage(1,
        duration: _tabSwitchDuration, curve: _tabSwitchCurve);
  }

  void _skipToChooseProtocol() {
    if (!mounted) return;
    setState(() {
      _showingTour = false;
      _tourStep = 0;
    });
    _pageController.jumpToPage(0);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PlansScreen(isWelcomeOffer: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: Stack(
        children: [
          const Positioned.fill(child: SilenAmbientBackdrop()),
          SafeArea(
            bottom: false,
            child: PageView(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              // Disable swiping while the tour is showing so the user
              // progresses sequentially via the tour card.
              physics:
                  _showingTour ? const NeverScrollableScrollPhysics() : null,
              children: [
                for (var i = 0; i < _screens.length; i++)
                  _AnimatedTab(active: i == _index, child: _screens[i]),
              ],
            ),
          ),
          if (_showingTour && _tourStep != 1)
            Positioned.fill(
              child: TourSpotlightOverlay(
                key: ValueKey(_tourStep),
                targetKey: _currentSpotlightKey,
                stepIndex: _tourStep,
                stepCount: kFeatureTourSteps.length,
                title: kFeatureTourSteps[_tourStep].title,
                description: kFeatureTourSteps[_tourStep].description,
                access: kFeatureTourSteps[_tourStep].access,
                nextLabel: _tourStep == kFeatureTourSteps.length - 1
                    ? 'Choose Protocol'
                    : 'Next',
                cardBottom:
                    SilenBottomNavBar.reservedHeight(context) + AppSpacing.sm,
                onNext: _nextTourStep,
                onSkip: _skipToChooseProtocol,
              ),
            ),
          if (!_showingTour)
            Positioned(
              left: 0,
              right: 0,
              bottom: SilenBottomNavBar.reservedHeight(context) + AppSpacing.sm,
              child: OfflinePill(
                offline: context.read<ApiClient>().isOffline,
                pendingCount: _syncQueue?.pendingCount,
              ),
            ),
        ],
      ),
      bottomNavigationBar: SilenBottomNavBar(
        currentIndex: _index,
        onTap: _showingTour ? (_) {} : _onTabSelected,
      ),
    );
  }
}

/// Wraps one tab's screen so it (a) never gets disposed as the [PageView]
/// scrolls it out of the cache range - matching the old [IndexedStack]'s
/// "state survives forever" guarantee - and (b) plays a quick fade + rise
/// entrance every time it becomes the active tab, whether that's a tap or a
/// swipe landing on it.
class _AnimatedTab extends StatefulWidget {
  final bool active;
  final Widget child;

  const _AnimatedTab({required this.active, required this.child});

  @override
  State<_AnimatedTab> createState() => _AnimatedTabState();
}

class _AnimatedTabState extends State<_AnimatedTab>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final _rise = Tween<Offset>(
    begin: const Offset(0, 0.03),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _AnimatedTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _controller.forward(from: 0);
    } else if (!widget.active && old.active) {
      // Reset (rather than just leaving it at 1) so the next arrival - tap
      // or swipe - always replays the entrance instead of skipping it.
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _rise, child: widget.child),
    );
  }
}
