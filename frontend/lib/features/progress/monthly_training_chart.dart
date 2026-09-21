import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_dropdown.dart';
import 'analytics_models.dart';

/// Plots logged load, not an inferred quality/effort score. The drawing starts
/// at the baseline, then traces each real point with a moving tip.
class MonthlyTrainingChart extends StatefulWidget {
  final List<MonthlyExercise> exercises;
  final bool active;
  const MonthlyTrainingChart(
      {super.key, required this.exercises, required this.active});
  @override
  State<MonthlyTrainingChart> createState() => _MonthlyTrainingChartState();
}

class _MonthlyTrainingChartState extends State<MonthlyTrainingChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));
  int _selected = 0;

  void _play() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = 1;
    } else if (widget.active) {
      _reveal.forward(from: 0);
    } else {
      _reveal.stop();
      _reveal.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _play();
  }

  @override
  void didUpdateWidget(covariant MonthlyTrainingChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) _play();
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exercises =
        widget.exercises.where((e) => e.points.isNotEmpty).toList();
    final exercise = exercises.isEmpty
        ? null
        : exercises[_selected.clamp(0, exercises.length - 1)];
    final rpes = exercise?.points
            .map((p) => p.sessionRpe)
            .whereType<double>()
            .toList() ??
        <double>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.marginMobile, vertical: AppSpacing.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionEyebrow('Your training, in motion'),
        const SizedBox(height: AppSpacing.sm),
        Text('See your effort over time', style: AppTypography.headlineLg),
        const SizedBox(height: AppSpacing.sm),
        Text(
            'Working weight, reps and logged effort tell different parts of the story.',
            style: AppTypography.bodyMd),
        const SizedBox(height: AppSpacing.lg),
        if (exercise == null)
          const SectionCard(
              child: Text(
                  'No exercise sets logged for this month yet. Log weights and reps during workouts to build your graph.'))
        else ...[
          SilenDropdown<int>(
            label: 'Exercise',
            value: _selected.clamp(0, exercises.length - 1),
            items: [
              for (var i = 0; i < exercises.length; i++)
                DropdownMenuItem(
                    value: i,
                    child: Text(exercises[i].exerciseName,
                        style: AppTypography.bodyMd,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis))
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _selected = value);
                _play();
              }
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Text(
                    '${_format(exercise.points.last.weightKg)} kg × ${exercise.points.last.reps} reps',
                    style: AppTypography.headlineLg
                        .copyWith(color: AppColors.accent)),
                Text(
                    'Latest heaviest set · ${DateFormat.MMMd().format(exercise.points.last.dateUtc)}',
                    style: AppTypography.bodySm),
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  label:
                      '${exercise.exerciseName}. Heaviest set per session. Record through month end ${exercise.recordWeightKg} kilograms. ${exercise.points.map((p) => '${DateFormat.MMMd().format(p.dateUtc)}: ${p.weightKg} kilograms, ${p.reps} reps').join('; ')}',
                  child: SizedBox(
                      height: 220,
                      child: AnimatedBuilder(
                        animation: _reveal,
                        builder: (context, _) => CustomPaint(
                            painter: _TrainingPainter(exercise, _reveal.value)),
                      )),
                ),
                Text(
                    'Heaviest set each session · kg\nDashed line: PR through month end (${_format(exercise.recordWeightKg)} kg)',
                    style: AppTypography.bodySm),
              ])),
          const SizedBox(height: AppSpacing.md),
          Text(
              exercise.points.length < 2
                  ? 'One session is a starting point. More logs are needed to show a trend.'
                  : exercise.steadyLoad
                      ? 'Your heaviest logged weight stayed at ${_format(exercise.points.last.weightKg)} kg across ${exercise.points.length} sessions. ${exercise.points.last.reps > exercise.points.first.reps ? 'You added reps at that weight.' : 'There is no upward load trend in these logs yet.'}'
                      : exercise.improved
                          ? 'Your latest set shows progress over your first session this month.'
                          : 'Your load varied this month. Compare the reps too before drawing conclusions about progress.',
              style: AppTypography.bodyMd),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
              child: Text(
                  rpes.isEmpty
                      ? 'Workout effort (RPE): not logged'
                      : 'Average workout effort: ${(rpes.reduce((a, b) => a + b) / rpes.length).toStringAsFixed(1)}/10 RPE\nFrom ${rpes.length} logged sessions for this exercise. This is session effort, not an exercise quality score.',
                  style: AppTypography.bodyMd)),
          const SizedBox(height: AppSpacing.sm),
          Text(
              'Training below your PR can be intentional. Load alone cannot tell us about technique, recovery or how hard a set felt.',
              style: AppTypography.bodySm),
          const SizedBox(height: AppSpacing.lg),
          const SectionEyebrow('The sets behind the line'),
          const SizedBox(height: AppSpacing.sm),
          for (final point in exercise.points)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                  '${DateFormat.MMMd().format(point.dateUtc)} · ${_format(point.weightKg)} kg × ${point.reps} reps${point.sessionRpe == null ? '' : ' · RPE ${point.sessionRpe!.toStringAsFixed(1)}'}',
                  style: AppTypography.bodySm),
            ),
        ],
      ]),
    );
  }
}

