import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/session/session_store.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/legal_links.dart';
import '../../core/widgets/silen_ambient_backdrop.dart';
import '../../core/widgets/silen_button.dart';
import '../auth/account_gate.dart';
import '../progress/analytics_controller.dart';
import '../progress/weekly_analytics_controller.dart';
import 'cancel_subscription_screen.dart';
import 'iap_service.dart';
import 'plans_controller.dart';
import 'plans_models.dart';
import 'restore_purchases_action.dart';

/// Where Settings' "Manage" goes. A paying user lands on the plan list with
/// their current plan selected - picking Free or "Cancel subscription" from
/// there opens [CancelSubscriptionScreen]. Free users and guests have nothing
/// to manage in-app, so they go straight to the store.
Future<void> manageSubscription(
    BuildContext context, CurrentSubscription? subscription) async {
  if (subscription == null || !subscription.isPaid) {
    await openManageSubscriptions();
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PlansScreen(currentSubscription: subscription),
  ));
}

class PlansScreen extends StatefulWidget {
  final bool isWelcomeOffer;
  final VoidCallback? onDismiss;

  /// The caller's paid plan when opened to manage it (see
  /// [manageSubscription]) - preselects that plan and offers the cancel flow.
  final CurrentSubscription? currentSubscription;

  const PlansScreen({
    super.key,
    this.isWelcomeOffer = false,
    this.onDismiss,
    this.currentSubscription,
  });

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

/// Every price on this screen comes from the store's own quote
/// ([StoreQuote]) - localized, and including an intro offer only when the
/// store says this user gets one (App Review 3.1.2 / 2.3.7). The catalogue's
/// USD figures are only a fallback for when the store can't be reached, in
/// which case purchasing is unavailable anyway.
String _fallbackPrice(double usd) =>
    NumberFormat.simpleCurrency(name: 'USD').format(usd);

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

  CurrentSubscription? get _current =>
      widget.currentSubscription?.isPaid == true
          ? widget.currentSubscription
          : null;

  @override
  void initState() {
    super.initState();
    _controller = context.read<PlansController>();
    // Deferred - see the matching comment in today_screen.dart: load()'s
    // first notifyListeners() must not fire synchronously mid-build.
    Future.microtask(_controller.load);
    // Open on the cycle the user actually pays for, so their current plan
    // reads as current rather than as a switch to the other cycle.
    final cycle = _current?.billingCycle;
    if (cycle != null) {
      Future.microtask(
          () => _controller.setBillingCycle(yearly: cycle == 'Yearly'));
    }
  }

  bool _isCurrentPlan(SubscriptionPlan plan) =>
      _current != null && plan.code.toUpperCase() == _current!.planCode;

  /// The current plan on the cycle it's billed on - anything else selected
  /// is a plan change the store can process.
  bool _isCurrentSelection(SubscriptionPlan plan) {
    if (!_isCurrentPlan(plan)) return false;
    final cycle = _current!.billingCycle;
    return cycle == null || (cycle == 'Yearly') == _controller.isYearly;
  }

