import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/state/resource_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/section_eyebrow.dart';
import '../exercise_progress_controller.dart';
import '../progress_models.dart';
import 'personal_record_tile.dart' show formatPrWeight;

/// PRO/Advanced per-exercise tracker: pick any exercise that has logged sets,
/// then chart one metric per session over the Progress screen's timeframe.
///
/// When [controller] reports [ExerciseProgressAccess.locked] the card renders
/// [_Sample] instead - the gated endpoints return nothing for a Free caller,
/// and the Progress screen blurs the card anyway, so this only has to look
/// plausible behind the blur.
class ExerciseProgressCard extends StatelessWidget {
  final ExerciseProgressController controller;

  const ExerciseProgressCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final locked = controller.access == ExerciseProgressAccess.locked;
    final exercisesState = locked
        ? ResourceState.data(_Sample.exercises)
        : controller.exercisesState;
    final progressState =
        locked ? ResourceState.data(_Sample.progress) : controller.progressState;
    final selectedId =
        locked ? _Sample.exercises.first.exerciseId : controller.selectedExerciseId;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(child: SectionEyebrow('Exercise Progress')),
              _TierBadge(),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (exercisesState.isLoading)
            const _CardSpinner()
          else if (exercisesState.error != null)
            _RetryMessage(
                message: exercisesState.error!,
                onRetry: () => controller.load(force: true))
          else if (exercisesState.data!.isEmpty)
            Text('Log sets during a workout to track each exercise over time.',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant))
          else ...[
            _ExercisePicker(
              exercises: exercisesState.data!,
              selectedId: selectedId,
              onSelected: locked ? (_) {} : controller.select,
            ),
            const SizedBox(height: AppSpacing.md),
            if (progressState.isLoading)
              const _CardSpinner()
            else if (progressState.error != null)
              _RetryMessage(
                  message: progressState.error!,
                  onRetry: controller.retryProgress)
            else
              _ProgressBody(
                progress: progressState.data!,
                metric: controller.metric,
                onMetricChanged: controller.setMetric,
              ),
          ],
        ],
      ),
    );
  }
}

class _TierBadge extends StatelessWidget {
  const _TierBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text('PRO',
          style: AppTypography.labelCaps
              .copyWith(color: AppColors.onAccent, fontSize: 9)),
    );
  }
}

class _ExercisePicker extends StatelessWidget {
  final List<TrackedExercise> exercises;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const _ExercisePicker({
    required this.exercises,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final exercise in exercises) ...[
            PillChip(
              label: exercise.exerciseName,
              selected: exercise.exerciseId == selectedId,
              onTap: () => onSelected(exercise.exerciseId),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

extension on ExerciseProgressMetric {
  String get label => switch (this) {
        ExerciseProgressMetric.estimatedOneRm => 'Est. 1RM',
        ExerciseProgressMetric.topSet => 'Top set',
        ExerciseProgressMetric.volume => 'Volume',
        ExerciseProgressMetric.reps => 'Reps',
      };

  String get unit => this == ExerciseProgressMetric.reps ? 'reps' : 'kg';

  double valueOf(ExerciseProgressPoint p) => switch (this) {
        ExerciseProgressMetric.estimatedOneRm => p.estimatedOneRmKg,
        ExerciseProgressMetric.topSet => p.topWeightKg,
        ExerciseProgressMetric.volume => p.totalVolumeKg,
        ExerciseProgressMetric.reps => p.totalReps.toDouble(),
      };
}

class _ProgressBody extends StatelessWidget {
  final ExerciseProgress progress;
  final ExerciseProgressMetric metric;
  final ValueChanged<ExerciseProgressMetric> onMetricChanged;

  const _ProgressBody({
    required this.progress,
    required this.metric,
    required this.onMetricChanged,
  });

  @override
  Widget build(BuildContext context) {
    final points = progress.points;
    if (points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text('No sessions for this exercise in the selected timeframe.',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.onSurfaceVariant)),
      );
    }

    // A bodyweight exercise logs 0 kg on every set - weight-based metrics
    // would just chart a flat zero, so only reps are offered for it.
    final weighted = points.any((p) => p.topWeightKg > 0);
    final metrics = weighted
        ? ExerciseProgressMetric.values
        : const [ExerciseProgressMetric.reps];
    final effective = metrics.contains(metric) ? metric : metrics.first;

    final values = [for (final p in points) effective.valueOf(p)];
    final latest = values.last;
    final best = values.reduce((a, b) => a > b ? a : b);
    final first = values.first;
    final pct = values.length >= 2 && first > 0
        ? (latest - first) / first * 100
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final m in metrics)
              _MetricChip(
                label: m.label,
                selected: m == effective,
                onTap: () => onMetricChanged(m),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatPrWeight(latest), style: AppTypography.displayStatMobile),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(effective.unit,
                  style: AppTypography.numericUnit
                      .copyWith(color: AppColors.onSurfaceVariant)),
            ),
            const Spacer(),
            if (pct != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
                  style: AppTypography.labelSm.copyWith(
                      fontWeight: FontWeight.w600,
                      color: pct >= 0 ? AppColors.accent : AppColors.error),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Best ${formatPrWeight(best)} ${effective.unit} · '
          '${points.length} session${points.length == 1 ? '' : 's'}',
          style:
              AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        if (points.length < 2)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(
                child: Text('Train it again to see your trend.',
                    style: AppTypography.bodySm)),
          )
        else
          SizedBox(
            height: 150,
            child: _MetricChart(
                points: points, values: values, unit: effective.unit),
          ),
        const SizedBox(height: AppSpacing.md),
        const SectionEyebrow('Recent sessions'),
        const SizedBox(height: AppSpacing.sm),
        for (final p in points.reversed.take(3)) _SessionRow(point: p),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MetricChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
              color: selected ? AppColors.accent : AppColors.outlineVariant),
        ),
        child: Text(label,
            style: AppTypography.labelSm.copyWith(
                color:
                    selected ? AppColors.accent : AppColors.onSurfaceVariant)),
      ),
    );
  }
}

