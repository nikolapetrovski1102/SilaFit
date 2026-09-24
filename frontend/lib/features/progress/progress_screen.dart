import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/bottom_nav_bar.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/upgrade_lock_card.dart';
import '../plans/plans_controller.dart';
import '../plans/plans_screen.dart';
import '../settings/ai_consent_gate.dart';
import 'all_personal_records_screen.dart';
import 'analytics_controller.dart';
import 'analytics_models.dart';
import 'exercise_progress_controller.dart';
import 'monthly_overview_screen.dart';
import 'progress_controller.dart';
import 'progress_models.dart';
import 'weekly_analytics_controller.dart';
import 'widgets/exercise_progress_card.dart';
import 'widgets/personal_record_tile.dart';

/// The AI-narrated progress screen. Registered-tier only - the caller
/// (RootShell) runs it through AccountGate before this ever mounts - and a
/// PRO/Advanced feature: a Free account sees the whole screen blurred behind
/// an upgrade prompt. Entitlement comes from [ExerciseProgressController]
/// (a 403 on the gated per-exercise endpoints), not a client-side plan read.
class ProgressScreen extends StatefulWidget {
  final GlobalKey? spotlightKey;

  const ProgressScreen({super.key, this.spotlightKey});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late final ProgressController _controller;
  late final ExerciseProgressController _exerciseController;
  int? _purchaseRevision;

  @override
  void initState() {
    super.initState();
    _controller = context.read<ProgressController>();
    _exerciseController = context.read<ExerciseProgressController>();
    // Deferred - see the matching comment in today_screen.dart: load()'s
    // first notifyListeners() must not fire synchronously mid-build.
    Future.microtask(_controller.load);
    Future.microtask(_exerciseController.load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A purchase or restore anywhere in the app can flip entitlement - re-ask
    // the server rather than leave the screen locked until a restart.
    final revision = context.watch<PlansController>().purchaseRevision;
    if (_purchaseRevision != null && _purchaseRevision != revision) {
      Future.microtask(() => _exerciseController.load(force: true));
    }
    _purchaseRevision = revision;
  }

  Future<void> _openPlans() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PlansScreen()));
    if (mounted) await _exerciseController.load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _exerciseController]),
      builder: (context, _) {
        final access = _exerciseController.access;
        // Stay blurred while the very first entitlement check is in flight
        // so a Free account never gets a flash of the unlocked screen. A
        // failed check (network, 5xx) un-blurs instead - the exercise card
        // shows its own retry, and the rest of the screen isn't gated
        // server-side anyway.
        final blurred = access == ExerciseProgressAccess.locked ||
            (access == ExerciseProgressAccess.unknown &&
                _exerciseController.exercisesState.isLoading);
        return Stack(
          children: [
            ImageFiltered(
              enabled: blurred,
              imageFilter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
              child: IgnorePointer(
                ignoring: blurred,
                child: _buildScrollView(context),
              ),
            ),
            // Hidden during the feature tour so it can't sit over the
            // spotlighted card - the blur alone still shows it's locked.
            if (blurred && widget.spotlightKey == null)
              Positioned.fill(
                child: _ProgressLockOverlay(
                  checking: access == ExerciseProgressAccess.unknown,
                  onUnlock: _openPlans,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildScrollView(BuildContext context) {
    return SingleChildScrollView(
          // Bottom padding clears the floating nav pill (now that
          // RootShell's Scaffold extends its body under it) plus the
          // usual breathing room, so the last card scrolls up past the
          // pill instead of staying hidden beneath it.
          padding: EdgeInsets.fromLTRB(
              AppSpacing.marginMobile,
              AppSpacing.lg,
              AppSpacing.marginMobile,
              AppSpacing.sm + SilenBottomNavBar.reservedHeight(context)),
          // Header, timeframe pills, and the PR / AI review entry
          // points don't need `overview` - only `_YourInsightCard`
          // does. Gating all of that behind one ResourceBuilder used to
          // blank the whole screen (title included) whenever the overview
          // call alone was slow or failed; now a stalled/errored overview
          // only empties its own card.
          child: _ProgressContent(
            controller: _controller,
            exerciseController: _exerciseController,
            spotlightKey: widget.spotlightKey,
          ),
        );
  }
}

/// Sits over the blurred Progress screen for a Free account.
class _ProgressLockOverlay extends StatelessWidget {
  final bool checking;
  final VoidCallback onUnlock;

  const _ProgressLockOverlay({required this.checking, required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background.withValues(alpha: 0.35),
      child: Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              AppSpacing.marginMobile,
              AppSpacing.lg,
              AppSpacing.marginMobile,
              SilenBottomNavBar.reservedHeight(context)),
          child: checking
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppColors.accent),
                )
              : UpgradeLockCard(
                  title: 'Track every lift',
                  message: 'See your estimated 1RM, top sets and volume for '
                      'each exercise over time, plus AI reviews.',
                  actionLabel: 'Unlock Progress',
                  onUnlock: onUnlock,
                ),
        ),
      ),
    );
  }
}

class _ProgressContent extends StatelessWidget {
  final ProgressController controller;
  final ExerciseProgressController exerciseController;
  final GlobalKey? spotlightKey;

  const _ProgressContent({
    required this.controller,
    required this.exerciseController,
    this.spotlightKey,
  });

