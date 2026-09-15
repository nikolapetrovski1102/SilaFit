import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/bottom_nav_bar.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../plans/plans_screen.dart';
import 'analytics_controller.dart';
import 'analytics_models.dart';
import 'monthly_overview_screen.dart';
import 'progress_controller.dart';
import 'progress_models.dart';
import 'weekly_analytics_controller.dart';

/// The AI-narrated progress screen. Registered-tier only - the caller
/// (RootShell) runs it through AccountGate before this ever mounts.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late final ProgressController _controller;
  late final AnalyticsController _analyticsController;
  late final WeeklyAnalyticsController _weeklyAnalyticsController;

  @override
  void initState() {
    super.initState();
    _controller = context.read<ProgressController>();
    _analyticsController = context.read<AnalyticsController>();
    _weeklyAnalyticsController = context.read<WeeklyAnalyticsController>();
    // Deferred - see the matching comment in today_screen.dart: load()'s
    // first notifyListeners() must not fire synchronously mid-build.
    Future.microtask(_controller.load);
    Future.microtask(_analyticsController.load);
    Future.microtask(_weeklyAnalyticsController.load);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, viewport) {
            return RefreshIndicator(
              onRefresh: () => _controller.load(force: true),
              color: AppColors.accent,
              backgroundColor: AppColors.surfaceContainer,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                // Bottom padding clears the floating nav pill (now that
                // RootShell's Scaffold extends its body under it) plus the
                // usual breathing room, so the last card scrolls up past the
                // pill instead of staying hidden beneath it.
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.marginMobile,
                    AppSpacing.lg,
                    AppSpacing.marginMobile,
                    AppSpacing.sm + SilenBottomNavBar.reservedHeight(context)),
                // Header, timeframe pills, and the independently-loaded PR /
                // AI review sections don't need `overview` - only
                // `_StrengthProgressCard` and `_YourInsightCard` do. Gating
                // all of that behind one ResourceBuilder used to blank the
                // whole screen (title included) whenever the overview call
                // alone was slow or failed; now a stalled/errored overview
                // only empties its own two cards.
                child: _ProgressContent(controller: _controller),
              ),
            );
          },
        );
      },
    );
  }
}

class _ProgressContent extends StatelessWidget {
  final ProgressController controller;

  const _ProgressContent({required this.controller});

