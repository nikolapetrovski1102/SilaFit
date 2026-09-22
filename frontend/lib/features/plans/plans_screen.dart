import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/session/session_store.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_ambient_backdrop.dart';
import '../../core/widgets/silen_button.dart';
import '../auth/account_gate.dart';
import '../progress/analytics_controller.dart';
import '../progress/weekly_analytics_controller.dart';
import 'plans_controller.dart';
import 'plans_models.dart';

class PlansScreen extends StatefulWidget {
  final bool isWelcomeOffer;
  final VoidCallback? onDismiss;

  const PlansScreen({
    super.key,
    this.isWelcomeOffer = false,
    this.onDismiss,
  });

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

/// 50% off, floored to the cent rather than rounded - so e.g. $2.99 shows as
/// $1.49 (matching the $1.49 Apple/Play introductory-offer price actually
/// charged) instead of $1.50, which toStringAsFixed's round-half-up would
/// otherwise produce from the exact $1.495 midpoint.
double _welcomeOfferPrice(double price) => (price * 50).floorToDouble() / 100;

class _PlansScreenState extends State<PlansScreen> {
  late final PlansController _controller;

  // Which row the sticky footer CTA acts on. Null until the user taps a
  // row, at which point it sticks - until then `_selectedEntry` derives a
  // sensible default (the featured paid tier) on every build instead.
  String? _selectedPlanId;

  // One GlobalKey per plan row so the selected row can be scrolled into view
  // once it finishes expanding - see `_selectPlan`.
  final Map<String, GlobalKey> _rowKeys = {};

  GlobalKey _rowKeyFor(String planId) =>
      _rowKeys.putIfAbsent(planId, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _controller = context.read<PlansController>();
    // Deferred - see the matching comment in today_screen.dart: load()'s
    // first notifyListeners() must not fire synchronously mid-build.
    Future.microtask(_controller.load);
  }

  Future<void> _dismiss() async {
    await context.read<SessionStore>().markFeatureTourComplete();
    if (!mounted) return;
    if (widget.onDismiss != null) {
      widget.onDismiss!();
    } else {
      Navigator.of(context).pop();
    }
  }

  static bool _isFree(SubscriptionPlan plan) =>
      plan.monthlyPrice == 0 && plan.yearlyPrice == 0;

  /// The paid tier a paywall should lead with: the featured one, or the
  /// cheapest paid tier if none is marked featured. A free "keep browsing"
  /// row never drives the sticky CTA.
  PlanCatalogEntry? _defaultEntry(List<PlanCatalogEntry> catalog) {
    final paid = catalog.where((e) => !_isFree(e.plan)).toList()
      ..sort((a, b) => a.plan.monthlyPrice.compareTo(b.plan.monthlyPrice));
    if (paid.isEmpty) return null;
    return paid.firstWhere((e) => e.plan.isFeatured, orElse: () => paid.first);
  }

  PlanCatalogEntry? _selectedEntry(List<PlanCatalogEntry> catalog) {
    final id = _selectedPlanId;
    if (id != null) {
      for (final entry in catalog) {
        if (entry.plan.planId == id) return entry;
      }
    }
    return _defaultEntry(catalog);
  }

