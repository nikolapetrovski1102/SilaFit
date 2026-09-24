import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/bottom_nav_bar.dart';
import '../../core/widgets/progress_ring.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../diet_plans/diet_plan_controller.dart';
import '../diet_plans/widgets/locked_diet_plans.dart';
import 'meal_controller.dart';
import 'meal_models.dart';
import 'meal_tracker_screen.dart';
import 'widgets/active_diet_plan_section.dart';
import 'widgets/macro_bar.dart';
import 'widgets/meal_log_card.dart';
import 'widgets/suggested_diet_plans_section.dart';

/// The Nutrition/Meal Planning screen - boxless: a calorie ring on the left
/// with its macro bars beside it on the right, a 7-day pill strip below that
/// connects up to the ring via a thin accent line, the active diet plan's
/// meals for the selected day, a "Log a meal" entry into the food-by-food
/// meal tracker plus the day's meals, and the diet-plan sections (Pro - a
/// locked preview on Free).
class MealPlanningScreen extends StatefulWidget {
  final GlobalKey? spotlightKey;

  const MealPlanningScreen({super.key, this.spotlightKey});

  @override
  State<MealPlanningScreen> createState() => _MealPlanningScreenState();
}

class _MealPlanningScreenState extends State<MealPlanningScreen> {
  late final MealController _controller;

