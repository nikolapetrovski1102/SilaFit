import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/section_eyebrow.dart';
import '../meal_models.dart';
import 'food_picker_sheet.dart' show MacroLine;

/// One meal in the day's list. A logged meal opens the meal tracker on tap
/// ([onOpen]) and, when it was built food by food, expands to show those
/// foods; a planned meal shows an inline "Log" pill instead.
class MealLogCard extends StatefulWidget {
  final MealLog meal;
  final VoidCallback onOpen;
  final VoidCallback onLog;
  final VoidCallback onDelete;

  const MealLogCard({
    super.key,
    required this.meal,
    required this.onOpen,
    required this.onLog,
    required this.onDelete,
  });

  @override
  State<MealLogCard> createState() => _MealLogCardState();
}

class _MealLogCardState extends State<MealLogCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final meal = widget.meal;
    final logged = meal.isLogged;
    final hasFoods = meal.items.isNotEmpty;

    return Material(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: logged ? widget.onOpen : widget.onLog,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
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
                        Text(meal.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodyMd),
                        const SizedBox(height: 2),
                        Text(
                          [
                            meal.mealType,
                            '${meal.caloriesKcal} kcal',
                            if (hasFoods)
                              '${meal.items.length} ${meal.items.length == 1 ? 'food' : 'foods'}',
                          ].join(' · '),
                          style: AppTypography.labelSm
                              .copyWith(color: AppColors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        MacroLine(
                          proteinG: meal.proteinG.toDouble(),
                          carbsG: meal.carbsG.toDouble(),
                          fatsG: meal.fatsG.toDouble(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  if (!logged) ...[
                    PillChip(label: 'Log', onTap: widget.onLog),
                    IconButton(
                      onPressed: widget.onDelete,
                      tooltip: 'Remove',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close_rounded,
                          size: 18, color: AppColors.onSurfaceVariant),
                    ),
                  ] else if (hasFoods)
                    IconButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      tooltip: _expanded ? 'Hide foods' : 'Show foods',
                      visualDensity: VisualDensity.compact,
                      icon: AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.expand_more_rounded,
                            color: AppColors.onSurfaceVariant),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: Icon(Icons.chevron_right_rounded,
                          color: AppColors.onSurfaceVariant),
                    ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !_expanded || !hasFoods
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(
                            top: AppSpacing.sm,
                            left: 40 + AppSpacing.sm,
                            right: AppSpacing.xs),
                        child: Column(
                          children: [
                            for (final item in meal.items) _FoodLine(item),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoodLine extends StatelessWidget {
  final MealLogItem item;

  const _FoodLine(this.item);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySm),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '${item.grams.round()} g · ${item.caloriesKcal.round()} kcal',
            style: AppTypography.labelSm
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
