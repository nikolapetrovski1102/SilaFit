import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/duration_format.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../splits/splits_models.dart';
import 'widgets/day_preview.dart';

/// Read-only details for one scheduled day in the active split.
class WorkoutPreviewScreen extends StatelessWidget {
  final DayPreview preview;
  final String? splitName;

  const WorkoutPreviewScreen({
    super.key,
    required this.preview,
    this.splitName,
  });

  @override
  Widget build(BuildContext context) {
    final exercises = [...preview.scheduledExercises]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final totalSets = exercises.fold<int>(
      0,
      (total, exercise) => total + exercise.targetSets,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Workout Preview', style: AppTypography.headlineSm),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.gutterMobile, vertical: AppSpacing.lg),
          children: [
            Text(preview.title ?? 'Training Session',
                style: AppTypography.headlineLg),
            const SizedBox(height: AppSpacing.xxs),
            Text(DateFormat('EEEE, MMM d').format(preview.date),
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant)),
            if (preview.focusLabel?.trim().isNotEmpty == true) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(preview.focusLabel!, style: AppTypography.bodyMd),
            ],
            if (splitName?.trim().isNotEmpty == true) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text('From $splitName',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant)),
            ],
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _SummaryPill(
                  icon: Icons.schedule_rounded,
                  label: preview.estimatedMinutes == null
                      ? 'Duration not set'
                      : formatMinutesLabel(preview.estimatedMinutes!),
                ),
                _SummaryPill(
                  icon: Icons.fitness_center_rounded,
                  label:
                      '${exercises.length} ${exercises.length == 1 ? 'exercise' : 'exercises'}',
                ),
                if (totalSets > 0)
                  _SummaryPill(
                      icon: Icons.repeat_rounded,
                      label: '$totalSets total sets'),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionEyebrow('Exercise details'),
            const SizedBox(height: AppSpacing.sm),
            if (exercises.isEmpty)
              const _EmptyWorkout()
            else
              for (var i = 0; i < exercises.length; i++) ...[
                _ExerciseDetail(index: i + 1, exercise: exercises[i]),
                const SizedBox(height: AppSpacing.md),
              ],
          ],
        ),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SummaryPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.accent),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: AppTypography.labelSm),
        ],
      ),
    );
  }
}

class _ExerciseDetail extends StatelessWidget {
  final int index;
  final SplitDayExercise exercise;

  const _ExerciseDetail({required this.index, required this.exercise});

  @override
  Widget build(BuildContext context) {
    final muscleGroup = exercise.muscleGroup.trim();
    return SectionCard(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: AppTypography.labelSm.copyWith(
                color: AppColors.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.name, style: AppTypography.headlineSm),
                if (muscleGroup.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    muscleGroup,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    _TargetValue(
                      label: 'SETS',
                      value: '${exercise.targetSets}',
                    ),
                    const SizedBox(width: AppSpacing.xxl),
                    _TargetValue(
                      label: 'REPS',
                      value: _repsLabel(exercise),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _repsLabel(SplitDayExercise exercise) {
    if (exercise.targetRepsLow == exercise.targetRepsHigh) {
      return '${exercise.targetRepsLow}';
    }
    return '${exercise.targetRepsLow}-${exercise.targetRepsHigh}';
  }
}

class _TargetValue extends StatelessWidget {
  final String label;
  final String value;

  const _TargetValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelCaps),
        const SizedBox(height: 2),
        Text(value, style: AppTypography.numericUnit.copyWith(fontSize: 18)),
      ],
    );
  }
}

class _EmptyWorkout extends StatelessWidget {
  const _EmptyWorkout();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Text(
        'No exercises are assigned to this day yet.',
        style: AppTypography.bodyLg.copyWith(
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}