  Future<void> _openCancelFlow() async {
    final switchTo = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CancelSubscriptionScreen(subscription: _current!),
      ),
    );
    if (switchTo != null && mounted) _selectPlan(switchTo);
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
    for (final entry in catalog) {
      if (_isCurrentPlan(entry.plan)) return entry;
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
      // ambient blur backdrop. Regular plan browsing keeps a floating back
      // control; the welcome-offer step gets a floating close control instead
      // - it must stay dismissible even when the catalogue or store products
      // fail to load and the footer's "Continue with Free Plan" never renders
      // (App Review 3.1.2 / 5.6).
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
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.marginMobile,
                          activeOffer ? 0 : AppSpacing.xs,
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
                              isManaging: _current != null,
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
                                currentPlanCode: _current?.planCode,
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
                        isCurrent: _isCurrentSelection(selected.plan),
                        onPurchase: () => _purchase(selected.plan),
                        onSkip: _dismiss,
                        onCancelSubscription:
                            _current != null ? _openCancelFlow : null,
                      ),
                  ],
                ),
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: widget.isWelcomeOffer
                  ? Align(
                      alignment: Alignment.topRight,
                      child: _TopControl(
                        icon: Icons.close_rounded,
                        tooltip: 'Close',
                        onPressed: _dismiss,
                      ),
                    )
                  : Align(
                      alignment: Alignment.topLeft,
                      child: _TopControl(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
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
  final String tooltip;
  final VoidCallback onPressed;

  const _TopControl(
      {required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: AppColors.onSurface),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

class _PlansHeader extends StatelessWidget {
  final PlansController controller;
  final bool isWelcomeOffer;
  final bool isManaging;

  const _PlansHeader({
    required this.controller,
    this.isWelcomeOffer = false,
    this.isManaging = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(isManaging ? 'Manage Your Plan' : 'Choose Your Protocol',
            style: AppTypography.headlineMd, textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(
          isWelcomeOffer && controller.hasIntroOffer
              ? 'New members get an introductory price on their first billing period.'
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
              label: switch (controller.yearlySavingsPercent) {
                final pct? => 'Yearly · Save $pct%',
                null => 'Yearly',
              },
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

  /// The paid plan being managed, or null on a plain paywall.
  final String? currentPlanCode;

  const _PlanList({
    required this.controller,
    required this.catalog,
    required this.selectedPlanId,
    required this.onSelect,
    required this.rowKeyFor,
    this.isWelcomeOffer = false,
    this.currentPlanCode,
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
            isManaging: currentPlanCode != null,
            isCurrentPlan: entry.plan.code.toUpperCase() == currentPlanCode,
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
  final bool isManaging;
  final bool isCurrentPlan;
  final VoidCallback onTap;

  const _PlanRow({
    super.key,
    required this.entry,
    required this.controller,
    required this.selected,
    required this.onTap,
    this.isWelcomeOffer = false,
    this.isManaging = false,
    this.isCurrentPlan = false,
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
    if (widget._isFree) {
      // Managing a paid plan, Free is a real choice (it leads to the cancel
      // flow); on a plain paywall it's the user's current baseline.
      return _FreeRow(
        name: widget.entry.plan.name,
        isCurrent: !widget.isManaging,
        selected: widget.selected,
        onTap: widget.isManaging ? _handleTap : null,
      );
    }

    final entry = widget.entry;
    final controller = widget.controller;
    final selected = widget.selected;

    final quote = controller.quoteFor(entry.plan);
    final intro = quote?.intro;
    final catalogPrice =
        controller.isYearly ? entry.plan.yearlyPrice : entry.plan.monthlyPrice;
    final priceText = quote?.price ?? _fallbackPrice(catalogPrice);
    final cadence = controller.isYearly ? '/yr' : '/mo';
    final periodDays = controller.isYearly ? 365 : 30;
    final perDayText = quote != null
        ? quote.format(quote.rawPrice / periodDays)
        : _fallbackPrice(catalogPrice / periodDays);
    final introPct = quote?.introDiscountPercent;
    final String? introBadge = widget.isCurrentPlan
        ? 'CURRENT PLAN'
        : intro == null
            ? null
            : intro.isFreeTrial
                ? 'FREE TRIAL'
                : introPct != null
                    ? '$introPct% OFF'
                    : 'INTRO OFFER';

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
                          if (introBadge != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: _Badge(label: introBadge),
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
                            if (intro != null && !intro.isFreeTrial) ...[
                              Text(
                                priceText,
                                style: AppTypography.bodySm.copyWith(
                                    decoration: TextDecoration.lineThrough),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              intro == null || intro.isFreeTrial
                                  ? priceText
                                  : intro.displayPrice,
                              style: AppTypography.headlineSm.copyWith(
                                  fontSize: 18,
                                  color: intro != null
                                      ? AppColors.accent
                                      : AppColors.highEmphasis),
                            ),
                            if (intro == null || intro.isPerPeriod)
                              Text(cadence,
                                  style: AppTypography.labelSm.copyWith(
                                      color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                        Text(
                          intro != null
                              ? 'then $priceText$cadence'
                              : '≈ $perDayText/day',
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
            child:
                Icon(Icons.check_rounded, size: 14, color: AppColors.onAccent),
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

/// The free tier shown as a muted line rather than a full plan row - on a
/// plain paywall it's a non-interactive baseline, not something to "buy", so
/// it shouldn't compete with the paid rows. When a paying user is managing
/// their plan it becomes selectable ([onTap] set), since picking it is how
/// they downgrade.
class _FreeRow extends StatelessWidget {
  final String name;
  final bool isCurrent;
  final bool selected;
  final VoidCallback? onTap;

  const _FreeRow({
    required this.name,
    this.isCurrent = true,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            if (onTap != null)
              _RadioDot(selected: selected)
            else
              Icon(Icons.circle_outlined,
                  size: 18,
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(name,
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.onSurfaceVariant)),
            ),
            if (isCurrent)
              Text('Current Plan',
                  style: AppTypography.labelSm.copyWith(
                      color:
                          AppColors.onSurfaceVariant.withValues(alpha: 0.7))),
          ],
        ),
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
  final bool isCurrent;
  final VoidCallback onPurchase;
  final VoidCallback onSkip;

  /// Set only when a paying user is managing their plan - opens the cancel
  /// flow, from the Free row's CTA or the "Cancel subscription" link.
  final VoidCallback? onCancelSubscription;

  const _PlansFooter({
    required this.controller,
    required this.entry,
    required this.isWelcomeOffer,
    required this.isWelcomeOfferFlow,
    required this.onPurchase,
    required this.onSkip,
    this.isCurrent = false,
    this.onCancelSubscription,
  });

  bool get _isFree =>
      entry.plan.monthlyPrice == 0 && entry.plan.yearlyPrice == 0;

  @override
  Widget build(BuildContext context) {
    final quote = controller.quoteFor(entry.plan);
    final intro = quote?.intro;
    final catalogPrice =
        controller.isYearly ? entry.plan.yearlyPrice : entry.plan.monthlyPrice;
    final priceText = quote?.price ?? _fallbackPrice(catalogPrice);
    final cadence = controller.isYearly ? 'year' : 'month';
    final mutedStyle = AppTypography.bodySm.copyWith(
        color: AppColors.onSurfaceVariant, fontSize: 11, height: 1.35);
    final linkStyle = AppTypography.bodySm.copyWith(
        fontSize: 11.5,
        color: AppColors.onSurfaceVariant,
        fontWeight: FontWeight.w500,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.onSurfaceVariant);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.marginMobile,
        AppSpacing.xs,
        AppSpacing.marginMobile,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: AppColors.surfaceContainerHigh, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryPillButton(
            label: _isFree
                ? 'Switch to ${entry.plan.name}'
                : isCurrent
                    ? 'Your current plan'
                    : intro != null
                        ? (intro.isFreeTrial
                            ? 'Start free trial of ${entry.plan.name}'
                            : 'Claim ${entry.plan.name} · ${intro.displayPrice}')
                        : onCancelSubscription != null
                            ? 'Switch to ${entry.plan.name} · $priceText/$cadence'
                            : 'Upgrade to ${entry.plan.name} · $priceText/$cadence',
            icon: isCurrent ? null : Icons.arrow_forward_rounded,
            isLoading: !_isFree && controller.isPurchasing,
            onPressed: _isFree
                ? onCancelSubscription
                : isCurrent
                    ? null
                    : onPurchase,
            height: 50,
          ),
          if (onCancelSubscription != null && !_isFree)
            TextButton(
              onPressed: onCancelSubscription,
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact),
              child: Text('Cancel subscription',
                  style: AppTypography.bodySm.copyWith(
                      fontSize: 14,
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w600)),
            ),
          if (isWelcomeOfferFlow)
            TextButton(
              onPressed: onSkip,
              // Full-size tap target and on-surface color: App Review rejects
              // paywalls whose free path is hard to find (3.1.2 / 5.6).
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact),
              child: Text('Continue with Free Plan',
                  style: AppTypography.bodySm.copyWith(
                      fontSize: 14,
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w600)),
            ),
          // Auto-renewal disclosure + Terms/Privacy links: App Review 3.1.2
          // requires both on the purchase screen itself.
          if (!_isFree)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${intro != null ? '${intro.summary}, then $priceText/$cadence. ' : ''}'
                'Auto-renews at $priceText/$cadence until cancelled. Cancel anytime '
                'in your $storeName settings at least 24 hours before the '
                'current period ends.',
                textAlign: TextAlign.center,
                style: mutedStyle,
              ),
            ),
          // App Review looks for Restore on the paywall itself, not just in
          // Settings (guideline 3.1.1).
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _FooterLink(
                label: 'Terms of Use',
                style: linkStyle,
                onPressed: () =>
                    openHostedPage(context, termsUrl, 'Terms of Use'),
              ),
              _FooterLink(
                label: 'Privacy Policy',
                style: linkStyle,
                onPressed: () =>
                    openHostedPage(context, privacyUrl, 'Privacy Policy'),
              ),
              _FooterLink(
                label: 'Restore purchases',
                style: linkStyle,
                onPressed: controller.isRestoring
                    ? null
                    : () => runRestorePurchases(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final TextStyle style;
  final VoidCallback? onPressed;

  const _FooterLink(
      {required this.label, required this.style, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact),
      child: Text(label, style: style),
    );
  }
}
