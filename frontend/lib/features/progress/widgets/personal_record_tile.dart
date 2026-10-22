import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../progress_models.dart';
import '../weight_display.dart';

/// One exercise's personal record row - shared by the Progress tab's
/// top-3 preview card and the full [AllPersonalRecordsScreen] list so the
/// two never drift out of sync visually.
class PersonalRecordTile extends StatelessWidget {
  final PersonalRecord record;

  const PersonalRecordTile({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final unit = weightUnitOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.emoji_events_rounded, size: 18, color: AppColors.secondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.exerciseName,
                    style: AppTypography.bodyMd,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (record.isPerDumbbell)
                  Text('Per dumbbell',
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          Text('${formatWeight(record.weightKg, unit)} $unit × ${record.reps}',
              style:
                  AppTypography.numericUnit.copyWith(fontWeight: FontWeight.w600)),
          if (record.deltaKg != null && record.deltaKg! > 0) ...[
            const SizedBox(width: AppSpacing.xs),
            Text('+${formatWeight(record.deltaKg!, unit)}',
                style: AppTypography.labelSm.copyWith(color: AppColors.accent)),
          ],
        ],
      ),
    );
  }
}
