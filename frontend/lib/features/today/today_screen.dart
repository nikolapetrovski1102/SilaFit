import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_responsive.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/bottom_nav_bar.dart';
import '../../core/widgets/fit_height.dart';
import '../splits/splits_models.dart';
import '../splits/splits_repository.dart';
import 'active_workout_draft_store.dart';
import 'active_workout_tracker_screen.dart';
import 'today_controller.dart';
import 'today_models.dart';
import 'widgets/active_split_card.dart';
import 'widgets/ai_insights_teaser_card.dart';
import 'widgets/day_preview.dart';
import 'widgets/overview_card.dart';
import 'widgets/streak_badge.dart';
import 'widgets/streak_history_sheet.dart';

/// The Today dashboard - the one screen fully wired end to end to the
/// real API, per the project's "solid skeleton + one full slice" scope.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late final TodayController _controller;

  // Which day the strip is currently centered on - null means "today",
  // which always defers to the live dashboard rather than a snapshot, so a
  // workout completed from this same screen shows up immediately instead
  // of through whatever status was known when today was first centered.
  DateTime? _selectedDate;
  WeekDayStatus? _selectedKnownStatus;

  // The active split's day-by-day detail, fetched once so the strip can
  // preview upcoming (and mark upcoming rest) days from its rotation. Not
  // part of the dashboard payload itself, so it's kept and requested here
  // rather than growing `TodayController`'s one fully-wired slice.
  SplitDetail? _splitDetail;
  String? _splitDetailForId;

  // Whether today's session has a still-fresh `ActiveWorkoutDraft` waiting
  // to be resumed - drives "Continue Workout" vs "Start Workout" on the
  // session card, and `_draftProgress` fills its ring to how far into the
  // session that draft already got. Re-checked (via `_draftCheckedForId`
  // being reset back to null) whenever the tracker screen is closed, since
  // finishing/abandoning a workout there doesn't itself trigger a dashboard
  // reload the way `_ensureSplitDetail`'s network-backed check would.
  bool _hasDraft = false;
  double _draftProgress = 0;
  String? _draftCheckedForId;

  @override
  void initState() {
    super.initState();
    _controller = context.read<TodayController>();
    // Deferred a tick so the controller's first `notifyListeners()` (inside
    // `load()`) never fires synchronously mid-build - it would otherwise hit
    // Provider's "setState() called during build" guard, since `initState`
    // runs while this screen's own element is still being mounted.
    Future.microtask(_controller.load);
  }

  void _onDaySelected(DayPreview preview) {
    setState(() {
      _selectedDate = preview.date;
      _selectedKnownStatus = preview.isToday
          ? null
          : WeekDayStatus(date: preview.date, status: preview.status);
    });
  }

  Future<void> _ensureSplitDetail(TodayDashboard dashboard) async {
    final split = dashboard.activeSplit;
    if (split == null) {
      _splitDetailForId = null;
      if (_splitDetail != null) setState(() => _splitDetail = null);
      return;
    }
    if (split.splitId == _splitDetailForId) return;
    _splitDetailForId = split.splitId;
    try {
      final detail = await context.read<SplitsRepository>().getDetail(split.splitId);
      if (!mounted || _splitDetailForId != split.splitId) return;
      setState(() => _splitDetail = detail);
    } catch (_) {
      // Secondary affordance (future-day previews) - not worth an error
      // banner; the strip just falls back to a bare "Scheduled" placeholder
      // for days it can't resolve a split day for.
    }
  }

  Future<void> _ensureDraftCheck(TodayDashboard dashboard) async {
    final sessionId = dashboard.session.workoutSessionId;
    if (sessionId == null) {
      _draftCheckedForId = null;
      if (_hasDraft) setState(() { _hasDraft = false; _draftProgress = 0; });
      return;
    }
    if (sessionId == _draftCheckedForId) return;
    _draftCheckedForId = sessionId;
    // Loads the full draft (not just a fresh/not-fresh bool) so the ring
    // can show real progress rather than snapping straight from empty to
    // whatever "Continue Workout" alone would imply.
    final draft = await ActiveWorkoutDraftStore.instance.load(sessionId);
    if (!mounted || _draftCheckedForId != sessionId) return;
    setState(() {
      _hasDraft = draft != null;
      _draftProgress = draft?.completionRatio ?? 0;
    });
  }

  /// Re-arms [_ensureDraftCheck] to actually re-check on the next build,
  /// rather than trusting its cached `_draftCheckedForId` - called once the
  /// tracker screen (pushed from `_TodayContent.onStart`) is popped, since
  /// neither finishing nor abandoning a workout there changes
  /// `dashboard.session.workoutSessionId` itself in a way that would
  /// otherwise prompt a re-check.
  void _onWorkoutScreenClosed() {
    if (!mounted) return;
    setState(() => _draftCheckedForId = null);
  }

  @override
  Widget build(BuildContext context) {
    // Home's dashboard is fit (via FitHeight, in _buildBody) to end above
    // the nav pill rather than scroll, so - unlike Progress/Nutrition/
    // Settings, whose lists scroll real content behind the pill - nothing
    // ever sits behind it here, and a flat page background gives the iOS
    // blur no detail to soften. FitHeight rescales the dashboard on every
    // load/refresh (its measureKey), which moves exactly where its content
    // ends - so a vignette pinned to a fixed *percentage of the screen*
    // drifts out of sync with that boundary and can land on top of the
    // cards instead of in the empty space below them. Anchoring this to the
    // nav bar's own reserved footprint instead keeps it structurally
    // confined to that empty band, however the dashboard is scaled.
    final navReserved = SilenBottomNavBar.reservedHeight(context);
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: navReserved,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.surfaceContainer.withOpacity(0),
                    AppColors.surfaceContainer.withOpacity(0.35),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildBody(context),
      ],
    );
  }

  // Captured just inside the tab's own body (RootShell's SafeArea already
  // stripped the status bar). RootShell's Scaffold runs `extendBody: true`
  // so the nav pill can float over scrolled/blurred content, which means
  // this LayoutBuilder's raw constraint now reaches all the way to the
  // physical bottom edge - subtract the pill's own footprint back out so
  // FitHeight still fits content into the same visible budget as before,
  // instead of sizing it to spill under the pill.
  Widget _buildBody(BuildContext context) {
    return LayoutBuilder(
      builder: (context, viewport) {
        final navReserved = SilenBottomNavBar.reservedHeight(context);
        final viewportHeight = viewport.maxHeight - navReserved;
        // Rough guess for the very first frame only - `FitHeight` measures
        // the actual content on the next frame and corrects to the exact
        // scale that fills the viewport, growing or shrinking everything
        // (type, icons, spacing) together rather than leaving dead space
        // or forcing a scroll.
        final seedScale = AppResponsive.scaleFor(context, viewportHeight);
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            // No pull-to-refresh on Home - it reloads on its own whenever the
            // tab mounts or an action changes its data (`ActiveSplitCard`,
            // `completeWorkout`, ...), and `NeverScrollableScrollPhysics`
            // keeps the page itself from ever moving under a drag.
            // `SingleChildScrollView` still wraps it as a silent safety net,
            // not a scroll surface: the rare case content can't be shrunk
            // enough to fit (a very short screen plus a large accessibility
            // text size) just has its excess sit inertly off the bottom
            // edge instead of throwing a hard overflow error.
            return SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: ResourceBuilder<TodayDashboard>(
                state: _controller.state,
                onRetry: _controller.load,
                builder: (context, dashboard) {
                  unawaited(_ensureSplitDetail(dashboard));
                  unawaited(_ensureDraftCheck(dashboard));
                  return FitHeight(
                    availableHeight: viewportHeight,
                    initialScale: seedScale,
                    minScale: 0.82,
                    maxScale: 1.6,
                    // Remeasure whenever the content that could change its
                    // natural height changes - a new load, a different
                    // session/split, or the strip settling on a different
                    // day (a rest day, a missed day and a full scheduled
                    // session all want a different natural height).
                    measureKey: (dashboard, _selectedDate),
                    builder: (scale) => Padding(
                      padding: EdgeInsets.fromLTRB(
                          AppSpacing.marginMobile,
                          AppSpacing.md * scale,
                          AppSpacing.marginMobile,
                          AppSpacing.sm),
                      child: _TodayContent(
                        controller: _controller,
                        dashboard: dashboard,
                        splitDetail: _splitDetail,
                        selectedDate: _selectedDate,
                        selectedKnownStatus: _selectedKnownStatus,
                        onDaySelected: _onDaySelected,
                        scale: scale,
                        isResumingWorkout: _hasDraft,
                        workoutProgress: _draftProgress,
                        onWorkoutScreenClosed: _onWorkoutScreenClosed,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _TodayContent extends StatelessWidget {
  final TodayController controller;
  final TodayDashboard dashboard;
  final SplitDetail? splitDetail;
  final DateTime? selectedDate;
  final WeekDayStatus? selectedKnownStatus;
  final ValueChanged<DayPreview> onDaySelected;
  final double scale;
  final bool isResumingWorkout;
  final double workoutProgress;
  final VoidCallback onWorkoutScreenClosed;

  const _TodayContent({
    required this.controller,
    required this.dashboard,
    required this.splitDetail,
    required this.selectedDate,
    required this.selectedKnownStatus,
    required this.onDaySelected,
    required this.scale,
    required this.isResumingWorkout,
    required this.workoutProgress,
    required this.onWorkoutScreenClosed,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final dateLabel = DateFormat('EEEE, MMM d').format(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Plain-text greeting, no boxed date pill - this page's own large
        // title, standing in for the removed shared header bar. The streak
        // badge sits up here next to it (rather than floating over the day
        // row below) so it reads as part of Home's header at a glance.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greeting,
                      style: AppTypography.headlineLg.copyWith(fontSize: 28 * scale)),
                  SizedBox(height: 2 * scale),
                  Text(dateLabel,
                      style: AppTypography.bodyMd
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            StreakBadge(
              streakDays: dashboard.currentStreakDays,
              scale: scale,
              onTap: () => showStreakHistorySheet(
                context,
                currentStreakDays: dashboard.currentStreakDays,
                weeklyCompliancePercent: dashboard.weeklyCompliancePercent,
              ),
            ),
          ],
        ),
        // Extra room above the day strip - keeps it from crowding the
        // greeting now that it's a scrollable row rather than a fixed one.
        SizedBox(height: AppSpacing.xxxl * scale),
        // Streak/calendar and today's session combined into one flowing
        // block - "am I on track" and "what do I do today" read as a single
        // glance instead of two stacked boxes.
        TodayOverviewCard(
          dashboard: dashboard,
          splitDetail: splitDetail,
          selectedDate: selectedDate,
          selectedKnownStatus: selectedKnownStatus,
          onDaySelected: onDaySelected,
          scale: scale,
          isResumingWorkout: isResumingWorkout,
          workoutProgress: workoutProgress,
          onStart: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => ActiveWorkoutTrackerScreen(
                      session: dashboard.session,
                      exercises: dashboard.targetExercises,
                      controller: controller)),
            );
            // The tracker screen may have saved, cleared, or left untouched
            // an `ActiveWorkoutDraft` for this same session - re-check
            // rather than trust whatever "Continue Workout" showed before
            // it was pushed.
            onWorkoutScreenClosed();
          },
        ),
        SizedBox(height: AppSpacing.xl * scale),
        ActiveSplitCard(activeSplit: dashboard.activeSplit, scale: scale),
        SizedBox(height: AppSpacing.md * scale),
        AiInsightsTeaserCard(scale: scale),
      ],
    );
  }
}
