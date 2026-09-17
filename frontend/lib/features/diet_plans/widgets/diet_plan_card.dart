import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/section_eyebrow.dart';
import '../diet_plan_controller.dart';
import '../diet_plan_detail_screen.dart';
import '../diet_plan_models.dart';
import '../diet_plan_repository.dart';

/// One diet-plan catalogue card. Shared by the full "Diet Plans" catalog (full
/// width) and the Nutrition screen's "Suggested This Month" strip ([width]
/// constrained to a fixed horizontal card). Tapping opens the plan's detail.
class DietPlanCard extends StatelessWidget {
  final DietPlan plan;

  /// Fixed width for horizontal strips; null lets the card fill its parent.
  final double? width;

  /// Trims the description and clamps the name to one line, so the card fits
  /// the fixed-height horizontal strip on Nutrition. The full catalog leaves
  /// this false.
  final bool compact;

  const DietPlanCard(
      {super.key, required this.plan, this.width, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<DietPlanRepository>();
    final card = GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DietPlanDetailScreen(
          controller: DietPlanDetailController(repository, plan.dietPlanId),
          planName: plan.name,
        ),
      )),
      child: SectionCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.inset)),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: plan.heroImageUrl != null
                        ? Image.network(plan.heroImageUrl!,
                            fit: BoxFit.cover)
                        : Image.asset('assets/branding/split_hero.png',
                            fit: BoxFit.cover),
                  ),
                ),
                if (plan.isSystemDefault)
                  Positioned(
                    top: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius:
                              BorderRadius.circular(AppRadius.full)),
                      child: Text('FEATURED',
                          style: AppTypography.labelCaps
                              .copyWith(color: AppColors.onAccent)),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SectionEyebrow(plan.periodType),
                  const SizedBox(height: 6),
                  Text(plan.name,
                      style: AppTypography.headlineSm,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis),
                  if (!compact && plan.description != null) ...[
                    const SizedBox(height: 4),
                    Text(plan.description!,
                        style: AppTypography.bodyMd
                            .copyWith(color: AppColors.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      _MetaPill(
                          icon: Icons.calendar_view_week_rounded,
                          label: '${plan.durationDays} days'),
                      if (plan.isEditableByMe)
                        const _MetaPill(
                            icon: Icons.edit_rounded, label: 'Your plan')
                      else if (!plan.isSystemDefault)
                        const _MetaPill(
                            icon: Icons.restaurant_menu_rounded,
                            label: 'From your coach'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return width == null ? card : SizedBox(width: width, child: card);
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.accent),
          const SizedBox(width: 4),
          Text(label,
              style: AppTypography.labelSm
                  .copyWith(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}
