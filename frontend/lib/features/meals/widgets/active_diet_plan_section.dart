import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/state/resource_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/section_eyebrow.dart';
import '../../diet_plans/diet_plan_controller.dart';
import '../../diet_plans/diet_plan_detail_screen.dart';
import '../../diet_plans/diet_plan_models.dart';
import '../../diet_plans/diet_plan_repository.dart';
import '../../diet_plans/diet_plans_screen.dart';
import '../meal_controller.dart';
import '../meal_models.dart';

/// The "Active Diet Plan" block that replaced the old "Logged Meals" list on
/// Nutrition: shows the user's active plan's meals for the day currently
/// selected in the day strip, and lets each plan meal be logged (or un-logged)
/// straight from here.
///
/// Falls back to a compact empty state when no plan is active, since "no plan
/// chosen yet" is a normal state for a new user rather than an error.
class ActiveDietPlanSection extends StatelessWidget {
  final MealController mealController;

  const ActiveDietPlanSection({super.key, required this.mealController});

  @override
  Widget build(BuildContext context) {
    final activeController = context.watch<ActiveDietPlanController>();
    final state = activeController.state;

    return AnimatedBuilder(
      animation: mealController,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SectionEyebrow('Active Diet Plan'),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DietPlansScreen())),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Change',
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
            _buildBody(context, activeController, state),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, ActiveDietPlanController controller,
      ResourceState<ActiveDietPlan> state) {
    if (!state.hasData) {
      if (state.error != null) {
        return _MessageCard(
          message: state.error!,
          actionLabel: 'RETRY',
          onAction: () => controller.load(force: true),
        );
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    final plan = state.data!.plan;
    if (plan == null) {
      return _MessageCard(
        message: 'No active plan yet. Pick one from the suggestions below.',
        actionLabel: 'BROWSE PLANS',
        onAction: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DietPlansScreen())),
      );
    }

    return _PlanDayCard(
      plan: plan,
      mealController: mealController,
    );
  }
}

/// The active plan's meals for the selected day, with per-meal log/un-log.
class _PlanDayCard extends StatelessWidget {
  final DietPlanDetail plan;
  final MealController mealController;

  const _PlanDayCard({required this.plan, required this.mealController});

  static const _kDayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  int _dayIndexFor(DateTime date, int durationDays) {
    final days = durationDays <= 0 ? 1 : durationDays;
    // A weekly plan maps cleanly onto the calendar week (Mon=1..Sun=7). Longer
    // plans rotate through their days by day-of-year so a monthly plan doesn't
    // collapse onto only its first seven day slots.
    if (days == 7) return date.weekday;
    final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays + 1;
    return ((dayOfYear - 1) % days) + 1;
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<DietPlanRepository>();
    final dayIndex = _dayIndexFor(mealController.selectedDate, plan.plan.durationDays);
    final planDay = _findDay(dayIndex);
    final dayLogs = mealController.state.data?.meals ?? const <MealLog>[];

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.plan.name,
                        style: AppTypography.bodyMd
                            .copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${plan.plan.periodType} · Day $dayIndex'
                      ' · ${_kDayNames[mealController.selectedDate.weekday - 1]}',
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DietPlanDetailScreen(
                    controller: DietPlanDetailController(
                        repository, plan.plan.dietPlanId),
                    planName: plan.plan.name,
                  ),
                )),
                child: Text('Open',
                    style: AppTypography.labelSm
                        .copyWith(color: AppColors.accent)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (planDay == null || planDay.meals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('This plan day has no meals yet.',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant)),
            )
          else
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Column(
                key: ValueKey(mealController.selectedDate.day),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final meal in planDay.meals) ...[
                    _PlanMealRow(
                      meal: meal,
                      logged: dayLogs.any((log) =>
                          log.isLogged && log.title == meal.title),
                      onLog: () {
                        // The backend now pre-fills the week with this plan's
                        // meals as Planned logs on activation, so most taps
                        // here just flip an existing row to Logged. Only fall
                        // back to creating one when it's genuinely missing
                        // (e.g. a plan applied before this day existed, or a
                        // row the user deleted).
                        for (final log in dayLogs) {
                          if (!log.isLogged && log.title == meal.title) {
                            mealController.logMeal(log);
                            return;
                          }
                        }
                        mealController.addMeal(
                          mealType: meal.mealType,
                          title: meal.title,
                          caloriesKcal: meal.caloriesKcal,
                          proteinG: meal.proteinG,
                          carbsG: meal.carbsG,
                          fatsG: meal.fatsG,
                          logNow: true,
                        );
                      },
                      onDelete: () {
                        for (final log in dayLogs) {
                          if (log.isLogged && log.title == meal.title) {
                            mealController.deleteMeal(log.mealLogId);
                            return;
                          }
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  DietPlanDayWithMeals? _findDay(int dayIndex) {
    if (plan.days.isEmpty) return null;
    for (final day in plan.days) {
      if (day.day.dayIndex == dayIndex) return day;
    }
    return plan.days.first;
  }
}

class _PlanMealRow extends StatelessWidget {
  final DietPlanMeal meal;
  final bool logged;
  final VoidCallback onLog;
  final VoidCallback onDelete;

  const _PlanMealRow({
    required this.meal,
    required this.logged,
    required this.onLog,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.inset),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meal.mealType.toUpperCase(),
                    style: AppTypography.labelCaps
                        .copyWith(color: AppColors.accent)),
                const SizedBox(height: 2),
                Text(meal.title,
                    style: AppTypography.bodySm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  '${meal.caloriesKcal} kcal · P${meal.proteinG} C${meal.carbsG} F${meal.fatsG}',
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (logged)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PillChip(
                    label: 'Logged', icon: Icons.check_circle_rounded),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: onDelete,
                ),
              ],
            )
          else
            GestureDetector(
              onTap: onLog,
              child: const PillChip(label: 'Log'),
            ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _MessageCard({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message,
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel,
                style: AppTypography.labelCaps
                    .copyWith(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }
}