  static const _timeframes = [
    (30, '1M'),
    (90, '3M'),
    (180, '6M'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionEyebrow('Performance', color: AppColors.accent),
        const SizedBox(height: 4),
        Text('Your progress', style: AppTypography.headlineLg),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            for (final (days, label) in _timeframes) ...[
              PillChip(
                label: label,
                selected: controller.days == days,
                onTap: () {
                  controller.setDays(days);
                  exerciseController.setDays(days);
                },
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (spotlightKey != null)
          KeyedSubtree(
            key: spotlightKey!,
            child: ExerciseProgressCard(controller: exerciseController),
          )
        else
          ExerciseProgressCard(controller: exerciseController),
        const SizedBox(height: AppSpacing.lg),
        // Only the insight card depends on `controller.state` (the overview
        // call) - scoping the ResourceBuilder to just it means a slow or
        // failed overview fetch no longer blanks the header/pills above or
        // the PR / AI review entry points below.
        ResourceBuilder<ProgressOverview>(
          state: controller.state,
          onRetry: controller.load,
          builder: (context, overview) => _YourInsightCard(
              insight: overview.insights.isNotEmpty
                  ? overview.insights.first
                  : null),
        ),
        const SizedBox(height: AppSpacing.lg),
        _PersonalRecordsCard(controller: controller),
        const SizedBox(height: AppSpacing.lg),
        const _AiMonthlyReviewSection(),
        const SizedBox(height: AppSpacing.lg),
        const _AiWeeklyReviewSection(),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// Real per-exercise Personal Records - the heaviest set ever logged for
/// each exercise (see `usp_WorkoutSession_GetPersonalRecords`), sourced from
/// [ProgressController.prsState] rather than mock data. That state loads
/// independently of the overview (see the controller), so this card has its
/// own loading/error/empty rendering instead of gating on the page's
/// [ResourceBuilder].
///
/// The card itself only ever holds a top-3 preview (`prsState` is fetched
/// with `top: 3`); tapping it opens [AllPersonalRecordsScreen], which fetches
/// the full per-exercise list on its own.
class _PersonalRecordsCard extends StatelessWidget {
  final ProgressController controller;

  const _PersonalRecordsCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final state = controller.prsState;
    final hasRecords = state.data != null && state.data!.isNotEmpty;

    return GestureDetector(
      onTap: hasRecords
          ? () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AllPersonalRecordsScreen()))
          : null,
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: SectionEyebrow('Personal Records')),
                if (hasRecords)
                  Icon(Icons.arrow_forward_rounded,
                      size: 16, color: AppColors.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (state.isLoading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.accent),
                  ),
                ),
              )
            else if (state.error != null)
              Text(state.error!, style: AppTypography.bodySm)
            else if (!hasRecords)
              Text('Log a set during a workout to start tracking PRs.',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant))
            else
              for (final record in state.data!)
                PersonalRecordTile(record: record),
          ],
        ),
      ),
    );
  }
}

class _YourInsightCard extends StatelessWidget {
  final String? insight;

  const _YourInsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      background: AppColors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionEyebrow('Your Insight', color: AppColors.accent),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '"${insight ?? 'Log a few more sessions to unlock your first insight.'}"',
            style: AppTypography.bodyLg.copyWith(
                color: AppColors.onSurface, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

/// Keeps the generated report out of the analytics dashboard. The report is
/// fetched only after this entry point is tapped, then rendered exclusively by
/// [MonthlyOverviewScreen].
class _AiMonthlyReviewSection extends StatelessWidget {
  const _AiMonthlyReviewSection();

  @override
  Widget build(BuildContext context) => const _AiReviewEntry(
        title: 'AI Monthly Review',
        description: 'Open your monthly overview',
        tier: 'PRO',
        weekly: false,
      );
}

/// Advanced-only weekly review entry point. As with the monthly entry, no
/// generated content is displayed or requested until the overview is opened.
class _AiWeeklyReviewSection extends StatelessWidget {
  const _AiWeeklyReviewSection();

  @override
  Widget build(BuildContext context) => const _AiReviewEntry(
        title: 'AI Weekly Review',
        description: 'Open your weekly overview',
        tier: 'ADVANCED',
        weekly: true,
      );
}

class _AiReviewEntry extends StatefulWidget {
  final String title;
  final String description;
  final String tier;
  final bool weekly;

  const _AiReviewEntry({
    required this.title,
    required this.description,
    required this.tier,
    required this.weekly,
  });

  @override
  State<_AiReviewEntry> createState() => _AiReviewEntryState();
}

class _AiReviewEntryState extends State<_AiReviewEntry> {
  bool _loading = false;

  Future<void> _open() async {
    if (_loading) return;
    if (!await AiConsentGate.ensure(context) || !mounted) return;
    setState(() => _loading = true);

    AnalyticsRecap? report;
    bool requiresUpgrade;
    String? error;
    if (widget.weekly) {
      final controller = context.read<WeeklyAnalyticsController>();
      await controller.load(force: true);
      report = controller.state.data;
      requiresUpgrade = controller.requiresUpgrade;
      error = controller.state.error;
    } else {
      final controller = context.read<AnalyticsController>();
      await controller.load(force: true);
      report = controller.state.data;
      requiresUpgrade = controller.requiresUpgrade;
      error = controller.state.error;
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (requiresUpgrade) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const PlansScreen()));
      return;
    }

    if (report != null) {
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) => MonthlyOverviewScreen(
          analytics: report!,
          onDone: () => Navigator.of(routeContext).pop(),
        ),
      ));
      return;
    }

    final message = error?.trim().isNotEmpty == true
        ? error!
        : 'Your review is not available yet.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _loading ? null : _open,
      child: SectionCard(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(Icons.auto_awesome_rounded,
                  color: AppColors.secondary, size: 20),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: AppTypography.labelSm
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(widget.description,
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(widget.tier,
                  style: AppTypography.labelCaps
                      .copyWith(color: AppColors.onAccent, fontSize: 9)),
            ),
            const SizedBox(width: AppSpacing.xs),
            if (_loading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.secondary),
              )
            else
              Icon(Icons.arrow_forward_rounded,
                  size: 18, color: AppColors.secondary),
          ],
        ),
      ),
    );
  }
}
