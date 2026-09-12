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
import '../../core/widgets/slim_action_row.dart';
import '../plans/plans_screen.dart';
import 'analytics_controller.dart';
import 'analytics_models.dart';
import 'progress_controller.dart';
import 'progress_models.dart';

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

  @override
  void initState() {
    super.initState();
    _controller = context.read<ProgressController>();
    _analyticsController = context.read<AnalyticsController>();
    // Deferred - see the matching comment in today_screen.dart: load()'s
    // first notifyListeners() must not fire synchronously mid-build.
    Future.microtask(_controller.load);
    Future.microtask(_analyticsController.load);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return RefreshIndicator(
          onRefresh: _controller.load,
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
            child: ResourceBuilder<ProgressOverview>(
              state: _controller.state,
              onRetry: _controller.load,
              builder: (context, overview) =>
                  _ProgressContent(controller: _controller, overview: overview),
            ),
          ),
        );
      },
    );
  }
}

class _ProgressContent extends StatelessWidget {
  final ProgressController controller;
  final ProgressOverview overview;

  const _ProgressContent({required this.controller, required this.overview});

  static const _timeframes = [
    (7, '7D'),
    (30, '1M'),
    (90, '3M'),
    (180, '6M'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionEyebrow('Performance Analytics', color: AppColors.accent),
        const SizedBox(height: 4),
        Text('Progression & Metrics', style: AppTypography.headlineLg),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _timeframes.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
            itemBuilder: (context, i) {
              final (days, label) = _timeframes[i];
              return PillChip(
                label: label,
                selected: controller.days == days,
                onTap: () => controller.setDays(days),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _TrendChartCard(controller: controller, overview: overview),
        const SizedBox(height: AppSpacing.lg),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.5,
          children: [
            _StatTile(
                label: 'STREAK',
                value: '${overview.currentStreakDays}',
                suffix: 'days'),
            _StatTile(
                label: 'COMPLIANCE',
                value: '${overview.weeklyCompliancePercent}',
                suffix: '%'),
            _StatTile(
                label: 'SESSIONS',
                value: '${overview.completedSessions}',
                suffix: '/ ${overview.scheduledSessions}'),
            _StatTile(
                label: 'TONNAGE',
                value: overview.totalTonnageKg.toStringAsFixed(0),
                suffix: 'kg'),
            _StatTile(
                label: 'AVG RPE',
                value: overview.avgRpe > 0
                    ? overview.avgRpe.toStringAsFixed(1)
                    : '-',
                suffix: '/ 10'),
            _StatTile(
                label: 'PEAK WEEK',
                value: _weeklyBuckets(overview.heatmap)
                    .fold<double>(0, (max, b) => b.totalTonnageKg > max ? b.totalTonnageKg : max)
                    .toStringAsFixed(0),
                suffix: 'kg'),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _InsightsCard(insights: overview.insights),
        const SizedBox(height: AppSpacing.lg),
        const _AiInsightsSection(),
        const SizedBox(height: AppSpacing.lg),
        const _ProForecastCard(),
        const SizedBox(height: AppSpacing.lg),
        const SectionEyebrow('Consistency Matrix'),
        const SizedBox(height: AppSpacing.sm),
        _HeatmapGrid(days: overview.heatmap),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// One calendar week's worth of the heatmap, reduced to the three series the
/// hero chart can plot: completed-session count (always available), summed
/// tonnage, and average RPE (both only as real as what WorkoutSessions
/// actually logged - no per-exercise 1RM history exists to chart instead).
class _WeekBucket {
  final DateTime start;
  final int completedCount;
  final double totalTonnageKg;
  final double? avgRpe;

  const _WeekBucket({
    required this.start,
    required this.completedCount,
    required this.totalTonnageKg,
    required this.avgRpe,
  });

  double valueFor(TrendMetric metric) => switch (metric) {
        TrendMetric.sessions => completedCount.toDouble(),
        TrendMetric.volume => totalTonnageKg,
        TrendMetric.rpe => avgRpe ?? 0,
      };
}

List<_WeekBucket> _weeklyBuckets(List<HeatmapDay> days) {
  if (days.isEmpty) return [];
  final sorted = [...days]..sort((a, b) => a.date.compareTo(b.date));
  final buckets = <_WeekBucket>[];
  DateTime? bucketStart;
  var count = 0;
  var tonnage = 0.0;
  final rpeValues = <double>[];

  void flush() {
    if (bucketStart == null) return;
    buckets.add(_WeekBucket(
      start: bucketStart,
      completedCount: count,
      totalTonnageKg: tonnage,
      avgRpe: rpeValues.isEmpty
          ? null
          : rpeValues.reduce((a, b) => a + b) / rpeValues.length,
    ));
  }

  for (final day in sorted) {
    bucketStart ??= day.date;
    if (day.date.difference(bucketStart).inDays >= 7) {
      flush();
      bucketStart = day.date;
      count = 0;
      tonnage = 0;
      rpeValues.clear();
    }
    if (day.status == 'Completed') count++;
    if (day.tonnageKg != null) tonnage += day.tonnageKg!;
    if (day.rpeScore != null) rpeValues.add(day.rpeScore!);
  }
  flush();
  return buckets;
}

extension on TrendMetric {
  String get headerLabel => switch (this) {
        TrendMetric.sessions => 'SESSIONS COMPLETED',
        TrendMetric.volume => 'TOTAL VOLUME',
        TrendMetric.rpe => 'AVERAGE RPE',
      };

  String get pillLabel => switch (this) {
        TrendMetric.sessions => 'Sessions',
        TrendMetric.volume => 'Volume',
        TrendMetric.rpe => 'RPE',
      };

  String get unit => switch (this) {
        TrendMetric.sessions => 'sessions',
        TrendMetric.volume => 'kg',
        TrendMetric.rpe => 'RPE',
      };
}

class _TrendChartCard extends StatelessWidget {
  final ProgressController controller;
  final ProgressOverview overview;

  const _TrendChartCard({required this.controller, required this.overview});

  @override
  Widget build(BuildContext context) {
    final buckets = _weeklyBuckets(overview.heatmap);
    final metric = controller.metric;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(metric.headerLabel,
                        style: AppTypography.labelCaps
                            .copyWith(color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    _TrendHeaderValue(overview: overview, metric: metric),
                  ],
                ),
              ),
              if (buckets.length > 1)
                _TrendBadge(buckets: buckets, metric: metric),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final m in TrendMetric.values) ...[
                _MetricPill(
                  label: m.pillLabel,
                  selected: metric == m,
                  onTap: () => controller.setMetric(m),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (buckets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: Text('Log a few sessions to see your trend.',
                      style: AppTypography.bodySm)),
            )
          else
            SizedBox(
                height: 160,
                child: _TrendChart(buckets: buckets, metric: metric)),
        ],
      ),
    );
  }
}

class _TrendHeaderValue extends StatelessWidget {
  final ProgressOverview overview;
  final TrendMetric metric;

  const _TrendHeaderValue({required this.overview, required this.metric});

  @override
  Widget build(BuildContext context) {
    final (value, suffix) = switch (metric) {
      TrendMetric.sessions => (
          '${overview.completedSessions}',
          'of ${overview.scheduledSessions}'
        ),
      TrendMetric.volume => (overview.totalTonnageKg.toStringAsFixed(0), 'kg lifted'),
      TrendMetric.rpe => (overview.avgRpe.toStringAsFixed(1), '/ 10 intensity'),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value, style: AppTypography.displayStatMobile),
        const SizedBox(width: 4),
        Text(suffix,
            style: AppTypography.numericUnit
                .copyWith(color: AppColors.onSurfaceVariant)),
      ],
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MetricPill(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
        decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.full)),
        child: Text(label,
            style: AppTypography.labelSm.copyWith(
                color: selected ? AppColors.onAccent : AppColors.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  final List<_WeekBucket> buckets;
  final TrendMetric metric;

  const _TrendBadge({required this.buckets, required this.metric});

  @override
  Widget build(BuildContext context) {
    final delta = buckets.last.valueFor(metric) - buckets.first.valueFor(metric);
    final up = delta >= 0;
    final deltaLabel = metric == TrendMetric.sessions
        ? delta.round().toString()
        : delta.toStringAsFixed(1);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 14, color: AppColors.accent),
          const SizedBox(width: 4),
          Text('${delta >= 0 ? '+' : ''}$deltaLabel / wk',
              style: AppTypography.labelSm
                  .copyWith(color: AppColors.accent, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<_WeekBucket> buckets;
  final TrendMetric metric;

  const _TrendChart({required this.buckets, required this.metric});

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < buckets.length; i++)
        FlSpot(i.toDouble(), buckets[i].valueFor(metric)),
    ];
    final maxValue =
        buckets.map((b) => b.valueFor(metric)).reduce((a, b) => a > b ? a : b);
    final maxY = metric == TrendMetric.rpe
        ? 10.0
        : (maxValue <= 0 ? 1.0 : maxValue * 1.2);
    final labelEvery = (buckets.length / 5).ceil().clamp(1, buckets.length);

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
              interval: labelEvery.toDouble(),
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= buckets.length) return const SizedBox.shrink();
                if (i != buckets.length - 1 && i % labelEvery != 0) {
                  return const SizedBox.shrink();
                }
                final isLast = i == buckets.length - 1;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('MMM d').format(buckets[i].start),
                    style: AppTypography.labelCaps.copyWith(
                        fontSize: 10,
                        color:
                            isLast ? AppColors.accent : AppColors.outline),
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
                  '${metric == TrendMetric.sessions ? spot.y.round() : spot.y.toStringAsFixed(1)} ${metric.unit}\n${DateFormat('MMM d').format(buckets[spot.x.round()].start)}',
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
                  color: isLast
                      ? AppColors.accent
                      : AppColors.surfaceContainer,
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

class _InsightsCard extends StatelessWidget {
  final List<String> insights;

  const _InsightsCard({required this.insights});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionEyebrow('Insights', color: AppColors.accent),
          const SizedBox(height: AppSpacing.sm),
          if (insights.isEmpty)
            Text('Log a few more sessions to unlock your first insight.',
                style: AppTypography.bodySm)
          else
            for (final line in insights)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(line,
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.onSurface)),
              ),
        ],
      ),
    );
  }
}

