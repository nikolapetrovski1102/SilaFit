import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/section_eyebrow.dart';
import '../meal_models.dart';

/// One card in the Logged Meals list - a planned meal shows a clock icon and
/// an inline "Log Meal" pill that flips to a static "Logged" pill (checkmark
/// icon) once it fires, matching `meal_planning/code.html`.
class MealLogCard extends StatelessWidget {
  final MealLog meal;
  final VoidCallback onLog;
  final VoidCallback onDelete;

  const MealLogCard({
    super.key,
    required this.meal,
    required this.onLog,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final logged = meal.isLogged;
    return SectionCard(
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: logged
                  ? AppColors.secondaryContainer
                  : AppColors.surfaceContainerHigh,
            ),
            alignment: Alignment.center,
            child: Icon(
              logged ? Icons.check_rounded : Icons.schedule_rounded,
              size: 20,
              color: logged
                  ? AppColors.onSecondaryContainer
                  : AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meal.title, style: AppTypography.bodyMd),
                const SizedBox(height: 2),
                Text('${meal.mealType} · ${meal.caloriesKcal} kcal',
                    style: AppTypography.labelSm
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (logged) ...[
            const PillChip(label: 'Logged', icon: Icons.check_circle_rounded),
            IconButton(
              onPressed: onDelete,
              icon: Icon(Icons.close_rounded,
                  size: 18, color: AppColors.onSurfaceVariant),
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.only(left: 4),
            ),
          ] else
            GestureDetector(
              onTap: onLog,
              child: const PillChip(label: 'Log Meal'),
            ),
        ],
      ),
    );
  }
}
