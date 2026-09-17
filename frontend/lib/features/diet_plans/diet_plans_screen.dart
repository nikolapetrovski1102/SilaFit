import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/mascot/mascot_empty_state.dart';
import '../../core/widgets/mascot/mascot_pose.dart';
import '../../core/widgets/section_eyebrow.dart';
import 'diet_plan_controller.dart';
import 'diet_plan_models.dart';
import 'my_diet_plans_screen.dart';
import 'widgets/diet_plan_card.dart';

/// Browse view for diet plans - the meal-planning equivalent of
/// `SplitsScreen`. Unlike splits, plans carry no server-computed
/// match/recommendation signal, so this stays a plain filterable catalog
/// rather than a ranked "best match" hero.
class DietPlansScreen extends StatefulWidget {
  const DietPlansScreen({super.key});

  @override
  State<DietPlansScreen> createState() => _DietPlansScreenState();
}

class _DietPlansScreenState extends State<DietPlansScreen> {
  late final DietPlansController _controller;
  String? _periodFilter;

  @override
  void initState() {
    super.initState();
    _controller = context.read<DietPlansController>();
    Future.microtask(_controller.load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyDietPlansScreen())),
            icon: Icon(Icons.edit_note_rounded, color: AppColors.onSurface),
            label: Text('My plans',
                style: AppTypography.labelSm.copyWith(color: AppColors.onSurface)),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                AppSpacing.sm, AppSpacing.marginMobile, AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionEyebrow('Meal Planning', color: AppColors.accent),
                const SizedBox(height: 4),
                Text('Diet Plans', style: AppTypography.headlineLg),
                const SizedBox(height: AppSpacing.md),
                ResourceBuilder<List<DietPlan>>(
                  state: _controller.state,
                  onRetry: _controller.load,
                  builder: (context, plans) => _buildContent(plans),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(List<DietPlan> plans) {
    if (plans.isEmpty) {
      return const MascotEmptyState(
        pose: MascotPose.ready,
        title: 'No diet plans yet',
        message: 'Weekly and monthly meal plans will show up here once ready.',
      );
    }
    final visible =
        _periodFilter == null ? plans : plans.where((p) => p.periodType == _periodFilter).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
            itemBuilder: (context, i) {
              const options = [null, 'Weekly', 'Monthly'];
              final value = options[i];
              return PillChip(
                label: value ?? 'All Plans',
                selected: _periodFilter == value,
                onTap: () => setState(() => _periodFilter = value),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
                child: Text('No plans match this filter.', style: AppTypography.bodySm)),
          ),
        for (final plan in visible) ...[
          DietPlanCard(plan: plan),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}