String _format(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

class _TrainingPainter extends CustomPainter {
  final MonthlyExercise exercise;
  final double progress;
  _TrainingPainter(this.exercise, this.progress);

  void _label(Canvas canvas, String text, Offset position) {
    final painter = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                color: AppColors.onSurfaceVariant,
                fontSize: 10,
                fontFamily: 'HankenGrotesk')),
        textDirection: TextDirection.ltr)
      ..layout();
    painter.paint(canvas, position);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(34, 16, size.width - 12, size.height - 28);
    final maxWeight = math.max(
            1.0,
            math.max(exercise.recordWeightKg,
                exercise.points.map((p) => p.weightKg).reduce(math.max))) *
        1.15;
    double y(double kg) => area.bottom - kg / maxWeight * area.height;
    final grid = Paint()
      ..color = AppColors.outlineVariant
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final weight = maxWeight * i / 2;
      canvas.drawLine(
          Offset(area.left, y(weight)), Offset(area.right, y(weight)), grid);
      _label(canvas, weight.toStringAsFixed(0), Offset(0, y(weight) - 6));
    }
    final prY = y(exercise.recordWeightKg);
    for (double x = area.left; x < area.right; x += 10) {
      canvas.drawLine(
          Offset(x, prY),
          Offset(math.min(x + 5, area.right), prY),
          Paint()
            ..color = AppColors.secondary
            ..strokeWidth = 1.5);
    }
    final firstTime = exercise.points.first.dateUtc.millisecondsSinceEpoch;
    final span =
        exercise.points.last.dateUtc.millisecondsSinceEpoch - firstTime;
    final points = exercise.points
        .map((point) => Offset(
              span == 0
                  ? area.center.dx
                  : area.left +
                      (point.dateUtc.millisecondsSinceEpoch - firstTime) /
                          span *
                          area.width,
              y(point.weightKg),
            ))
        .toList();
    // The baseline stem is an animation lead-in, not a zero-weight data point.
    final stem = Path()
      ..moveTo(points.first.dx, area.bottom)
      ..lineTo(points.first.dx, points.first.dy);
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final stemPhase = (progress / 0.18).clamp(0.0, 1.0);
    final linePhase = ((progress - 0.18) / 0.82).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final metric in stem.computeMetrics()) {
      canvas.drawPath(
          metric.extractPath(0, metric.length * stemPhase),
          Paint()
            ..color = AppColors.accent.withValues(alpha: .25)
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke);
    }
    Offset? tip;
    for (final metric in line.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * linePhase), paint);
      tip = metric.getTangentForOffset(metric.length * linePhase)?.position;
    }
    if (progress >= .18) {
      final dot = tip ?? points.first;
      canvas.drawCircle(
          dot, 9, Paint()..color = AppColors.accent.withValues(alpha: .15));
      canvas.drawCircle(dot, 4, Paint()..color = AppColors.accent);
    }
    if (progress == 1) {
      for (final point in points) {
        canvas.drawCircle(point, 3, Paint()..color = AppColors.accent);
      }
    }
    _label(canvas, DateFormat.MMMd().format(exercise.points.first.dateUtc),
        Offset(area.left, area.bottom + 10));
    if (span > 0) {
      _label(canvas, DateFormat.MMMd().format(exercise.points.last.dateUtc),
          Offset(math.max(area.left + 50, area.right - 40), area.bottom + 10));
    }
  }

  @override
  bool shouldRepaint(covariant _TrainingPainter oldDelegate) =>
      oldDelegate.exercise != exercise || oldDelegate.progress != progress;
}