class _MetricChart extends StatelessWidget {
  final List<ExerciseProgressPoint> points;
  final List<double> values;
  final String unit;

  const _MetricChart({
    required this.points,
    required this.values,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
    ];
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    // Pad around the actual range rather than anchoring at zero - a lift
    // moving 100 -> 107.5 kg should read as progress, not a flat line.
    final span = maxValue - minValue;
    final pad = span == 0 ? (maxValue == 0 ? 1.0 : maxValue * 0.1) : span * 0.2;
    final minY = (minValue - pad).clamp(0.0, double.infinity);
    final maxY = maxValue + pad;

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 3,
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
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i != 0 && i != points.length - 1) {
                  return const SizedBox.shrink();
                }
                final isLast = i == points.length - 1;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('MMM d').format(points[i].date),
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
                  '${formatPrWeight(spot.y)} $unit\n${DateFormat('MMM d').format(points[spot.x.round()].date)}',
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
            preventCurveOverShooting: true,
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

class _SessionRow extends StatelessWidget {
  final ExerciseProgressPoint point;

  const _SessionRow({required this.point});

  @override
  Widget build(BuildContext context) {
    final topSet = point.topWeightKg > 0
        ? '${formatPrWeight(point.topWeightKg)} kg × ${point.topSetReps}'
        : '${point.totalReps} reps';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(DateFormat('MMM d').format(point.date),
                style: AppTypography.labelSm
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
                '${point.setCount} set${point.setCount == 1 ? '' : 's'}',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ),
          Text(topSet,
              style: AppTypography.numericUnit
                  .copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _CardSpinner extends StatelessWidget {
  const _CardSpinner();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
              strokeWidth: 2.5, color: AppColors.accent),
        ),
      ),
    );
  }
}

class _RetryMessage extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _RetryMessage({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: Text('$message Tap to retry.',
          style:
              AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
    );
  }
}

/// Placeholder shown only behind the lock blur - never real data.
abstract final class _Sample {
  static final exercises = [
    TrackedExercise(
        exerciseId: 'sample-bench',
        exerciseName: 'Bench Press',
        sessionCount: 8,
        lastTrainedAtUtc: DateTime(2026)),
    TrackedExercise(
        exerciseId: 'sample-squat',
        exerciseName: 'Back Squat',
        sessionCount: 7,
        lastTrainedAtUtc: DateTime(2026)),
    TrackedExercise(
        exerciseId: 'sample-deadlift',
        exerciseName: 'Deadlift',
        sessionCount: 5,
        lastTrainedAtUtc: DateTime(2026)),
  ];

  static final progress = ExerciseProgress(
    exerciseId: 'sample-bench',
    days: 30,
    points: [
      for (final (i, weight) in [60.0, 62.5, 62.5, 65.0, 67.5, 70.0].indexed)
        ExerciseProgressPoint(
          date: DateTime.now().subtract(Duration(days: (5 - i) * 5)),
          topWeightKg: weight,
          topSetReps: 5,
          estimatedOneRmKg: weight * (1 + 5 / 30),
          totalVolumeKg: weight * 15,
          totalReps: 15,
          setCount: 3,
        ),
    ],
  );
}