  static const _timeframes = [
    (30, '1M'),
    (90, '3M'),
    (180, '6M'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionEyebrow('Performance', color: AppColors.accent),
        const SizedBox(height: 4),
        Text('Your progress', style: AppTypography.headlineLg),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            for (final (days, label) in _timeframes) ...[
              PillChip(
                label: label,
                selected: controller.days == days,
                onTap: () => controller.setDays(days),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        // Only these two cards depend on `controller.state` (the overview
        // call) - scoping the ResourceBuilder to just them means a slow or
        // failed overview fetch no longer blanks the header/pills above or
        // the independently-loaded PR / AI review sections below.
        ResourceBuilder<ProgressOverview>(
          state: controller.state,
          onRetry: controller.load,
          builder: (context, overview) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StrengthProgressCard(overview: overview),
              const SizedBox(height: AppSpacing.lg),
              _YourInsightCard(
                  insight: overview.insights.isNotEmpty
                      ? overview.insights.first
                      : null),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _PersonalRecordsCard(controller: controller),
        const SizedBox(height: AppSpacing.lg),
        const _AiMonthlyReviewSection(),
        const SizedBox(height: AppSpacing.lg),
        const _AiWeeklyReviewSection(),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// One calendar week's worth of the heatmap, reduced to summed tonnage - the
/// only series the hero card can honestly plot as "strength progress"; no
/// per-exercise 1RM history exists to derive a truer strength curve from.
class _WeekBucket {
  final DateTime start;
  final double totalTonnageKg;

  const _WeekBucket({required this.start, required this.totalTonnageKg});
}

List<_WeekBucket> _weeklyBuckets(List<HeatmapDay> days) {
  if (days.isEmpty) return [];
  final sorted = [...days]..sort((a, b) => a.date.compareTo(b.date));
  final buckets = <_WeekBucket>[];
  DateTime? bucketStart;
  var tonnage = 0.0;

  void flush() {
    if (bucketStart == null) return;
    buckets.add(_WeekBucket(start: bucketStart, totalTonnageKg: tonnage));
  }

  for (final day in sorted) {
    bucketStart ??= day.date;
    if (day.date.difference(bucketStart).inDays >= 7) {
      flush();
      bucketStart = day.date;
      tonnage = 0;
    }
    if (day.tonnageKg != null) tonnage += day.tonnageKg!;
  }
  flush();
  return buckets;
}

/// Percent change from the first to the last weekly bucket - `null` when
/// there isn't enough range to compare, or the starting point was zero.
double? _percentChange(List<_WeekBucket> buckets) {
  if (buckets.length < 2) return null;
  final first = buckets.first.totalTonnageKg;
  final last = buckets.last.totalTonnageKg;
  if (first <= 0) return null;
  return (last - first) / first * 100;
}

class _StrengthProgressCard extends StatelessWidget {
  final ProgressOverview overview;

  const _StrengthProgressCard({required this.overview});

  @override
  Widget build(BuildContext context) {
    final buckets = _weeklyBuckets(overview.heatmap);
    final pct = _percentChange(buckets);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionEyebrow('Strength Progress'),
          const SizedBox(height: AppSpacing.sm),
          Text(
            pct == null
                ? '--'
                : '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
            style: AppTypography.displayStatMobile.copyWith(
                color: pct == null
                    ? AppColors.onSurfaceVariant
                    : (pct >= 0 ? AppColors.accent : AppColors.error)),
          ),
          const SizedBox(height: 2),
          Text('Overall strength',
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.md),
          if (buckets.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: Text('Log a few sessions to see your trend.',
                      style: AppTypography.bodySm)),
            )
          else
            SizedBox(height: 140, child: _TrendChart(buckets: buckets)),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<_WeekBucket> buckets;

  const _TrendChart({required this.buckets});

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < buckets.length; i++)
        FlSpot(i.toDouble(), buckets[i].totalTonnageKg),
    ];
    final maxValue =
        buckets.map((b) => b.totalTonnageKg).reduce((a, b) => a > b ? a : b);
    final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.2;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 3,
          getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.onSurface.withOpacity(0.06), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              // Only the first and last week get a date label - the mockup
              // shows a plain start/end range under the sparkline, not a
              // tick per week.
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i != 0 && i != buckets.length - 1) {
                  return const SizedBox.shrink();
                }
                final isLast = i == buckets.length - 1;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('MMM d').format(buckets[i].start),
                    style: AppTypography.labelCaps.copyWith(
                        fontSize: 10,
                        color: isLast ? AppColors.accent : AppColors.outline),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceContainerHighest,
            getTooltipItems: (touchedSpots) => [
              for (final spot in touchedSpots)
                LineTooltipItem(
                  '${spot.y.toStringAsFixed(0)} kg\n${DateFormat('MMM d').format(buckets[spot.x.round()].start)}',
                  AppTypography.labelSm.copyWith(color: AppColors.onSurface),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: AppColors.accent,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) {
                final isLast = index == spots.length - 1;
                return FlDotCirclePainter(
                  radius: isLast ? 5 : 3,
                  color: isLast ? AppColors.accent : AppColors.surfaceContainer,
                  strokeColor: isLast ? AppColors.accent : AppColors.outline,
                  strokeWidth: 1.5,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.accent.withOpacity(0.16),
                  AppColors.accent.withOpacity(0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatPrWeight(double kg) =>
    kg % 1 == 0 ? kg.toStringAsFixed(0) : kg.toStringAsFixed(1);

/// Real per-exercise Personal Records - the heaviest set ever logged for
/// each exercise (see `usp_WorkoutSession_GetPersonalRecords`), sourced from
/// [ProgressController.prsState] rather than mock data. That state loads
/// independently of the overview (see the controller), so this card has its
/// own loading/error/empty rendering instead of gating on the page's
/// [ResourceBuilder].
class _PersonalRecordsCard extends StatelessWidget {
  final ProgressController controller;

  const _PersonalRecordsCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final state = controller.prsState;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionEyebrow('Personal Records'),
          const SizedBox(height: AppSpacing.md),
          if (state.isLoading)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppColors.accent),
                ),
              ),
            )
          else if (state.error != null)
            Text(state.error!, style: AppTypography.bodySm)
          else if (state.data == null || state.data!.isEmpty)
            Text('Log a set during a workout to start tracking PRs.',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant))
          else
            for (final record in state.data!)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(Icons.emoji_events_rounded,
                        size: 18, color: AppColors.secondary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(record.exerciseName,
                          style: AppTypography.bodyMd,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                        '${_formatPrWeight(record.weightKg)} kg × ${record.reps}',
                        style: AppTypography.numericUnit
                            .copyWith(fontWeight: FontWeight.w600)),
                    if (record.deltaKg != null && record.deltaKg! > 0) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Text('+${_formatPrWeight(record.deltaKg!)}',
                          style: AppTypography.labelSm
                              .copyWith(color: AppColors.accent)),
                    ],
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _YourInsightCard extends StatelessWidget {
  final String? insight;

  const _YourInsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      background: AppColors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionEyebrow('Your Insight', color: AppColors.accent),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '"${insight ?? 'Log a few more sessions to unlock your first insight.'}"',
            style: AppTypography.bodyLg.copyWith(
                color: AppColors.onSurface, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

/// AI Monthly Review entry point - a locked upsell button for Free tier
/// (matching the design's "AI MONTHLY REVIEW · PRO" bracket button), or the
/// real generated report inline for Pro once it has data.
class _AiMonthlyReviewSection extends StatelessWidget {
  const _AiMonthlyReviewSection();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AnalyticsController>();

    if (controller.requiresUpgrade) {
      return const _AiReviewUpsellButton(
          label: 'AI MONTHLY REVIEW', tier: 'PRO');
    }

    final state = controller.state;

    if (controller.notEnoughData) {
      return _AiRecapNotice(
        title: 'AI Monthly Review',
        icon: Icons.insights_outlined,
        message: state.error != null && state.error!.isNotEmpty
            ? state.error!
            : "Log a bit more this month and your AI review will unlock once there's enough to analyze.",
        isRefreshing: controller.isRefreshing,
        onRefresh: controller.refresh,
      );
    }

    if (state.error != null && state.error!.isNotEmpty) {
      return _AiRecapNotice(
        title: 'AI Monthly Review',
        message: state.error!,
        isRefreshing: controller.isRefreshing,
        onRefresh: controller.refresh,
      );
    }

    if (!state.hasData) {
      return _AiRecapLoading(
        title: 'AI Monthly Review',
        isRefreshing: controller.isRefreshing,
        onRefresh: controller.refresh,
      );
    }

    return _AiRecapCard(
      title: 'AI Monthly Review',
      analytics: state.data!,
      isRefreshing: controller.isRefreshing,
      onRefresh: controller.refresh,
    );
  }
}

class _AiInsightsHeader extends StatelessWidget {
  final String title;
  final bool isRefreshing;
  final VoidCallback onRefresh;

  const _AiInsightsHeader({
    required this.title,
    required this.isRefreshing,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SectionEyebrow(title, color: AppColors.accent),
        IconButton(
          onPressed: isRefreshing ? null : onRefresh,
          icon: isRefreshing
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.onSurfaceVariant))
              : Icon(Icons.refresh_rounded,
                  size: 18, color: AppColors.onSurfaceVariant),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          splashRadius: 18,
        ),
      ],
    );
  }
}

/// The inline AI recap card, shared by the monthly (Pro) and weekly (Advanced)
/// sections - both report shapes satisfy [AnalyticsRecap], so the same body
/// works and only the title/link copy differ.
class _AiRecapCard extends StatelessWidget {
  final String title;
  final AnalyticsRecap analytics;
  final bool isRefreshing;
  final VoidCallback onRefresh;

  const _AiRecapCard({
    required this.title,
    required this.analytics,
    required this.isRefreshing,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final periodWord = analytics.isWeekly ? 'week' : 'month';
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AiInsightsHeader(
              title: title, isRefreshing: isRefreshing, onRefresh: onRefresh),
          const SizedBox(height: 2),
          Text(analytics.periodLabel,
              style: AppTypography.labelCaps
                  .copyWith(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.sm),
          if (analytics.strengths.isNotEmpty) ...[
            Text('STRENGTHS',
                style:
                    AppTypography.labelCaps.copyWith(color: AppColors.accent)),
            const SizedBox(height: 6),
            for (final strength in analytics.strengths)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(strength,
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.onSurface)),
              ),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (analytics.improvements.isNotEmpty) ...[
            Text('IMPROVEMENTS',
                style: AppTypography.labelCaps
                    .copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 6),
            for (final improvement in analytics.improvements)
              _ImprovementTile(improvement: improvement),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (analytics.focusText.isNotEmpty) ...[
            Text('FOCUS FOR NEXT ${periodWord.toUpperCase()}',
                style: AppTypography.labelCaps
                    .copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text(analytics.focusText,
                style:
                    AppTypography.bodySm.copyWith(color: AppColors.onSurface)),
          ],
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (routeContext) => MonthlyOverviewScreen(
                  analytics: analytics,
                  onDone: () => Navigator.of(routeContext).pop(),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                    'View full ${analytics.isWeekly ? 'weekly' : 'monthly'} recap',
                    style: AppTypography.labelSm.copyWith(
                        color: AppColors.accent, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded,
                    size: 14, color: AppColors.accent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared non-report state for both AI recap sections - the "not enough data"
/// encouraging card and the generic error card.
class _AiRecapNotice extends StatelessWidget {
  final String title;
  final String message;
  final bool isRefreshing;
  final VoidCallback onRefresh;
  final IconData? icon;

  const _AiRecapNotice({
    required this.title,
    required this.message,
    required this.isRefreshing,
    required this.onRefresh,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AiInsightsHeader(
              title: title, isRefreshing: isRefreshing, onRefresh: onRefresh),
          const SizedBox(height: AppSpacing.sm),
          if (icon == null)
            Text(message, style: AppTypography.bodySm)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: AppColors.onSurfaceVariant),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(message,
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Shared loading state for both AI recap sections.
class _AiRecapLoading extends StatelessWidget {
  final String title;
  final bool isRefreshing;
  final VoidCallback onRefresh;

  const _AiRecapLoading({
    required this.title,
    required this.isRefreshing,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AiInsightsHeader(
              title: title, isRefreshing: isRefreshing, onRefresh: onRefresh),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: AppColors.accent),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _ImprovementTile extends StatelessWidget {
  final AnalyticsImprovement improvement;

  const _ImprovementTile({required this.improvement});

  Color get _priorityColor => switch (improvement.priority) {
        'High' => AppColors.error,
        'Low' => AppColors.onSurfaceVariant,
        _ => AppColors.secondary,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(improvement.area,
                    style: AppTypography.labelSm
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: _priorityColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppRadius.full)),
                child: Text(improvement.priority.toUpperCase(),
                    style: AppTypography.labelCaps
                        .copyWith(color: _priorityColor, fontSize: 9)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(improvement.recommendation,
              style: AppTypography.bodySm.copyWith(color: AppColors.onSurface)),
        ],
      ),
    );
  }
}

/// Locked upsell button for a user below the required tier - the bracketed
/// "AI MONTHLY REVIEW · PRO" / "WEEKLY AI REVIEW · ADVANCED" pill, routing
/// into Plans.
class _AiReviewUpsellButton extends StatelessWidget {
  final String label;
  final String tier;

  const _AiReviewUpsellButton({required this.label, required this.tier});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PlansScreen()),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: AppColors.secondary.withOpacity(0.4)),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded,
                size: 16, color: AppColors.secondary),
            const SizedBox(width: AppSpacing.xs),
            Text(label,
                style: AppTypography.labelCaps
                    .copyWith(color: AppColors.secondary)),
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(AppRadius.full)),
              child: Text(tier,
                  style: AppTypography.labelCaps
                      .copyWith(color: AppColors.onAccent, fontSize: 9)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Advanced-only weekly AI review entry point. A Pro user sees the locked
/// "WEEKLY AI REVIEW · ADVANCED" upsell; an Advanced user gets the inline
/// weekly report, whose full recap appends the meal/split suggestion slides.
class _AiWeeklyReviewSection extends StatelessWidget {
  const _AiWeeklyReviewSection();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WeeklyAnalyticsController>();

    if (controller.requiresUpgrade) {
      return const _AiReviewUpsellButton(
          label: 'WEEKLY AI REVIEW', tier: 'ADVANCED');
    }

    final state = controller.state;

    if (controller.notEnoughData) {
      return _AiRecapNotice(
        title: 'AI Weekly Review',
        icon: Icons.insights_outlined,
        message: state.error != null && state.error!.isNotEmpty
            ? state.error!
            : "Log a bit more this week and your weekly review will unlock once there's enough to analyze.",
        isRefreshing: controller.isRefreshing,
        onRefresh: controller.refresh,
      );
    }

    if (state.error != null && state.error!.isNotEmpty) {
      return _AiRecapNotice(
        title: 'AI Weekly Review',
        message: state.error!,
        isRefreshing: controller.isRefreshing,
        onRefresh: controller.refresh,
      );
    }

    if (!state.hasData) {
      return _AiRecapLoading(
        title: 'AI Weekly Review',
        isRefreshing: controller.isRefreshing,
        onRefresh: controller.refresh,
      );
    }

    return _AiRecapCard(
      title: 'AI Weekly Review',
      analytics: state.data!,
      isRefreshing: controller.isRefreshing,
      onRefresh: controller.refresh,
    );
  }
}
