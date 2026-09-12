import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/section_eyebrow.dart';
import '../meal_models.dart';

/// One card in the horizontal "Suggested this month" strip - tapping it
/// hands the suggestion to [onTap], which opens the quick-add sheet
/// pre-filled so the user can still adjust portions before logging it.
///
/// Trimmed padding + a `Wrap` (not a `Row`) for the macro pills, and no
/// description line: the card is locked to the strip's fixed 156px row
/// height (see `meal_planning_screen.dart`) via `SectionCard`'s own
/// padding, and a full `SectionEyebrow` + 2-line title + 2-line description
/// + macro row used to add up to more height than the card actually had,
/// clipping the pills. `Wrap` also means a long macro readout on a narrow
/// card wraps to a second line instead of overflowing horizontally.
class MealSuggestionCard extends StatelessWidget {
  final MealSuggestion suggestion;
  final VoidCallback onTap;

  const MealSuggestionCard({
    super.key,
    required this.suggestion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 220,
        child: SectionCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionEyebrow(suggestion.mealType, color: AppColors.accent),
              const SizedBox(height: 6),
              Text(
                suggestion.title,
                style: AppTypography.headlineSm.copyWith(fontSize: 16),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _MacroChip(
                    icon: Icons.local_fire_department_rounded,
                    label: '${suggestion.caloriesKcal} kcal',
                  ),
                  _MacroChip(
                    label: '${suggestion.proteinG}P · '
                        '${suggestion.carbsG}C · ${suggestion.fatsG}F',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacroChip extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _MacroChip({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: AppColors.accent),
            const SizedBox(width: 3),
          ],
          Text(label,
              style: AppTypography.labelSm
                  .copyWith(color: AppColors.onSurfaceVariant, fontSize: 11)),
        ],
      ),
    );
  }
}
