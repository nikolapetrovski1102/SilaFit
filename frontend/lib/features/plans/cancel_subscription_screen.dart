import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/legal_links.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/silen_ambient_backdrop.dart';
import '../../core/widgets/silen_button.dart';
import '../progress/progress_repository.dart';
import 'plans_controller.dart';
import 'plans_models.dart';

/// Three-step retention flow ahead of the store's cancel screen, opened from
/// the plan list when a paying user picks Free or "Cancel subscription": a "stay"
/// pitch (with a cheaper tier when one exists), what the user's training
/// history adds up to, then the hand-off to the store. The store owns
/// renewal, so the last step can only send the user there - and the
/// "Continue to cancel" link stays a readable, full-size tap target on every
/// step (App Review 3.1.2 rejects cancel paths that are hard to find).
class CancelSubscriptionScreen extends StatefulWidget {
  final CurrentSubscription subscription;

  const CancelSubscriptionScreen({super.key, required this.subscription});

  @override
  State<CancelSubscriptionScreen> createState() =>
      _CancelSubscriptionScreenState();
}

typedef _History = ({
  int sessions,
  double tonnageKg,
  int streakDays,
  int exercises,
});

class _CancelSubscriptionScreenState extends State<CancelSubscriptionScreen> {
  static const _stepCount = 3;

  int _step = 0;
  _History? _history;

  @override
  void initState() {
    super.initState();
    final plans = context.read<PlansController>();
    if (!plans.state.hasData) plans.load();
    _loadHistory();
  }

  // Best-effort: if either call fails, step 2 just shows the plan features
  // without the stats block rather than blocking the flow.
  Future<void> _loadHistory() async {
    final repo = context.read<ProgressRepository>();
    try {
      final (overview, exercises) = await (
        repo.getOverview(days: 365),
        repo.getTrackedExercises(),
      ).wait;
      if (!mounted) return;
      setState(() => _history = (
            sessions: overview.completedSessions,
            tonnageKg: overview.totalTonnageKg,
            streakDays: overview.currentStreakDays,
            exercises: exercises.length,
          ));
    } catch (_) {}
  }

  void _keep() => Navigator.of(context).pop();