/// The real, AI-generated monthly report (Pro/Advanced only) - distinct from
/// the rule-based `_InsightsCard` above and the still-unbuilt `_ProForecastCard`
/// teaser below. Reads `AnalyticsController` directly via `context.watch`
/// rather than threading its state through `_ProgressContent`'s constructor.
class _AiInsightsSection extends StatelessWidget {
  const _AiInsightsSection();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AnalyticsController>();

    if (controller.requiresUpgrade) {
      return const _AiInsightsLockedCard();
    }

    final state = controller.state;
    if (state.error != null && state.error!.isNotEmpty) {
      return SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AiInsightsHeader(controller: controller),
            const SizedBox(height: AppSpacing.sm),
            Text(state.error!, style: AppTypography.bodySm),
          ],
        ),
      );
    }

    if (!state.hasData) {
      return SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AiInsightsHeader(controller: controller),
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

    final analytics = state.data!;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AiInsightsHeader(controller: controller),
          const SizedBox(height: 2),
          Text(
            DateFormat('MMMM yyyy')
                .format(DateTime(analytics.year, analytics.month)),
            style: AppTypography.labelCaps
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
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
          if (analytics.focusForNextMonth.isNotEmpty) ...[
            Text('FOCUS FOR NEXT MONTH',
                style: AppTypography.labelCaps
                    .copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text(analytics.focusForNextMonth,
                style:
                    AppTypography.bodySm.copyWith(color: AppColors.onSurface)),
          ],
        ],
      ),
    );
  }
}