  void _selectPlan(String planId) {
    setState(() => _selectedPlanId = planId);
    // Wait for the row's AnimatedSize expansion (see _PlanRow) to finish
    // before measuring where to scroll, otherwise the target offset is
    // computed against the still-collapsed height.
    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final rowContext = _rowKeys[planId]?.currentContext;
      if (rowContext == null) return;
      // Freshly re-read from the GlobalKey right after the `mounted` check
      // above, not a BuildContext captured before the delay.
      Scrollable.ensureVisible(
        // ignore: use_build_context_synchronously
        rowContext,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignment: 0.1,
      );
    });
  }

  Future<void> _purchase(SubscriptionPlan plan) async {
    final hasAccount = await AccountGate.ensure(context);
    if (!hasAccount || !mounted) return;
    final ok = await _controller.purchase(plan);
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
      if (widget.isWelcomeOffer) {
        await context.read<SessionStore>().markFeatureTourComplete();
        if (mounted) {
          if (widget.onDismiss != null) {
            widget.onDismiss!();
          } else {
            Navigator.of(context).pop();
          }
        }
      }
    } else if (_controller.actionError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_controller.actionError!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeOffer = widget.isWelcomeOffer;

    return Scaffold(
      backgroundColor: AppColors.background,
      // No AppBar on this screen - a Material AppBar tints/dims as content
      // scrolls underneath it (scrolledUnderElevation), which fought the
      // ambient blur backdrop. The close/back control below is a plain
      // floating icon instead, so it never dims and the tier list can start
      // right at the top of the screen.
      body: Stack(
        children: [
          const Positioned.fill(child: SilenAmbientBackdrop()),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final catalog = _controller.state.data;
              final selected = catalog != null ? _selectedEntry(catalog) : null;

              return SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.marginMobile,
                          AppSpacing.xs,
                          AppSpacing.marginMobile,
                          AppSpacing.md,
                        ),
                        // Header + billing toggle don't need the catalogue, so
                        // they stay visible even when that fetch is slow or
                        // fails - only the plan rows themselves (which do
                        // need it) sit behind the ResourceBuilder below.
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _PlansHeader(
                              controller: _controller,
                              isWelcomeOffer: activeOffer,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            ResourceBuilder<List<PlanCatalogEntry>>(
                              state: _controller.state,
                              onRetry: _controller.load,
                              builder: (context, catalog) => _PlanList(
                                controller: _controller,
                                catalog: catalog,
                                selectedPlanId:
                                    _selectedEntry(catalog)?.plan.planId,
                                onSelect: _selectPlan,
                                rowKeyFor: _rowKeyFor,
                                isWelcomeOffer: activeOffer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (selected != null)
                      _PlansFooter(
                        controller: _controller,
                        entry: selected,
                        isWelcomeOffer: activeOffer,
                        isWelcomeOfferFlow: widget.isWelcomeOffer,
                        onPurchase: () => _purchase(selected.plan),
                        onSkip: _dismiss,
                      ),
                  ],
                ),
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Align(
                alignment: Alignment.topLeft,
                child: _TopControl(
                  icon: widget.isWelcomeOffer
                      ? Icons.close_rounded
                      : Icons.arrow_back_rounded,
                  onPressed: widget.isWelcomeOffer
                      ? _dismiss
                      : () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A bare icon button floating over the ambient backdrop - deliberately not
/// an AppBar, which tints/dims via `scrolledUnderElevation` as content
/// scrolls beneath it.
class _TopControl extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _TopControl({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: AppColors.onSurface),
        tooltip: 'Back',
        onPressed: onPressed,
      ),
    );
  }
}

class _PlansHeader extends StatelessWidget {
  final PlansController controller;
  final bool isWelcomeOffer;

  const _PlansHeader({
    required this.controller,
    this.isWelcomeOffer = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (isWelcomeOffer)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.full),
              border:
                  Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_fire_department_rounded,
                    size: 14, color: AppColors.accent),
                const SizedBox(width: 4),
                Text(
                  'NEW MEMBER · 50% OFF FIRST BILLING PERIOD',
                  style: AppTypography.labelCaps.copyWith(
                      color: AppColors.accent, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          )
        else
          const PillChip(
              label: 'System Telemetry & Access',
              icon: Icons.bolt_rounded,
              selected: true),
        const SizedBox(height: AppSpacing.sm),
        Text('Choose Your Protocol',
            style: AppTypography.headlineMd, textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(
          isWelcomeOffer
              ? 'New members get 50% off their first billing period on every premium tier.'
              : 'Transparent pricing. Upgrade or cancel anytime.',
          style: AppTypography.bodySm,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        _BillingToggle(controller: controller),
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
              label: 'Yearly · Save 30%',
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
          padding: const EdgeInsets.symmetric(vertical: 9),
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

class _PlanList extends StatelessWidget {
  final PlansController controller;
  final List<PlanCatalogEntry> catalog;
  final String? selectedPlanId;
  final ValueChanged<String> onSelect;
  final GlobalKey Function(String planId) rowKeyFor;
  final bool isWelcomeOffer;

  const _PlanList({
    required this.controller,
    required this.catalog,
    required this.selectedPlanId,
    required this.onSelect,
    required this.rowKeyFor,
    this.isWelcomeOffer = false,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...catalog]
      ..sort((a, b) => a.plan.monthlyPrice.compareTo(b.plan.monthlyPrice));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in sorted) ...[
          _PlanRow(
            key: rowKeyFor(entry.plan.planId),
            entry: entry,
            controller: controller,
            selected: entry.plan.planId == selectedPlanId,
            isWelcomeOffer: isWelcomeOffer,
            onTap: () => onSelect(entry.plan.planId),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

/// A compact, single-select plan row. Collapsed it's one line (name +
/// price); the selected row expands in place to show its feature list, so
/// only one tier's details are ever on screen at once - the rest of the
/// tradeoff-comparison stays out of the way instead of stacking three full
/// cards' worth of copy.
class _PlanRow extends StatefulWidget {
  final PlanCatalogEntry entry;
  final PlansController controller;
  final bool selected;
  final bool isWelcomeOffer;
  final VoidCallback onTap;

  const _PlanRow({
    super.key,
    required this.entry,
    required this.controller,
    required this.selected,
    required this.onTap,
    this.isWelcomeOffer = false,
  });

  bool get _isFree =>
      entry.plan.monthlyPrice == 0 && entry.plan.yearlyPrice == 0;

  @override
  State<_PlanRow> createState() => _PlanRowState();
}

class _PlanRowState extends State<_PlanRow> {
  bool _pressed = false;

  void _setPressed(bool value) => setState(() => _pressed = value);

  void _handleTap() {
    if (!widget.selected) HapticFeedback.selectionClick();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    if (widget._isFree) return _FreeRow(name: widget.entry.plan.name);

    final entry = widget.entry;
    final controller = widget.controller;
    final selected = widget.selected;
    final isWelcomeOffer = widget.isWelcomeOffer;

    final price =
        controller.isYearly ? entry.plan.yearlyPrice : entry.plan.monthlyPrice;
    final cadence = controller.isYearly ? '/yr' : '/mo';
    final periodDays = controller.isYearly ? 365 : 30;
    final effectivePrice = isWelcomeOffer ? _welcomeOfferPrice(price) : price;
    final perDay = effectivePrice / periodDays;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: _handleTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.surfaceContainer
                : AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  selected ? AppColors.accent : AppColors.surfaceContainerHigh,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.18),
                      blurRadius: 16,
                      spreadRadius: -4,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : const [],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _RadioDot(selected: selected),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isWelcomeOffer)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 2),
                              child: _Badge(label: '50% OFF'),
                            )
                          else if (entry.plan.isFeatured)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 2),
                              child: _Badge(label: 'MOST POPULAR'),
                            ),
                          Text(entry.plan.name,
                              style: AppTypography.headlineSm
                                  .copyWith(fontSize: 16)),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            if (isWelcomeOffer) ...[
                              Text(
                                '\$${price.toStringAsFixed(2)}',
                                style: AppTypography.bodySm.copyWith(
                                    decoration: TextDecoration.lineThrough),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              '\$${effectivePrice.toStringAsFixed(2)}',
                              style: AppTypography.headlineSm.copyWith(
                                  fontSize: 18,
                                  color: isWelcomeOffer
                                      ? AppColors.accent
                                      : AppColors.highEmphasis),
                            ),
                            Text(cadence,
                                style: AppTypography.labelSm.copyWith(
                                    color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                        Text(
                          '≈ \$${perDay.toStringAsFixed(2)}/day',
                          style: AppTypography.labelSm.copyWith(
                              fontSize: 11, color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: selected
                      ? _ExpandedDetails(entry: entry)
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool selected;

  const _RadioDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.accent : Colors.transparent,
        border: Border.all(
          color: selected
              ? AppColors.accent
              : AppColors.onSurfaceVariant.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Center(
        child: AnimatedScale(
          scale: selected ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: selected ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            child: Icon(Icons.check_rounded, size: 14, color: AppColors.onAccent),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;

  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Text(label,
          style: AppTypography.labelCaps
              .copyWith(color: AppColors.onAccent, fontSize: 9)),
    );
  }
}

class _ExpandedDetails extends StatelessWidget {
  final PlanCatalogEntry entry;

  const _ExpandedDetails({required this.entry});

  @override
  Widget build(BuildContext context) {
    // Fades and settles in from a slight offset each time this mounts (i.e.
    // each time the row becomes selected), rather than snapping into place
    // the instant AnimatedSize finishes making room for it.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 6),
          child: child,
        ),
      ),
      child: _ExpandedDetailsContent(entry: entry),
    );
  }
}

class _ExpandedDetailsContent extends StatelessWidget {
  final PlanCatalogEntry entry;

  const _ExpandedDetailsContent({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs, left: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.plan.tagline != null) ...[
            Text(entry.plan.tagline!, style: AppTypography.bodySm),
            const SizedBox(height: AppSpacing.xxs),
          ],
          for (final feature in entry.features)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    feature.isHighlighted
                        ? Icons.auto_awesome_rounded
                        : Icons.check_rounded,
                    size: 14,
                    color: feature.isHighlighted
                        ? AppColors.accent
                        : AppColors.secondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      feature.featureText,
                      style: AppTypography.bodySm.copyWith(
                        fontSize: 12.5,
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
        ],
      ),
    );
  }
}

/// The free tier shown as a muted, non-interactive line rather than a
/// selectable row - it's a baseline for comparison, not something to "buy",
/// so it shouldn't compete with the paid rows for tap targets or attention.
class _FreeRow extends StatelessWidget {
  final String name;

  const _FreeRow({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Icon(Icons.circle_outlined,
              size: 18,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(name,
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ),
          Text('Current Plan',
              style: AppTypography.labelSm.copyWith(
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

/// The sticky, always-visible purchase bar. Pulling the CTA out of each
/// card and pinning a single one to the bottom means the button never
/// scrolls out of view, and it always reflects whichever row is currently
/// selected.
class _PlansFooter extends StatelessWidget {
  final PlansController controller;
  final PlanCatalogEntry entry;
  final bool isWelcomeOffer;
  final bool isWelcomeOfferFlow;
  final VoidCallback onPurchase;
  final VoidCallback onSkip;

  const _PlansFooter({
    required this.controller,
    required this.entry,
    required this.isWelcomeOffer,
    required this.isWelcomeOfferFlow,
    required this.onPurchase,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final price =
        controller.isYearly ? entry.plan.yearlyPrice : entry.plan.monthlyPrice;
    final effectivePrice = isWelcomeOffer ? _welcomeOfferPrice(price) : price;
    final cadence = controller.isYearly ? 'year' : 'month';

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile, AppSpacing.xs,
          AppSpacing.marginMobile, AppSpacing.xs),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: AppColors.surfaceContainerHigh, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryPillButton(
            label: isWelcomeOffer
                ? 'Claim ${entry.plan.name} · \$${effectivePrice.toStringAsFixed(2)}/$cadence'
                : 'Upgrade to ${entry.plan.name} · \$${effectivePrice.toStringAsFixed(2)}/$cadence',
            icon: Icons.arrow_forward_rounded,
            isLoading: controller.isPurchasing,
            onPressed: onPurchase,
            height: 42,
          ),
          if (isWelcomeOfferFlow) ...[
            TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 24),
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text('Continue with Free Plan',
                  style: AppTypography.bodySm.copyWith(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w500)),
            ),
            if (isWelcomeOffer)
              Text('50% off applies to your first billing period only',
                  style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                      fontSize: 10)),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 12, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('Cancel anytime · Secure payment',
                      style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant, fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