  void _next() => setState(() => _step++);

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() => _step--);
    }
  }

  // Pops back to the plan list (the only way in) with the tier selected, so
  // the switch goes through the regular purchase footer.
  void _switchTo(PlanCatalogEntry tier) =>
      Navigator.of(context).pop(tier.plan.planId);

  /// The cheapest paid tier below the user's current one, if any.
  PlanCatalogEntry? _cheaperTier(List<PlanCatalogEntry>? catalog) {
    if (catalog == null) return null;
    final current = catalog
        .where((e) => e.plan.code.toUpperCase() == widget.subscription.planCode)
        .firstOrNull;
    if (current == null) return null;
    final cheaper = catalog
        .where((e) =>
            e.plan.monthlyPrice > 0 &&
            e.plan.monthlyPrice < current.plan.monthlyPrice)
        .toList()
      ..sort((a, b) => a.plan.monthlyPrice.compareTo(b.plan.monthlyPrice));
    return cheaper.firstOrNull;
  }

  List<PlanFeature> _currentFeatures(List<PlanCatalogEntry>? catalog) =>
      catalog
          ?.where(
              (e) => e.plan.code.toUpperCase() == widget.subscription.planCode)
          .firstOrNull
          ?.features ??
      const [];

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<PlansController>().state.data;
    final sub = widget.subscription;
    final cheaper = _cheaperTier(catalog);

    final (Widget body, Widget actions) = switch (_step) {
      0 => (
          _StayStep(subscription: sub),
          _Actions(
            primaryLabel: 'Keep SilaFit ${sub.planName}',
            onPrimary: _keep,
            secondaryLabel: switch (cheaper) {
              final tier? => 'Switch to ${tier.plan.name} instead',
              null => null,
            },
            onSecondary: cheaper == null ? null : () => _switchTo(cheaper),
            onContinue: _next,
          ),
        ),
      1 => (
          _LossStep(history: _history, features: _currentFeatures(catalog)),
          _Actions(
            primaryLabel: 'Keep my progress',
            onPrimary: _keep,
            onContinue: _next,
          ),
        ),
      _ => (
          _StoreStep(subscription: sub),
          _Actions(
            primaryLabel: 'Keep SilaFit ${sub.planName}',
            onPrimary: _keep,
            secondaryLabel: 'Open $storeName subscriptions',
            onSecondary: () async {
              await openManageSubscriptions();
              if (mounted) _keep();
            },
          ),
        ),
    };

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: SilenAmbientBackdrop()),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.xs,
                        AppSpacing.xs, AppSpacing.marginMobile, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_rounded,
                              color: AppColors.onSurface),
                          tooltip: 'Back',
                          onPressed: _back,
                        ),
                        Expanded(
                          child: Text('Cancel subscription',
                              style: AppTypography.bodyMd
                                  .copyWith(fontWeight: FontWeight.w600)),
                        ),
                        Text('${_step + 1} of $_stepCount',
                            style: AppTypography.bodySm
                                .copyWith(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: SingleChildScrollView(
                        key: ValueKey(_step),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.marginMobile,
                            vertical: AppSpacing.lg),
                        child: body,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                        0, AppSpacing.marginMobile, AppSpacing.xs),
                    child: actions,
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

String _formatDate(DateTime? utc) => utc == null
    ? 'the end of this period'
    : DateFormat.yMMMd().format(utc.toLocal());

class _StayStep extends StatelessWidget {
  final CurrentSubscription subscription;

  const _StayStep({required this.subscription});

  @override
  Widget build(BuildContext context) {
    final sub = subscription;
    final muted =
        AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("We'd hate to see you go", style: AppTypography.headlineLg),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'If you cancel, SilaFit ${sub.planName} stays active until '
          '${_formatDate(sub.expiresAtUtc)}. After that your account moves '
          'to the Free plan and premium features lock.',
          style:
              AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          child: Column(
            children: [
              _DetailRow(label: 'Plan', value: 'SilaFit ${sub.planName}'),
              const SizedBox(height: AppSpacing.xs),
              _DetailRow(
                  label: 'Billing',
                  value: sub.billingCycle ?? 'Subscription',
                  style: muted),
              const SizedBox(height: AppSpacing.xs),
              _DetailRow(
                label: sub.autoRenewing ? 'Renews' : 'Ends',
                value: _formatDate(sub.expiresAtUtc),
                style: muted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LossStep extends StatelessWidget {
  final _History? history;
  final List<PlanFeature> features;

  const _LossStep({required this.history, required this.features});

  @override
  Widget build(BuildContext context) {
    final h = history;
    final hasHistory = h != null && (h.sessions > 0 || h.exercises > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.errorContainer,
            borderRadius: BorderRadius.circular(AppSpacing.sm),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: AppColors.onErrorContainer),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Premium insights built from your training stop updating '
                  'once your plan ends.',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (hasHistory) ...[
          Center(
            child: Text('${h.sessions}',
                style: AppTypography.displayStatXl
                    .copyWith(color: AppColors.accent)),
          ),
          Center(
            child: Text('workouts completed this year',
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            child: Column(
              children: [
                _DetailRow(
                    label: 'Volume lifted',
                    value:
                        '${NumberFormat.decimalPattern().format(h.tonnageKg.round())} kg'),
                const SizedBox(height: AppSpacing.xs),
                _DetailRow(label: 'Exercises tracked', value: '${h.exercises}'),
                const SizedBox(height: AppSpacing.xs),
                _DetailRow(
                    label: 'Current streak', value: '${h.streakDays} days'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ] else ...[
          Text("You're about to lose", style: AppTypography.headlineLg),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (features.isNotEmpty)
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Included in your plan',
                    style: AppTypography.bodyMd
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.xs),
                for (final f in features)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_rounded,
                            size: 18, color: AppColors.accent),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                            child: Text(f.featureText,
                                style: AppTypography.bodySm)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StoreStep extends StatelessWidget {
  final CurrentSubscription subscription;

  const _StoreStep({required this.subscription});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cancel in $storeName', style: AppTypography.headlineLg),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '$storeName manages your subscription, so the last step happens '
          'there. You keep full access until '
          '${_formatDate(subscription.expiresAtUtc)}, and your workouts, '
          'meals and history stay on your account.',
          style:
              AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? style;

  const _DetailRow({required this.label, required this.value, this.style});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.onSurfaceVariant)),
        ),
        Text(value,
            style: style ??
                AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final VoidCallback? onContinue;

  const _Actions({
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PrimaryPillButton(
            label: primaryLabel, onPressed: onPrimary, height: 50),
        if (secondaryLabel != null) ...[
          const SizedBox(height: AppSpacing.xs),
          SecondaryPillButton(
            label: secondaryLabel!,
            foregroundColor: AppColors.accent,
            onPressed: onSecondary,
          ),
        ],
        if (onContinue != null)
          TextButton(
            onPressed: onContinue,
            // Full-size tap target and readable color - see the class doc.
            style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12)),
            child: Text('Continue to cancel',
                style: AppTypography.bodySm
                    .copyWith(fontSize: 14, color: AppColors.onSurfaceVariant)),
          ),
      ],
    );
  }
}