class _AiInsightsHeader extends StatelessWidget {
  final AnalyticsController controller;

  const _AiInsightsHeader({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SectionEyebrow('AI Monthly Report', color: AppColors.accent),
        IconButton(
          onPressed: controller.isRefreshing ? null : controller.refresh,
          icon: controller.isRefreshing
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              style:
                  AppTypography.bodySm.copyWith(color: AppColors.onSurface)),
        ],
      ),
    );
  }
}

/// Locked upsell teaser for a Free-tier user - the same slim single-row
/// pattern as Home's `AiInsightsTeaserCard` (icon, label, value, trailing
/// "PRO" pill) rather than a full card, so every Pro teaser in the app reads
/// as one consistent shape instead of Progress inventing its own heavier one.
class _AiInsightsLockedCard extends StatelessWidget {
  const _AiInsightsLockedCard();

  @override
  Widget build(BuildContext context) {
    return SlimActionRow(
      icon: Icons.insights_rounded,
      iconColor: AppColors.secondary,
      iconBackground: AppColors.secondary.withOpacity(0.16),
      label: 'AI MONTHLY REPORT',
      value: 'Unlock strengths, improvements & focus for the month',
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.secondaryContainer.withOpacity(0.18),
          AppColors.surfaceContainer,
        ],
      ),
      borderColor: AppColors.secondary.withOpacity(0.3),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(AppRadius.full)),
        child: Text('PRO',
            style: AppTypography.labelCaps
                .copyWith(color: AppColors.onAccent, fontSize: 9)),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PlansScreen()),
      ),
    );
  }
}

/// Static, locked-look "predictive forecast" teaser - like the Today AI
/// overview teaser, no real forecasting model backs this, it's a Pro
/// merchandising row that routes into Plans. Same slim shape as
/// `_AiInsightsLockedCard` above so the two Pro upsells on this screen read
/// as a matched pair rather than two differently-built cards.
class _ProForecastCard extends StatelessWidget {
  const _ProForecastCard();

  @override
  Widget build(BuildContext context) {
    return SlimActionRow(
      icon: Icons.model_training_rounded,
      iconColor: AppColors.secondary,
      iconBackground: AppColors.secondary.withOpacity(0.16),
      label: 'PREDICTIVE FORECAST',
      value: 'Unlock a projected training curve & load forecast',
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.secondaryContainer.withOpacity(0.18),
          AppColors.surfaceContainer,
        ],
      ),
      borderColor: AppColors.secondary.withOpacity(0.3),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(AppRadius.full)),
        child: Text('PRO',
            style: AppTypography.labelCaps
                .copyWith(color: AppColors.onAccent, fontSize: 9)),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PlansScreen()),
      ),
    );
  }
}

class _HeatmapGrid extends StatelessWidget {
  final List<HeatmapDay> days;

  const _HeatmapGrid({required this.days});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final day in days)
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                  color: AppColors.forSessionStatus(day.status),
                  borderRadius: BorderRadius.circular(4)),
            ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String suffix;

  const _StatTile(
      {required this.label, required this.value, required this.suffix});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      background: AppColors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: AppTypography.labelCaps),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: AppTypography.metricMd),
              const SizedBox(width: 4),
              Text(suffix, style: AppTypography.bodySm),
            ],
          ),
        ],
      ),
    );
  }
}
