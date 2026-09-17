import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/bottom_nav_bar.dart';
import '../../core/widgets/progress_ring.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import '../diet_plans/diet_plan_controller.dart';
import 'meal_controller.dart';
import 'meal_models.dart';
import 'widgets/active_diet_plan_section.dart';
import 'widgets/macro_bar.dart';
import 'widgets/suggested_diet_plans_section.dart';

/// The Nutrition/Meal Planning screen - boxless: a calorie ring on the left
/// with its macro bars beside it on the right, a 7-day pill strip below that
/// connects up to the ring via a thin accent line, the active diet plan's
/// meals for the selected day, a "Suggested This Month" strip of diet plans
/// (with on-demand generation), and a quick-add FAB.
class MealPlanningScreen extends StatefulWidget {
  const MealPlanningScreen({super.key});

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
        // PageView, which now reaches all the way behind the real floating
        // nav pill (RootShell's `extendBody: true`). Reserve that same
        // footprint here too: `extendBody` so the meal list can actually
        // scroll under the pill (letting its transparency/blur show real
        // content), and an invisible bottomNavigationBar spacer so the FAB
        // still anchors just above the pill instead of sliding down behind
        // it.
        final navReserved = SilenBottomNavBar.reservedHeight(context);
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          floatingActionButton: _QuickAddFab(controller: _controller),
          bottomNavigationBar: SizedBox(height: navReserved),
          body: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.marginMobile,
                AppSpacing.lg,
                AppSpacing.marginMobile,
                AppSpacing.sm + navReserved),
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
                  builder: (context, day) =>
                      _MealDayContent(controller: _controller, day: day),
                ),
                const SizedBox(height: AppSpacing.xl),
                ActiveDietPlanSection(mealController: _controller),
                const SizedBox(height: AppSpacing.xl),
                const SuggestedDietPlansSection(),
                const SizedBox(height: 96), // clears the FAB
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
                            AppColors.accent.withOpacity(0),
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
      ],
    );
  }
}

/// Opens the quick-add bottom sheet, optionally pre-filled from a tapped
/// [MealSuggestion] - shared by the FAB and the suggestions strip so both
/// entry points land on the same editable form rather than logging silently.
Future<void> showQuickAddSheet(BuildContext context, MealController controller,
    {MealSuggestion? initial}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
    builder: (_) => _QuickAddSheet(controller: controller, initial: initial),
  );
}

/// The floating quick-add button - rotates 45 degrees into an "x" look while
/// its bottom sheet is open, then eases back on close.
class _QuickAddFab extends StatefulWidget {
  final MealController controller;

  const _QuickAddFab({required this.controller});

  @override
  State<_QuickAddFab> createState() => _QuickAddFabState();
}

class _QuickAddFabState extends State<_QuickAddFab> {
  bool _open = false;

  Future<void> _openSheet() async {
    setState(() => _open = true);
    await showQuickAddSheet(context, widget.controller);
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: _openSheet,
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

class _QuickAddSheet extends StatefulWidget {
  final MealController controller;
  final MealSuggestion? initial;

  const _QuickAddSheet({required this.controller, this.initial});

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  late String _mealType;
  late final _titleController =
      TextEditingController(text: widget.initial?.title ?? '');
  late final _caloriesController = TextEditingController(
      text: widget.initial != null ? '${widget.initial!.caloriesKcal}' : '');
  late final _proteinController = TextEditingController(
      text: widget.initial != null ? '${widget.initial!.proteinG}' : '');
  late final _carbsController = TextEditingController(
      text: widget.initial != null ? '${widget.initial!.carbsG}' : '');
  late final _fatsController = TextEditingController(
      text: widget.initial != null ? '${widget.initial!.fatsG}' : '');
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _mealType =
        widget.initial != null && kMealTypes.contains(widget.initial!.mealType)
            ? widget.initial!.mealType
            : kMealTypes.first;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty || _submitting) return;
    setState(() => _submitting = true);
    final ok = await widget.controller.addMeal(
      mealType: _mealType,
      title: _titleController.text.trim(),
      caloriesKcal: int.tryParse(_caloriesController.text) ?? 0,
      proteinG: int.tryParse(_proteinController.text) ?? 0,
      carbsG: int.tryParse(_carbsController.text) ?? 0,
      fatsG: int.tryParse(_fatsController.text) ?? 0,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.marginMobile,
        right: AppSpacing.marginMobile,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Log a meal', style: AppTypography.headlineSm),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (final type in kMealTypes)
                  PillChip(
                    label: type,
                    selected: type == _mealType,
                    onTap: () => setState(() => _mealType = type),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _titleController,
              style: AppTypography.bodyMd,
              decoration: const InputDecoration(hintText: 'What did you eat?'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                    child: _NumberField(
                        controller: _caloriesController, hint: 'Kcal')),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                    child: _NumberField(
                        controller: _proteinController, hint: 'Protein g')),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                    child: _NumberField(
                        controller: _carbsController, hint: 'Carbs g')),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                    child: _NumberField(
                        controller: _fatsController, hint: 'Fats g')),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryPillButton(
              label: 'Log Meal',
              isLoading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _NumberField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: AppTypography.bodyMd,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: hint),
    );
  }
}
