import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import 'diet_plan_builder_screen.dart';
import 'diet_plan_controller.dart';
import 'diet_plan_models.dart';
import 'diet_plan_repository.dart';

/// Read-only detail view for a diet plan - the meal-planning equivalent of
/// `SplitDetailScreen`. Besides browse + (if owned) edit, it offers the
/// activate action: since weekly AI plans are no longer auto-activated, this
/// is how the user adopts a freshly generated plan or switches back to an
/// older one.
class DietPlanDetailScreen extends StatefulWidget {
  final DietPlanDetailController controller;
  final String planName;

  const DietPlanDetailScreen(
      {super.key, required this.controller, required this.planName});

  @override
  State<DietPlanDetailScreen> createState() => _DietPlanDetailScreenState();
}

class _DietPlanDetailScreenState extends State<DietPlanDetailScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(widget.controller.load);
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final ok = await widget.controller.activate();
    if (!mounted) return;
    if (ok) {
      // The Nutrition screen's active-plan section is cached, so refresh it
      // rather than waiting for its next manual load.
      context.read<ActiveDietPlanController>().load(force: true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${widget.planName} is now your active plan.')));
    } else if (widget.controller.actionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.actionError!)));
    }
  }

  Future<void> _keep() async {
    final ok = await widget.controller.keep();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This diet plan is now permanently yours.')));
    } else if (widget.controller.actionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.actionError!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.planName, style: AppTypography.headlineSm),
        actions: [
          if (widget.controller.state.data?.plan.isEditableByMe == true)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final repository = context.read<DietPlanRepository>();
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DietPlanBuilderScreen(
                    controller: DietPlanBuilderController(repository,
                        dietPlanId: widget.controller.dietPlanId),
                  ),
                ));
                if (!mounted) return;
                widget.controller.load(force: true);
              },
            ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.gutterMobile),
            child: ResourceBuilder<DietPlanDetail>(
              state: widget.controller.state,
              onRetry: widget.controller.load,
              builder: (context, detail) => _DetailBody(
                  detail: detail,
                  controller: widget.controller,
                  onActivate: _activate,
                  onKeep: _keep),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final DietPlanDetail detail;
  final DietPlanDetailController controller;
  final VoidCallback onActivate;
  final VoidCallback onKeep;

  const _DetailBody(
      {required this.detail,
      required this.controller,
      required this.onActivate,
      required this.onKeep});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: detail.plan.heroImageUrl != null
                ? Image.network(detail.plan.heroImageUrl!, fit: BoxFit.cover)
                : Image.asset('assets/branding/split_hero.png', fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionEyebrow(detail.plan.periodType, color: AppColors.accent),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _MetaPill(
                icon: Icons.calendar_view_week_rounded,
                label: '${detail.plan.durationDays} days'),
            const SizedBox(width: AppSpacing.xs),
            _MetaPill(
                icon: Icons.event_repeat_rounded,
                label: '${detail.days.length} plan days'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (detail.plan.description != null) ...[
          Text(detail.plan.description!, style: AppTypography.bodyMd),
          const SizedBox(height: AppSpacing.md),
        ],
        PrimaryPillButton(
          label:
              controller.activated ? 'Plan Activated' : 'Activate This Plan',
          icon: controller.activated
              ? Icons.check_rounded
              : Icons.play_arrow_rounded,
          isLoading: controller.isActivating,
          onPressed: controller.activated ? null : onActivate,
        ),
        const SizedBox(height: AppSpacing.md),
        if (detail.plan.isAiGenerated && detail.plan.aiKeptAtUtc == null) ...[
          SecondaryPillButton(
            label: controller.isKeeping ? 'Keeping...' : 'Keep This Plan',
            icon: Icons.push_pin_outlined,
            onPressed: controller.isKeeping ? null : onKeep,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "AI-generated for this week. Keep it and it's yours for good — "
            'otherwise it refreshes next Sunday.',
            style: AppTypography.labelSm
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Text('DAY BY DAY', style: AppTypography.labelCaps),
        const SizedBox(height: AppSpacing.sm),
        for (final day in [...detail.days]
          ..sort((a, b) => a.day.dayIndex.compareTo(b.day.dayIndex))) ...[
          _DayCard(day: day),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (detail.shoppingList.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('SHOPPING LIST', style: AppTypography.labelCaps),
          const SizedBox(height: AppSpacing.sm),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Everything you need for the week.',
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final ingredient in detail.shoppingList)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.circle_outlined,
                            size: 16, color: AppColors.accent),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(ingredient,
                              style: AppTypography.bodySm.copyWith(
                                  color: AppColors.onSurface)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.accent),
          const SizedBox(width: 4),
          Text(label,
              style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final DietPlanDayWithMeals day;

  const _DayCard({required this.day});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('${day.day.dayIndex}',
                    style: AppTypography.labelCaps.copyWith(color: AppColors.onAccent)),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(day.day.title ?? 'Day ${day.day.dayIndex}',
                    style: AppTypography.headlineSm.copyWith(fontSize: 16)),
              ),
            ],
          ),
          if (day.meals.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Divider(color: AppColors.outlineVariant, height: 1),
            const SizedBox(height: AppSpacing.sm),
            for (final meal in [...day.meals]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(meal.mealType,
                          style: AppTypography.labelSm.copyWith(color: AppColors.accent)),
                    ),
                    Expanded(
                        child: Text(meal.title,
                            style: AppTypography.bodySm.copyWith(color: AppColors.onSurface))),
                    Text('${meal.caloriesKcal} kcal',
                        style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
