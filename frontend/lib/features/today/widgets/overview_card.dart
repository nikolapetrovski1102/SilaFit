import '../../../core/widgets/container_transform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/duration_format.dart';
import '../../../core/widgets/mascot/mascot_pose.dart';
import '../../../core/widgets/progress_ring.dart';
import '../../../core/widgets/silen_button.dart';
import '../../splits/splits_models.dart';
import '../today_models.dart';
import 'day_preview.dart';
import 'day_scroll_strip.dart';
import 'set_history_screen.dart';

/// Home's hero: the scrollable day picker and whichever day it's centered
/// on, floating directly on the page background rather than boxed in a
/// card. Order top to bottom: `DayScrollStrip` (today centered by default,
/// history and a couple of weeks of the split's upcoming rotation
/// scrollable either side of it) with a smooth accent line hanging from the
/// centered oval, then that day's session growing straight out of that
/// line. The streak badge itself lives up in Home's header, next to the
/// greeting - see `StreakBadge`.
class TodayOverviewCard extends StatelessWidget {
  final TodayDashboard dashboard;
  final SplitDetail? splitDetail;
  final DateTime? selectedDate;
  final WeekDayStatus? selectedKnownStatus;
  final ValueChanged<DayPreview> onDaySelected;
  final WidgetBuilder workoutBuilder;
  final VoidCallback onWorkoutClosed;
  final double scale;

  /// Whether a still-fresh `ActiveWorkoutDraft` exists for today's session -
  /// see `ActiveWorkoutDraftStore`. Swaps the scheduled-today card's button
  /// from "Start Workout" to "Continue Workout" instead of restarting the
  /// session from scratch.
  final bool isResumingWorkout;

  /// Completed/total sets across that same draft (0-1) - fills the
  /// scheduled-today ring so "how far in am I" reads at a glance from Home,
  /// instead of the ring only ever showing empty until the session is
  /// actually finished.
  final double workoutProgress;

  const TodayOverviewCard({
    super.key,
    required this.dashboard,
    required this.splitDetail,
    required this.selectedDate,
    required this.selectedKnownStatus,
    required this.onDaySelected,
    required this.workoutBuilder,
    required this.onWorkoutClosed,
    this.scale = 1,
    this.isResumingWorkout = false,
    this.workoutProgress = 0,
  });

  @override
  Widget build(BuildContext context) {
    final activeDate = selectedDate ?? dateOnly(DateTime.now());
    final preview = DayPreview.resolve(
      date: activeDate,
      dashboard: dashboard,
      knownStatus: selectedKnownStatus,
      splitDetail: splitDetail,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Bleeds the strip out past the page's own side margins (applied
        // above this, in `TodayScreen`) so the wheel runs edge to edge -
        // the full screen width to center within and scroll across - while
        // everything else in this column stays inset. `Padding` can't take
        // a negative value (it asserts non-negative), so the extra width is
        // granted via `OverflowBox` instead and the horizontal scroller
        // fills it, centered on the same margin either side.
        //
        // The bleed width comes from `MediaQuery`, not the incoming layout
        // constraints: this card lives inside `FitHeight`, which re-lays
        // out its content offstage (in a `Stack`) purely to measure it, and
        // that measuring pass hands non-positioned children *unbounded*
        // width - reading `constraints.maxWidth` there would be infinite.
        //
        // `fit: deferToChild` matters too: the whole page scrolls inside a
        // `SingleChildScrollView`, which always hands its content unbounded
        // *height* (so it can measure scroll extent). The default `.max`
        // fit sizes the OverflowBox itself to `constraints.biggest`, i.e.
        // infinite height, and crashes; `deferToChild` sizes it off its
        // (fixed-height) child instead, while the wider child still
        // overflows and paints past the box horizontally as intended.
        OverflowBox(
          minWidth: 0,
          maxWidth: MediaQuery.sizeOf(context).width,
          fit: OverflowBoxFit.deferToChild,
          child: DayScrollStrip(
            weekStatuses: dashboard.weekStatuses,
            activeSplit: dashboard.activeSplit,
            splitDetail: splitDetail,
            scale: scale,
            onSelect: (date, status) => onDaySelected(DayPreview.resolve(
              date: date,
              dashboard: dashboard,
              knownStatus: status,
              splitDetail: splitDetail,
            )),
          ),
        ),
        SizedBox(height: AppSpacing.xxl * scale),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey(dayKey(preview.date)),
            child: _SessionSection(
              preview: preview,
              workoutBuilder: workoutBuilder,
              onWorkoutClosed: onWorkoutClosed,
              scale: scale,
              isResumingWorkout: isResumingWorkout,
              workoutProgress: workoutProgress,
            ),
          ),
        ),
      ],
    );
  }
}