  @override
  void initState() {
    super.initState();
    _controller = context.read<MealController>();
    // App-wide controllers: the "Suggested This Month" strip and the active
    // plan section both need their own first load, independent of the meal day.
    final dietPlansController = context.read<DietPlansController>();
    final activePlanController = context.read<ActiveDietPlanController>();
    Future.microtask(() {
      _controller.load();
      dietPlansController.load();
      activePlanController.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // This screen's own Scaffold is nested inside RootShell's tab
        // PageView, which reaches all the way behind the floating nav pill
        // (RootShell's `extendBody: true`). Reserve that same footprint:
        // `extendBody` so the meals scroll under the pill, and an invisible
        // bottomNavigationBar spacer so the "log a meal" FAB anchors just
        // above the pill instead of sliding down behind it.
        final navReserved = SilenBottomNavBar.reservedHeight(context);
        final dietPlans = context.watch<DietPlansController>();
        final activePlan = context.watch<ActiveDietPlanController>();
        final hasActivePlan = activePlan.state.data?.plan != null;
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          floatingActionButton: _LogMealFab(controller: _controller),
          bottomNavigationBar: SizedBox(height: navReserved),
          body: SingleChildScrollView(
            // Extra room at the end so the last meal can scroll clear of
            // the FAB.
            padding: EdgeInsets.fromLTRB(
                AppSpacing.marginMobile,
                AppSpacing.lg,
                AppSpacing.marginMobile,
                AppSpacing.sm + navReserved + 72),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionEyebrow('Fuel & Macros', color: AppColors.accent),
                const SizedBox(height: 4),
                Text('Nutrition', style: AppTypography.headlineLg),
                const SizedBox(height: AppSpacing.lg),
                ResourceBuilder<MealDay>(
                  state: _controller.state,
                  onRetry: _controller.load,
                  builder: (context, day) {
                    final content =
                        _MealDayContent(controller: _controller, day: day);
                    if (widget.spotlightKey != null) {
                      return KeyedSubtree(
                          key: widget.spotlightKey!, child: content);
                    }
                    return content;
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
                // Free accounts keep following a plan they already had, but
                // browsing/creating plans is Pro - show the locked preview.
                if (dietPlans.requiresUpgrade && !hasActivePlan) ...[
                  const SectionEyebrow('Diet Plans · Pro'),
                  const SizedBox(height: AppSpacing.sm),
                  LockedDietPlans(onReturn: () {
                    if (!mounted) return;
                    dietPlans.load(force: true);
                    activePlan.load(force: true);
                  }),
                ] else ...[
                  ActiveDietPlanSection(mealController: _controller),
                  if (!dietPlans.requiresUpgrade) ...[
                    const SizedBox(height: AppSpacing.xl),
                    const SuggestedDietPlansSection(),
                  ],
                ],
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The 7-day strip, now living *below* the calorie ring/macro row: the
/// selected pill grows a thin accent line up out of its own top edge (via
/// [_DayPill]'s reserved connector slot) so the strip visually reads as
/// "plugged into" the totals above it, rather than a disconnected picker.
///
/// Fixed-width pills with a real gap between them (rather than 7 pills
/// dividing up whatever width the screen happens to have, which squeezed
/// them thin and left barely any breathing room) - on a narrow phone the
/// full week can run a little wider than the screen, so this scrolls
/// horizontally instead of shrinking the pills to force-fit.
class _DayStrip extends StatelessWidget {
  final MealController controller;

  const _DayStrip({required this.controller});

  static const _pillGap = 10.0;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = today.subtract(const Duration(days: 3));
    final days = List.generate(7, (i) => start.add(Duration(days: i)));

    return SizedBox(
      height: _DayPill.connectorHeight + _DayPill.pillHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(
          children: [
            for (var i = 0; i < days.length; i++) ...[
              if (i > 0) const SizedBox(width: _pillGap),
              _DayPill(
                date: days[i],
                selected: _isSameDate(days[i], controller.selectedDate),
                isToday: _isSameDate(days[i], today),
                onTap: () => controller.selectDate(days[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayPill extends StatelessWidget {
  final DateTime date;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  const _DayPill({
    required this.date,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  /// Reserved space above the pill for the connector line - always present
  /// (even unselected, as an empty slot) so every pill in the row sits at
  /// the same height and only the selected one's line pops into it.
  static const connectorHeight = 18.0;
  static const pillHeight = 68.0;
  // Matches the Home day strip's own oval width - now that this pill sizes
  // itself (rather than stretching to fill an `Expanded` slot), it should
  // read as the same "day oval" shape used elsewhere, not a narrower one.
  static const pillWidth = 56.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: connectorHeight,
            child: selected
                ? Center(
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        // Fades out going *up* - toward the calorie ring/macro
                        // row this pill's totals belong to - the same visual
                        // language as the Home day strip's hanging connector,
                        // just flipped since this strip sits below its totals
                        // instead of above them.
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            AppColors.accent,
                            AppColors.accent.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: pillWidth,
            height: pillHeight,
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('E').format(date).substring(0, 1).toUpperCase(),
                  style: AppTypography.labelCaps.copyWith(
                      color: selected
                          ? AppColors.onAccent
                          : AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  '${date.day}',
                  style: AppTypography.headlineSm.copyWith(
                    color: selected ? AppColors.onAccent : AppColors.onSurface,
                    fontSize: 16,
                  ),
                ),
                if (isToday && !selected)
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.accent, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MealDayContent extends StatelessWidget {
  final MealController controller;
  final MealDay day;

  const _MealDayContent({required this.controller, required this.day});

  @override
  Widget build(BuildContext context) {
    final ratio = day.targets.targetCalories <= 0
        ? 0.0
        : (day.consumedCalories / day.targets.targetCalories).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Flat, no card - the ring anchors the left, its macro breakdown
        // sits directly beside it on the right, both straight on the
        // screen's own background.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            RadialProgressRing(
              progress: ratio,
              size: 128,
              strokeWidth: 11,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${day.remainingCalories}',
                      style: AppTypography.displayStatMobile
                          .copyWith(fontSize: 28)),
                  Text('KCAL LEFT', style: AppTypography.labelCaps),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${day.consumedCalories} / ${day.targets.targetCalories} kcal',
                    style: AppTypography.labelSm
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  MacroBar(
                    label: 'Protein',
                    consumedG: day.consumedProteinG,
                    targetG: day.targets.targetProteinG,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  MacroBar(
                    label: 'Carbs',
                    consumedG: day.consumedCarbsG,
                    targetG: day.targets.targetCarbsG,
                    color: AppColors.tertiaryContainer,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  MacroBar(
                    label: 'Fats',
                    consumedG: day.consumedFatsG,
                    targetG: day.targets.targetFatsG,
                    color: AppColors.secondary,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _DayStrip(controller: controller),
        const SizedBox(height: AppSpacing.xl),
        _DayMeals(controller: controller, day: day),
      ],
    );
  }
}

/// The sticky bottom-right "+" - opens the meal tracker for a new meal. The
/// plus turns into an x while the tracker is up, so the hand-off reads as
/// one gesture.
class _LogMealFab extends StatefulWidget {
  final MealController controller;

  const _LogMealFab({required this.controller});

  @override
  State<_LogMealFab> createState() => _LogMealFabState();
}

class _LogMealFabState extends State<_LogMealFab> {
  bool _open = false;

  Future<void> _openTracker() async {
    HapticFeedback.lightImpact();
    setState(() => _open = true);
    await openMealTracker(context, widget.controller);
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: _openTracker,
      tooltip: 'Log a meal',
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.onAccent,
      elevation: 0,
      shape: const CircleBorder(),
      child: AnimatedRotation(
        turns: _open ? 0.125 : 0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }
}

/// Pushes the full-screen meal tracker - a new meal, or [existing] to edit.
Future<void> openMealTracker(BuildContext context, MealController controller,
    {MealLog? existing}) {
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) =>
        MealTrackerScreen(controller: controller, existing: existing),
  ));
}

/// The selected day's meals. Planned meals from an active diet plan are
/// already listed (and logged) in that plan's section, so they're left out
/// here while one is active.
class _DayMeals extends StatelessWidget {
  final MealController controller;
  final MealDay day;

  const _DayMeals({required this.controller, required this.day});

  @override
  Widget build(BuildContext context) {
    final hasActivePlan =
        context.watch<ActiveDietPlanController>().state.data?.plan != null;
    final meals = [
      for (final meal in day.meals)
        if (meal.isLogged || !hasActivePlan) meal,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: SectionEyebrow('Meals')),
            if (meals.isNotEmpty)
              Text('${meals.where((m) => m.isLogged).length} logged',
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (meals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(
                'Nothing logged yet. Tap + to build a meal food by food - its '
                'macros count toward this day.',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant)),
          )
        else
          for (final meal in meals)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: MealLogCard(
                key: ValueKey(meal.mealLogId),
                meal: meal,
                onOpen: () =>
                    openMealTracker(context, controller, existing: meal),
                onLog: () => controller.logMeal(meal),
                onDelete: () => controller.deleteMeal(meal.mealLogId),
              ),
            ),
      ],
    );
  }
}
