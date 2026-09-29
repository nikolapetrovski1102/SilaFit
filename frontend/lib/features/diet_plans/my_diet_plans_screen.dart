import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../auth/widgets/auth_blob_background.dart';
import '../splits/widgets/split_hero_image.dart';
import 'diet_creation_wizard_screen.dart';
import 'diet_plan_builder_screen.dart';
import 'diet_plan_controller.dart';
import 'diet_plan_models.dart';
import 'diet_plan_repository.dart';
import 'diet_plans_screen.dart';

/// The user's own diet plans - built via the in-app builder, always fully
/// editable. The Nutrition "Active Diet Plan" section's destination, laid out
/// the same as [MySplitsScreen]: a big "Create Diet Plan" entry point into the
/// step-by-step wizard, the user's plans, and a link out to the browsable
/// library ([DietPlansScreen]).
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

  /// New diets go through the same one-field, day-by-day flow as splits.
  Future<void> _openWizard() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DietCreationWizardScreen(
        existingPlanCount: _controller.state.data?.length ?? 0,
      ),
    ));
    if (!mounted) return;
    _controller.load(force: true);
    context.read<ActiveDietPlanController>().load(force: true);
  }

  void _openBuilder(String dietPlanId) async {
    final repository = context.read<DietPlanRepository>();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DietPlanBuilderScreen(
        controller:
            DietPlanBuilderController(repository, dietPlanId: dietPlanId),
      ),
    ));
    if (!mounted) return;
    _controller.load(force: true);
    context.read<ActiveDietPlanController>().load(force: true);
  }

  Future<void> _activatePlan(DietPlan plan) async {
    final activeController = context.read<ActiveDietPlanController>();
    final ok = await activeController.activate(plan.dietPlanId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? '${plan.name} is now your active diet plan.'
            : activeController.actionError ??
                'Could not activate this plan.')));
  }

  @override
  Widget build(BuildContext context) {
    final activePlanId = context
        .watch<ActiveDietPlanController>()
        .state
        .data
        ?.plan
        ?.plan
        .dietPlanId;

    return Scaffold(
      backgroundColor: AppColors.background,
      // Lets the blob backdrop bleed all the way behind the (transparent)
      // AppBar - matching MySplitsScreen.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: AuthBlobBackground(layout: 3)),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: () => _controller.load(force: true),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                      AppSpacing.marginMobile,
                      AppSpacing.xs,
                      AppSpacing.marginMobile,
                      AppSpacing.xxl + MediaQuery.paddingOf(context).bottom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionEyebrow('Your Nutrition', color: AppColors.accent),
                      const SizedBox(height: 4),
                      Text('My Diet Plans', style: AppTypography.headlineLg),
                      const SizedBox(height: AppSpacing.lg),
                      _CreateDietPlanCta(onTap: _openWizard),
                      if (activePlanId == null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Text('No active diet plan yet',
                            style: AppTypography.headlineSm),
                        const SizedBox(height: AppSpacing.xs),
                        Text('Create one to get your nutrition on track.',
                            style: AppTypography.bodyMd
                                .copyWith(color: AppColors.onSurfaceVariant)),
                      ],
                      ResourceBuilder<List<DietPlan>>(
                        state: _controller.state,
                        onRetry: _controller.load,
                        builder: (context, plans) {
                          if (plans.isEmpty) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: AppSpacing.lg),
                              const SectionEyebrow('Your diet plans'),
                              const SizedBox(height: AppSpacing.sm),
                              for (final plan in plans) ...[
                                _MyDietPlanCard(
                                  plan: plan,
                                  isActive: activePlanId == plan.dietPlanId,
                                  onTap: () => _openBuilder(plan.dietPlanId),
                                  onActivate: () => _activatePlan(plan),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _SuggestedDietPlansRow(
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const DietPlansScreen())),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Always-visible entry point into [DietCreationWizardScreen] - the same loud
/// CTA as My Splits' "Create Split".
class _CreateDietPlanCta extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateDietPlanCta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.accent, AppColors.accent.withOpacity(0.78)],
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.onAccent.withOpacity(0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add_rounded, color: AppColors.onAccent),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Create Diet Plan',
                      style: AppTypography.headlineSm
                          .copyWith(color: AppColors.onAccent)),
                  const SizedBox(height: 2),
                  Text('One simple step at a time',
                      style: AppTypography.bodySm.copyWith(
                          color: AppColors.onAccent.withOpacity(0.85))),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: AppColors.onAccent),
          ],
        ),
      ),
    );
  }
}

/// One of the user's own diet plans, in the same hero-image card language as
/// My Splits' cards, plus an activate affordance.
class _MyDietPlanCard extends StatefulWidget {
  final DietPlan plan;
  final bool isActive;
  final VoidCallback onTap;
  final Future<void> Function() onActivate;

  const _MyDietPlanCard({
    required this.plan,
    required this.isActive,
    required this.onTap,
    required this.onActivate,
  });

  @override
  State<_MyDietPlanCard> createState() => _MyDietPlanCardState();
}

class _MyDietPlanCardState extends State<_MyDietPlanCard> {
  bool _activating = false;

  Future<void> _handleActivate() async {
    if (_activating) return;
    setState(() => _activating = true);
    await widget.onActivate();
    if (!mounted) return;
    setState(() => _activating = false);
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return GestureDetector(
      onTap: widget.onTap,
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
                    child: SplitHeroImage(plan.heroImageUrl),
                  ),
                ),
                if (widget.isActive)
                  Positioned(
                    top: AppSpacing.sm,
                    left: AppSpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(AppRadius.full)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded,
                              size: 12, color: AppColors.onAccent),
                          const SizedBox(width: 6),
                          Text('ACTIVE',
                              style: AppTypography.labelCaps
                                  .copyWith(color: AppColors.onAccent)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.name,
                      style: AppTypography.headlineSm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            _MetaPill(
                                icon: Icons.calendar_view_week_rounded,
                                label: '${plan.durationDays} days'),
                            _MetaPill(
                                icon: Icons.event_repeat_rounded,
                                label: plan.periodType),
                          ],
                        ),
                      ),
                      if (widget.isActive)
                        Text('Active',
                            style: AppTypography.labelSm
                                .copyWith(color: AppColors.accent))
                      else
                        _activating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                tooltip: 'Set as active diet plan',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(Icons.play_circle_outline_rounded,
                                    color: AppColors.accent),
                                onPressed: _handleActivate,
                              ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
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

/// Bottom link out to the full browsable library in [DietPlansScreen].
class _SuggestedDietPlansRow extends StatelessWidget {
  final VoidCallback onTap;

  const _SuggestedDietPlansRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SectionCard(
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: AppColors.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text('Suggested diet plans',
                  style: AppTypography.bodyMd
                      .copyWith(fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