/// The centered day's session - scheduled, rest day, completed, missed, or
/// an upcoming preview from the active split. Grows straight out of the
/// accent line hanging from the centered oval above it, so it carries the
/// same weight and accent styling as that day marker instead of sitting in
/// a card of its own.
class _SessionSection extends StatelessWidget {
  final DayPreview preview;
  final WidgetBuilder workoutBuilder;
  final VoidCallback onWorkoutClosed;
  final double scale;
  final bool isResumingWorkout;
  final double workoutProgress;

  const _SessionSection({
    required this.preview,
    required this.workoutBuilder,
    required this.onWorkoutClosed,
    required this.scale,
    this.isResumingWorkout = false,
    this.workoutProgress = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (preview.isRestDay) return _buildRestDay();
    if (preview.status == 'Completed') return _buildCompleted(context);
    if (preview.status == 'Missed') return _buildMissed();
    return preview.isToday ? _buildScheduledToday() : _buildUpcomingPreview();
  }

  String get _dateLabel => DateFormat('EEE, MMM d').format(preview.date);

  Widget _buildScheduledToday() {
    final minutesLabel = preview.estimatedMinutes != null
        ? formatMinutesLabel(preview.estimatedMinutes!)
        : 'Duration not set';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(preview.focusLabel?.toUpperCase() ?? 'SCHEDULED TODAY',
                      style: AppTypography.labelCaps.copyWith(
                          color: AppColors.accent, fontSize: 12 * scale)),
                  SizedBox(height: AppSpacing.xxs * scale),
                  Text(preview.title ?? 'Training Session',
                      style: AppTypography.headlineLg
                          .copyWith(fontSize: 32 * scale)),
                ],
              ),
            ),
            SizedBox(width: AppSpacing.md * scale),
            RadialProgressRing(
              // Real set-completion progress once a draft exists (see
              // `workoutProgress`'s doc) - still 0, same as before, for a
              // session that hasn't been opened yet.
              progress: workoutProgress,
              size: 68 * scale,
              strokeWidth: 5.5 * scale,
              child: Icon(Icons.bolt_rounded,
                  color: AppColors.accent, size: 28 * scale),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.lg * scale),
        Row(
          children: [
            Icon(Icons.schedule_rounded,
                color: AppColors.onSurfaceVariant, size: 20 * scale),
            SizedBox(width: AppSpacing.xs * scale),
            Text(minutesLabel,
                style: AppTypography.bodyLg
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ],
        ),
        SizedBox(height: AppSpacing.lg * scale),
        ContainerTransform(
          openBuilder: workoutBuilder,
          onClosed: onWorkoutClosed,
          closedColor: AppColors.accent,
          radius: AppRadius.full,
          closedBuilder: (context, openContainer) => PrimaryPillButton(
              // A fresh `ActiveWorkoutDraft` means there's a session already
              // under way (sets logged, or just the clock already running) -
              // "Start Workout" would read as discarding that instead of
              // picking it back up.
              label: isResumingWorkout ? 'Continue Workout' : 'Start Workout',
              icon: isResumingWorkout
                  ? Icons.play_circle_fill_rounded
                  : Icons.play_arrow_rounded,
              // Never below the spec's 48 tap-target floor, even if the rest
              // of the card ever scaled down.
              height: (48 * scale).clamp(48, 72),
              onPressed: openContainer),
        ),
      ],
    );
  }

  /// A day - future or already gone - that the active split has scheduled
  /// but isn't today, so there's nothing to start: just what's coming up.
  Widget _buildUpcomingPreview() {
    final minutesLabel = preview.estimatedMinutes != null
        ? formatMinutesLabel(preview.estimatedMinutes!)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('UPCOMING · ${_dateLabel.toUpperCase()}',
                      style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 12 * scale)),
                  SizedBox(height: AppSpacing.xxs * scale),
                  Text(preview.title ?? 'Nothing scheduled',
                      style: AppTypography.headlineLg
                          .copyWith(fontSize: 32 * scale)),
                ],
              ),
            ),
            SizedBox(width: AppSpacing.md * scale),
            RadialProgressRing(
              progress: 0,
              size: 68 * scale,
              strokeWidth: 5.5 * scale,
              child: Icon(Icons.event_rounded,
                  color: AppColors.onSurfaceVariant, size: 26 * scale),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.lg * scale),
        Row(
          children: [
            Icon(Icons.schedule_rounded,
                color: AppColors.onSurfaceVariant, size: 20 * scale),
            SizedBox(width: AppSpacing.xs * scale),
            Text(minutesLabel ?? 'No active split to preview',
                style: AppTypography.bodyLg
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ],
        ),
        if (minutesLabel != null) ...[
          SizedBox(height: AppSpacing.lg * scale),
          Row(
            children: [
              Icon(Icons.event_repeat_rounded,
                  color: AppColors.onSurfaceVariant, size: 18 * scale),
              SizedBox(width: AppSpacing.xs * scale),
              Text('From your active split · comes up on $_dateLabel',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildRestDay() {
    final today = dateOnly(DateTime.now());
    final subtitle = preview.isToday
        ? 'No session scheduled. Recovery is part of the program.'
        : preview.date.isBefore(today)
            ? 'Recovery day - no session scheduled.'
            : 'Recovery day coming up in your split.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!preview.isToday) _dateEyebrow(),
              Text('REST DAY',
                  style:
                      AppTypography.headlineLg.copyWith(fontSize: 30 * scale)),
              SizedBox(height: AppSpacing.xxs * scale),
              Text(
                subtitle,
                style: AppTypography.bodyLg
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        SizedBox(width: AppSpacing.md * scale),
        Image.asset(MascotPose.resting.assetPath,
            width: 68 * scale, height: 68 * scale),
      ],
    );
  }

  Widget _buildCompleted(BuildContext context) {
    final subtitle = preview.isToday
        ? 'Completed. Nice work today.'
        : 'Completed on $_dateLabel.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!preview.isToday) _dateEyebrow(),
                  Text(preview.title ?? 'Session',
                      style: AppTypography.headlineLg
                          .copyWith(fontSize: 30 * scale)),
                  SizedBox(height: AppSpacing.xxs * scale),
                  Text(subtitle,
                      style: AppTypography.bodyLg
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            SizedBox(width: AppSpacing.md * scale),
            RadialProgressRing(
              progress: 1,
              size: 68 * scale,
              strokeWidth: 5.5 * scale,
              child: Icon(Icons.check_rounded,
                  color: AppColors.accent, size: 30 * scale),
            ),
          ],
        ),
        // Only offered for a past day - today's own completion already shows
        // in the active tracker it was just logged from.
        if (!preview.isToday) ...[
          SizedBox(height: AppSpacing.lg * scale),
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SetHistoryScreen(
                date: preview.date,
                sessionTitle: preview.title,
              ),
            )),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('View set history',
                    style: AppTypography.labelSm.copyWith(
                        color: AppColors.accent, fontWeight: FontWeight.w600)),
                SizedBox(width: 4 * scale),
                Icon(Icons.arrow_forward_rounded,
                    size: 14 * scale, color: AppColors.accent),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMissed() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dateEyebrow(),
              Text(preview.title ?? 'Session missed',
                  style:
                      AppTypography.headlineLg.copyWith(fontSize: 30 * scale)),
              SizedBox(height: AppSpacing.xxs * scale),
              Text('No session logged for this day.',
                  style: AppTypography.bodyLg
                      .copyWith(color: AppColors.onSurfaceVariant)),
            ],
          ),
        ),
        SizedBox(width: AppSpacing.md * scale),
        Icon(Icons.close_rounded,
            color: AppColors.onSurfaceVariant, size: 36 * scale),
      ],
    );
  }

  Widget _dateEyebrow() {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.xxs * scale),
      child: Text(_dateLabel.toUpperCase(),
          style: AppTypography.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant, fontSize: 12 * scale)),
    );
  }
}
