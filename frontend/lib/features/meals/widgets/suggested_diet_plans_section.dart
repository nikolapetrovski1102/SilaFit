import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/section_eyebrow.dart';
import '../../../core/widgets/silen_button.dart';
import '../../diet_plans/diet_plan_controller.dart';
import '../../diet_plans/diet_plan_models.dart';
import '../../diet_plans/diet_plans_screen.dart';
import '../../diet_plans/widgets/diet_plan_card.dart';

/// The "Suggested This Month" strip on Nutrition - diet-plan listings rather
/// than one-off meal recipes, plus a "Generate plan" action that builds a fresh
/// plan from the user's calorie/macro targets (the on-demand counterpart of the
/// weekly AI batch).
class SuggestedDietPlansSection extends StatelessWidget {
  const SuggestedDietPlansSection({super.key});

  @override
  Widget build(BuildContext context) {
    final plansController = context.watch<DietPlansController>();
    final activeController = context.watch<ActiveDietPlanController>();

    final plans = plansController.state.data ?? const <DietPlan>[];
    final isLoading = plansController.state.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionEyebrow('Suggested This Month',
                    color: AppColors.accent),
                const SizedBox(height: 2),
                Text('Diet plans matched to your targets',
                    style: AppTypography.labelSm
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DietPlansScreen())),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('See all',
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.accent)),
                  Icon(Icons.chevron_right_rounded,
                      size: 16, color: AppColors.accent),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (isLoading && plans.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          )
        else if (plans.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No plans available yet.',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant)),
          )
        else
          SizedBox(
            height: 248,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: plans.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) =>
                  DietPlanCard(plan: plans[i], width: 230, compact: true),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        PrimaryPillButton(
          label: activeController.isGenerating
              ? 'Generating...'
              : 'Generate a plan for me',
          icon: Icons.auto_awesome_rounded,
          isLoading: activeController.isGenerating,
          onPressed: () => _generate(context, activeController),
        ),
      ],
    );
  }

  Future<void> _generate(
      BuildContext context, ActiveDietPlanController controller) async {
    final ok = await controller.generate();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Your plan is ready.'
          : controller.actionError ?? 'Could not generate a plan right now.'),
    ));
  }
}
