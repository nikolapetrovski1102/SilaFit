import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import '../auth/account_gate.dart';
import '../progress/analytics_controller.dart';
import '../progress/weekly_analytics_controller.dart';
import 'plans_controller.dart';
import 'plans_models.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  late final PlansController _controller;

  @override
  void initState() {
    super.initState();
    _controller = context.read<PlansController>();
    // Deferred - see the matching comment in today_screen.dart: load()'s
    // first notifyListeners() must not fire synchronously mid-build.
    Future.microtask(_controller.load);
  }

  Future<void> _purchase(SubscriptionPlan plan) async {
    final hasAccount = await AccountGate.ensure(context);
    if (!hasAccount || !mounted) return;
    final ok = await _controller.purchase(plan.planId);
    if (!mounted) return;
    if (ok) {
      // The app-lifetime AnalyticsControllers otherwise only ever check
      // entitlement once, in ProgressScreen's initState - without this, a
      // fresh purchase leaves the AI Monthly/Weekly Review cards looking
      // locked until the app is restarted.
      context.read<AnalyticsController>().load(force: true);
      context.read<WeeklyAnalyticsController>().load(force: true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Upgraded to ${plan.name}.')));
    } else if (_controller.actionError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_controller.actionError!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return SafeArea(
            child: RefreshIndicator(
              onRefresh: () => _controller.load(force: true),
              color: AppColors.accent,
              backgroundColor: AppColors.surfaceContainer,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.marginMobile,
                    vertical: AppSpacing.sm),
                // Header + billing toggle don't need the catalogue, so they
                // stay visible even when that fetch is slow or fails -
                // only the plan cards themselves (which do need it) sit
                // behind the ResourceBuilder below.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PlansHeader(controller: _controller),
                    const SizedBox(height: AppSpacing.lg),
                    ResourceBuilder<List<PlanCatalogEntry>>(
                      state: _controller.state,
                      onRetry: _controller.load,
                      builder: (context, catalog) => _PlanCards(
                          controller: _controller,
                          catalog: catalog,
                          onPurchase: _purchase),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlansHeader extends StatelessWidget {
  final PlansController controller;

  const _PlansHeader({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const PillChip(
            label: 'System Telemetry & Access',
            icon: Icons.bolt_rounded,
            selected: true),
        const SizedBox(height: AppSpacing.sm),
        Text('Choose Your Protocol',
            style: AppTypography.headlineLg.copyWith(fontSize: 26),
            textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(
          'Transparent pricing. Upgrade or cancel anytime.',
          style: AppTypography.bodySm,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        _BillingToggle(controller: controller),
      ],
    );
  }
}

class _PlanCards extends StatelessWidget {
  final PlansController controller;
  final List<PlanCatalogEntry> catalog;
  final ValueChanged<SubscriptionPlan> onPurchase;

  const _PlanCards(
      {required this.controller,
      required this.catalog,
      required this.onPurchase});

  @override
  Widget build(BuildContext context) {
    final sorted = [...catalog]
      ..sort((a, b) => a.plan.monthlyPrice.compareTo(b.plan.monthlyPrice));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in sorted) ...[
          _PlanCard(
              entry: entry, controller: controller, onPurchase: onPurchase),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _BillingToggle extends StatelessWidget {
  final PlansController controller;

  const _BillingToggle({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Row(
        children: [
          _ToggleButton(
              label: 'Monthly',
              selected: !controller.isYearly,
              onTap: () => controller.setBillingCycle(yearly: false)),
          _ToggleButton(
              label: 'Yearly · -30%',
              selected: controller.isYearly,
              onTap: () => controller.setBillingCycle(yearly: true)),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleButton(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          alignment: Alignment.center,
          child: Text(
            label.toUpperCase(),
            style: AppTypography.labelCaps.copyWith(
                color:
                    selected ? AppColors.onAccent : AppColors.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final PlanCatalogEntry entry;
  final PlansController controller;
  final ValueChanged<SubscriptionPlan> onPurchase;

  const _PlanCard(
      {required this.entry,
      required this.controller,
      required this.onPurchase});

  bool get _isFree =>
      entry.plan.monthlyPrice == 0 && entry.plan.yearlyPrice == 0;

  @override
  Widget build(BuildContext context) {
    final price =
        controller.isYearly ? entry.plan.yearlyPrice : entry.plan.monthlyPrice;
    final cadence = controller.isYearly ? '/YEAR' : '/MONTH';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: entry.plan.isFeatured
            ? AppColors.surfaceContainer
            : AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: entry.plan.isFeatured
            ? Border.all(color: AppColors.accent.withOpacity(0.4))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (entry.plan.isFeatured)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius:
                                BorderRadius.circular(AppRadius.full)),
                        child: Text('MOST POPULAR',
                            style: AppTypography.labelCaps.copyWith(
                                color: AppColors.onAccent, fontSize: 9)),
                      ),
                    Text(entry.plan.name.toUpperCase(),
                        style: AppTypography.headlineMd.copyWith(fontSize: 20)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_isFree ? '€0' : '€${price.toStringAsFixed(2)}',
                      style: AppTypography.metricMd),
                  Text(cadence,
                      style: AppTypography.labelCaps
                          .copyWith(color: AppColors.accent)),
                ],
              ),
            ],
          ),
          if (entry.plan.tagline != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(entry.plan.tagline!, style: AppTypography.bodySm),
          ],
          const SizedBox(height: AppSpacing.sm),
          for (final feature in entry.features)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    feature.isHighlighted
                        ? Icons.auto_awesome_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 16,
                    color: feature.isHighlighted
                        ? AppColors.accent
                        : AppColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feature.featureText,
                      style: AppTypography.bodySm.copyWith(
                        color: feature.isHighlighted
                            ? AppColors.highEmphasis
                            : AppColors.onSurface,
                        fontWeight: feature.isHighlighted
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          if (_isFree)
            const SecondaryPillButton(label: 'Current Plan', onPressed: null)
          else
            PrimaryPillButton(
              label: 'Upgrade to ${entry.plan.name}',
              icon: Icons.arrow_forward_rounded,
              isLoading: controller.isPurchasing,
              onPressed: () => onPurchase(entry.plan),
            ),
        ],
      ),
    );
  }
}
