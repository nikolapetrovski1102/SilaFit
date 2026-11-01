import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// "WEEK k" divider between the weeks of a multi-week split or diet plan.
class WeekHeader extends StatelessWidget {
  final int week;

  /// The first header sits flush under the section title.
  final bool first;

  const WeekHeader({super.key, required this.week, this.first = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          top: first ? 0 : AppSpacing.sm, bottom: AppSpacing.sm),
      child: Row(
        children: [
          Text('WEEK $week',
              style: AppTypography.labelCaps.copyWith(color: AppColors.accent)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Divider(color: AppColors.outlineVariant, height: 1)),
        ],
      ),
    );
  }
}
