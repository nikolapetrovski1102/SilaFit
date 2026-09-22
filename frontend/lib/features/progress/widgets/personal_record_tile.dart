import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../progress_models.dart';

String formatPrWeight(double kg) =>
    kg % 1 == 0 ? kg.toStringAsFixed(0) : kg.toStringAsFixed(1);

/// One exercise's personal record row - shared by the Progress tab's
/// top-3 preview card and the full [AllPersonalRecordsScreen] list so the
/// two never drift out of sync visually.
class PersonalRecordTile extends StatelessWidget {
  final PersonalRecord record;

  const PersonalRecordTile({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.emoji_events_rounded, size: 18, color: AppColors.secondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(record.exerciseName,
                style: AppTypography.bodyMd,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text('${formatPrWeight(record.weightKg)} kg × ${record.reps}',
              style:
                  AppTypography.numericUnit.copyWith(fontWeight: FontWeight.w600)),
          if (record.deltaKg != null && record.deltaKg! > 0) ...[
            const SizedBox(width: AppSpacing.xs),
            Text('+${formatPrWeight(record.deltaKg!)}',
                style: AppTypography.labelSm.copyWith(color: AppColors.accent)),
          ],
        ],
      ),
    );
  }
}
