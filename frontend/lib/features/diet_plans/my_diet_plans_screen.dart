import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/mascot/mascot_empty_state.dart';
import '../../core/widgets/section_card.dart';
import 'diet_plan_builder_screen.dart';
import 'diet_plan_controller.dart';
import 'diet_plan_models.dart';
import 'diet_plan_repository.dart';

/// The user's own diet plans - built via the in-app builder, always fully
/// editable. Reached from [DietPlansScreen]'s "My plans" action.
class MyDietPlansScreen extends StatefulWidget {
  const MyDietPlansScreen({super.key});

  @override
  State<MyDietPlansScreen> createState() => _MyDietPlansScreenState();
}

class _MyDietPlansScreenState extends State<MyDietPlansScreen> {
  late final MyDietPlansController _controller;

  @override
  void initState() {
    super.initState();
    _controller = context.read<MyDietPlansController>();
    Future.microtask(_controller.load);
  }

  void _openBuilder({String? dietPlanId}) async {
    final repository = context.read<DietPlanRepository>();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DietPlanBuilderScreen(
        controller: DietPlanBuilderController(repository, dietPlanId: dietPlanId),
      ),
    ));
    if (!mounted) return;
    _controller.load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('My Diet Plans', style: AppTypography.headlineSm),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openBuilder(),
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New plan'),
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => SafeArea(
          child: RefreshIndicator(
            onRefresh: () => _controller.load(force: true),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                  AppSpacing.sm, AppSpacing.marginMobile, AppSpacing.xxl),
              child: ResourceBuilder<List<DietPlan>>(
                state: _controller.state,
                onRetry: _controller.load,
                minHeight: 320,
                builder: (context, plans) {
                  if (plans.isEmpty) {
                    return const MascotEmptyState(
                      title: 'No diet plans yet',
                      message:
                          'Build your own meal plan - tap "New plan" to start.',
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final plan in plans) ...[
                        _MyDietPlanRow(
                          plan: plan,
                          onTap: () => _openBuilder(dietPlanId: plan.dietPlanId),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MyDietPlanRow extends StatelessWidget {
  final DietPlan plan;
  final VoidCallback onTap;

  const _MyDietPlanRow({required this.plan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SectionCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.name,
                      style: AppTypography.headlineSm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${plan.periodType} • ${plan.durationDays} days',
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
