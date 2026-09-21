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

  @override
  void initState() {
    super.initState();
    _controller = context.read<ProgressController>();
    // Deferred - see the matching comment in today_screen.dart: load()'s
    // first notifyListeners() must not fire synchronously mid-build.
    Future.microtask(_controller.load);
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
                // Header, timeframe pills, and the PR / AI review entry
                // points don't need `overview` - only
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
        // the PR / AI review entry points below.
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
              color: AppColors.onSurface.withValues(alpha: 0.06),
              strokeWidth: 1),
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
                  AppColors.accent.withValues(alpha: 0.16),
                  AppColors.accent.withValues(alpha: 0),
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

/// Keeps the generated report out of the analytics dashboard. The report is
/// fetched only after this entry point is tapped, then rendered exclusively by
/// [MonthlyOverviewScreen].
class _AiMonthlyReviewSection extends StatelessWidget {
  const _AiMonthlyReviewSection();

  @override
  Widget build(BuildContext context) => const _AiReviewEntry(
        title: 'AI Monthly Review',
        description: 'Open your monthly overview',
        tier: 'PRO',
        weekly: false,
      );
}

/// Advanced-only weekly review entry point. As with the monthly entry, no
/// generated content is displayed or requested until the overview is opened.
class _AiWeeklyReviewSection extends StatelessWidget {
  const _AiWeeklyReviewSection();

  @override
  Widget build(BuildContext context) => const _AiReviewEntry(
        title: 'AI Weekly Review',
        description: 'Open your weekly overview',
        tier: 'ADVANCED',
        weekly: true,
      );
}

class _AiReviewEntry extends StatefulWidget {
  final String title;
  final String description;
  final String tier;
  final bool weekly;

  const _AiReviewEntry({
    required this.title,
    required this.description,
    required this.tier,
    required this.weekly,
  });

  @override
  State<_AiReviewEntry> createState() => _AiReviewEntryState();
}

class _AiReviewEntryState extends State<_AiReviewEntry> {
  bool _loading = false;

  Future<void> _open() async {
    if (_loading) return;
    setState(() => _loading = true);

    AnalyticsRecap? report;
    bool requiresUpgrade;
    String? error;
    if (widget.weekly) {
      final controller = context.read<WeeklyAnalyticsController>();
      await controller.load(force: true);
      report = controller.state.data;
      requiresUpgrade = controller.requiresUpgrade;
      error = controller.state.error;
    } else {
      final controller = context.read<AnalyticsController>();
      await controller.load(force: true);
      report = controller.state.data;
      requiresUpgrade = controller.requiresUpgrade;
      error = controller.state.error;
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (requiresUpgrade) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const PlansScreen()));
      return;
    }

    if (report != null) {
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) => MonthlyOverviewScreen(
          analytics: report!,
          onDone: () => Navigator.of(routeContext).pop(),
        ),
      ));
      return;
    }

    final message = error?.trim().isNotEmpty == true
        ? error!
        : 'Your review is not available yet.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _loading ? null : _open,
      child: SectionCard(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(Icons.auto_awesome_rounded,
                  color: AppColors.secondary, size: 20),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: AppTypography.labelSm
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(widget.description,
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(widget.tier,
                  style: AppTypography.labelCaps
                      .copyWith(color: AppColors.onAccent, fontSize: 9)),
            ),
            const SizedBox(width: AppSpacing.xs),
            if (_loading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.secondary),
              )
            else
              Icon(Icons.arrow_forward_rounded,
                  size: 18, color: AppColors.secondary),
          ],
        ),
      ),
    );
  }
}
