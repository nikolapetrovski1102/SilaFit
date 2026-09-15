import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/platform/device_timezone.dart';
import 'core/theme/app_colors.dart';
import 'core/widgets/bottom_nav_bar.dart';
import 'features/auth/account_gate.dart';
import 'features/auth/auth_controller.dart';
import 'features/meals/meal_planning_screen.dart';
import 'features/notifications/notifications_repository.dart';
import 'features/progress/progress_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/today/today_screen.dart';

/// The four-tab shell every top-level screen lives inside. Owns the bottom
/// nav (there's no shared header bar - each screen carries its own large
/// title), and is the one place that enforces "Progress requires a linked
/// account" before switching tabs - the backend also enforces this (403
/// without it), this is just the friendlier UX layer. Plans/pricing is
/// reached from Settings' Subscription row, and workout splits from the
/// active-split card on Home - neither is a tab.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  static const _tabSwitchDuration = Duration(milliseconds: 320);
  static const _tabSwitchCurve = Curves.easeInOutCubic;

  final _pageController = PageController();
  int _index = 0;

  // The interaction ping exists to say "the user is here", so rapid
  // background/resume cycling doesn't need a request each time. Throttled to
  // one report per window; genuinely long absences still land.
  static const _interactionMinGap = Duration(seconds: 30);
  DateTime? _lastInteractionReportUtc;

  static const _screens = [
    TodayScreen(),
    ProgressScreen(),
    MealPlanningScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportInteraction());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reportInteraction();
    }
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
    // ignore: avoid_print
    print('[TAB] onTabSelected($index), current=$_index');
    if (index == _index) return;
    if (index == 1 && !await _ensureProgressUnlocked()) {
      // ignore: avoid_print
      print('[TAB] onTabSelected($index) gate declined, staying put');
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
    // ignore: avoid_print
    print('[TAB] onPageChanged($index), previous=$_index');
    final previous = _index;
    HapticFeedback.selectionClick();
    setState(() => _index = index);
    if (index == 1 && !context.read<AuthController>().isRegistered) {
      // ignore: avoid_print
      print('[TAB] onPageChanged triggering gate for index 1');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // Body paints underneath the floating pill instead of stopping above
      // it - required for SilenBottomNavBar's transparency (Android) and
      // blur (iOS) to actually reveal/soften scrolled content rather than
      // just the flat page background. Each tab compensates by padding its
      // own scrollable content by SilenBottomNavBar.reservedHeight so
      // nothing ends up permanently hidden under the pill.
      extendBody: true,
      // No shared chrome bar - each screen leads with its own large title
      // instead, so this just reserves the status-bar/notch inset that the
      // header used to pad for. `bottom: false` since the bottom nav pill
      // already pads for the home-indicator inset itself.
      //
      // The ambient backdrop sits *outside* the SafeArea, as its own layer
      // behind everything, so its glow bleeds edge to edge (including under
      // the status bar/notch) instead of being inset like real content.
      body: Stack(
        children: [
          const Positioned.fill(child: SilenAmbientBackdrop()),
          SafeArea(
            bottom: false,
            child: PageView(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              children: [
                for (var i = 0; i < _screens.length; i++)
                  _AnimatedTab(active: i == _index, child: _screens[i]),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar:
          SilenBottomNavBar(currentIndex: _index, onTap: _onTabSelected),
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

/// Soft ambient glow behind every tab - two blurred accent-color blobs
/// pinned off-screen at opposite corners, so the flat page background reads
/// as atmosphere rather than a single flat fill. Resolves the accent from the
/// inherited [Theme], rather than [AppColors]'s ambient static value, so this
/// layer is explicitly rebuilt when the app's brightness changes.
///
/// Static (nothing here ever animates), so [RepaintBoundary] lets Flutter
/// rasterize it once and reuse that layer rather than reprocessing the blur
/// every frame - cheap even though the blur radius itself is large.
/// [IgnorePointer] keeps it from stealing any taps meant for the real
/// content stacked on top of it.
class SilenAmbientBackdrop extends StatelessWidget {
  const SilenAmbientBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.paletteFor(brightness).accent;

    return IgnorePointer(
      child: RepaintBoundary(
        // A theme switch must discard the cached blurred layer. Without a
        // color-dependent key, the boundary can retain pixels rasterized for
        // the previous palette even after the surrounding UI has changed.
        key: ValueKey(accent),
        child: ClipRect(
          child: Stack(
            children: [
              Positioned(
                top: -140,
                right: -120,
                child: _GlowBlob(diameter: 340, color: accent),
              ),
              Positioned(
                bottom: -160,
                left: -130,
                child: _GlowBlob(diameter: 380, color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final double diameter;
  final Color color;

  const _GlowBlob({required this.diameter, required this.color});

  @override
  Widget build(BuildContext context) {
    // ImageFiltered blurs this one static shape into a soft glow - unlike
    // BackdropFilter (used for the nav pill's frosted glass) it never needs
    // to keep sampling whatever's moving underneath, so it stays cheap on
    // every platform.
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.28),
        ),
      ),
    );
  }
}
