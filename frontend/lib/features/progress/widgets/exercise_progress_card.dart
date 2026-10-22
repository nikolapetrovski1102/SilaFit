import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/state/resource_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/container_transform.dart';
import '../../../core/widgets/hero_container_transform.dart';
import '../../../core/widgets/silen_button.dart';
import '../../../core/widgets/section_eyebrow.dart';
import '../../../core/widgets/silen_ambient_backdrop.dart';
import '../../../core/widgets/skeleton.dart';
import '../../onboarding/widgets/age_wheel_picker.dart';
import '../exercise_progress_controller.dart';
import '../progress_models.dart';
import '../weight_display.dart';

/// Hairline used in place of card edges - the tracker sits straight on the
/// screen's ambient backdrop, so separation comes from type and spacing.
Color get _hairline => AppColors.onSurface.withValues(alpha: 0.06);

const _motion = Duration(milliseconds: 260);

/// PRO/Advanced per-exercise tracker: pick any exercise that has logged sets,
/// then chart one metric per session over the section's own timeframe.
///
/// Deliberately not a [SectionCard]: it blends into the backdrop as the
/// screen's hero section, with a large exercise title that morphs into a
/// search screen, and a borderless chart running edge to edge.
///
/// When [controller] reports [ExerciseProgressAccess.locked] the section
/// renders [_Sample] instead - the gated endpoints return nothing for a Free
/// caller, and the Progress screen blurs it anyway, so this only has to look
/// plausible behind the blur.
class ExerciseProgressCard extends StatelessWidget {
  final ExerciseProgressController controller;

  const ExerciseProgressCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final locked = controller.access == ExerciseProgressAccess.locked;
    final exercisesState = locked
        ? ResourceState.data(_Sample.exercises)
        : controller.exercisesState;
    final progressState = locked
        ? ResourceState.data(_Sample.progress)
        : controller.progressState;
    final selectedId = locked
        ? _Sample.exercises.first.exerciseId
        : controller.selectedExerciseId;
    final hasExercises =
        exercisesState.data != null && exercisesState.data!.isNotEmpty;
    final isPerDumbbell = exercisesState.data
            ?.any((e) => e.exerciseId == selectedId && e.isPerDumbbell) ??
        false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SectionEyebrow('Exercise Progress',
                    color: AppColors.accent),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: _TierBadge(),
              ),
              const Spacer(),
              if (hasExercises)
                _TimeframeValue(
                  amount: controller.timeframeAmount,
                  unit: controller.timeframeUnit,
                  onChanged: locked ? null : controller.setTimeframe,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (exercisesState.isLoading)
            const SkeletonChart()
          else if (exercisesState.error != null)
            _RetryMessage(
                message: exercisesState.error!,
                onRetry: () => controller.load(force: true))
          else if (!hasExercises)
            Text('Log sets during a workout to track each exercise over time.',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant))
          else ...[
            _ExerciseSelector(
              exercises: exercisesState.data!,
              selectedId: selectedId,
              onSelected: locked ? null : controller.select,
            ),
            const SizedBox(height: AppSpacing.lg),
            AnimatedSwitcher(
              duration: _motion,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: KeyedSubtree(
                key: ValueKey(progressState.isLoading
                    ? 'loading'
                    : progressState.error != null
                        ? 'error'
                        : 'data'),
                child: progressState.isLoading
                    ? const SkeletonChart()
                    : progressState.error != null
                        ? _RetryMessage(
                            message: progressState.error!,
                            onRetry: controller.retryProgress)
                        : _ProgressBody(
                            progress: progressState.data!,
                            metric: controller.metric,
                            onMetricChanged: controller.setMetric,
                            isPerDumbbell: isPerDumbbell,
                          ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TierBadge extends StatelessWidget {
  const _TierBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(
            color: AppColors.secondary.withValues(alpha: 0.55), width: 1),
      ),
      child: Text('PRO',
          style: AppTypography.labelCaps
              .copyWith(color: AppColors.secondary, fontSize: 9)),
    );
  }
}

const _amountHeroTag = 'exercise-progress-timeframe-amount';
const _unitHeroTag = 'exercise-progress-timeframe-unit';

/// "Last 3 M" as one big number plus its unit. Tapping either grows both,
/// each as its own shared element, into the matching wheel's selection pill
/// on [_TimeframePickerScreen].
class _TimeframeValue extends StatelessWidget {
  final int amount;
  final ProgressTimeframeUnit unit;

  /// Null while locked - the value renders but doesn't open.
  final void Function(int amount, ProgressTimeframeUnit unit)? onChanged;

  const _TimeframeValue({
    required this.amount,
    required this.unit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null
          ? null
          : () => Navigator.of(context).push(heroExpandRoute<void>(
                builder: (_) => _TimeframePickerScreen(
                  amount: amount,
                  unit: unit,
                  onChanged: onChanged,
                ),
              )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('LAST', style: AppTypography.labelCaps.copyWith(fontSize: 10)),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _timeframeHero(
                _amountHeroTag,
                _TimeframeSlot(
                  label: '$amount',
                  style: AppTypography.displayStat.copyWith(height: 1),
                ),
              ),
              const SizedBox(width: 4),
              _timeframeHero(
                _unitHeroTag,
                _TimeframeSlot(
                  label: unit.short,
                  style: AppTypography.headlineLg
                      .copyWith(color: AppColors.accent, height: 1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _timeframeHero(String tag, _TimeframeSlot slot) => Hero(
      tag: tag,
      createRectTween: straightHeroRectTween,
      flightShuttleBuilder: _timeframeShuttle,
      child: slot,
    );

/// One end of a timeframe flight: the section's plain number/unit (no
/// [pill]), or the wheel's selection pill, whose [label] and [style] mirror
/// the wheel's centered value so the flight can carry the label itself.
class _TimeframeSlot extends StatelessWidget {
  final String label;
  final TextStyle style;
  final Widget? pill;

  const _TimeframeSlot({required this.label, required this.style, this.pill});

  // The wheel draws the label on the pill side - this only shows it.
  @override
  Widget build(BuildContext context) =>
      pill ?? Text(label, maxLines: 1, softWrap: false, style: style);
}

/// Flies the section's number/unit into the wheel's accent pill (and back):
/// the label morphs its size, weight and color into the wheel's centered
/// label while the pill grows in behind it, so the value itself travels
/// rather than fading out at one end and in at the other.
///
/// Progress is read off the flight box's live height rather than
/// [animation]: Hero eases the box with its own curve, flipped on pop, so a
/// separately-curved label ran ahead of or behind the box - on the way back
/// it was still pill-sized in a box already shrunk to the unit, and got
/// squeezed. Measured this way, label and box always land together.
Widget _timeframeShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final push = direction == HeroFlightDirection.push;
  final picker = ((push ? toHeroContext : fromHeroContext).widget as Hero).child
      as _TimeframeSlot;
  final section = ((push ? fromHeroContext : toHeroContext).widget as Hero)
      .child as _TimeframeSlot;

  double? heightOf(BuildContext context) {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.height : null;
  }

  final sectionHeight = heightOf(push ? fromHeroContext : toHeroContext);
  final pickerHeight = heightOf(push ? toHeroContext : fromHeroContext);

  // 0 at the section's slot, 1 at the wheel's pill.
  double progress(double boxHeight) {
    if (sectionHeight == null ||
        pickerHeight == null ||
        (pickerHeight - sectionHeight).abs() < 1) {
      return animation.value;
    }
    return ((boxHeight - sectionHeight) / (pickerHeight - sectionHeight))
        .clamp(0.0, 1.0);
  }

  Widget label(String text, TextStyle style) => Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(text, maxLines: 1, softWrap: false, style: style),
        ),
      );

  return Material(
    type: MaterialType.transparency,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final t = progress(constraints.maxHeight);
        // The pill lands a touch ahead of the label so the label's color
        // turns onAccent against an already-solid accent fill.
        final pillT = Curves.easeOut.transform((t / 0.75).clamp(0.0, 1.0));
        final style = TextStyle.lerp(section.style, picker.style, t)!;
        // Usually equal - they only differ if the value changed while the
        // section hadn't rebuilt yet, so crossfade rather than hard-swap.
        final same = section.label == picker.label;
        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: pillT,
              child: Transform.scale(
                scale: 0.85 + 0.15 * pillT,
                child: picker.pill,
              ),
            ),
            if (same)
              label(picker.label, style)
            else ...[
              Opacity(opacity: 1 - t, child: label(section.label, style)),
              Opacity(opacity: t, child: label(picker.label, style)),
            ],
          ],
        );
      },
    ),
  );
}

/// Picks the tracker's timeframe with the onboarding age wheel, twice: one
/// wheel for the amount, one for the unit. Applied when the screen closes,
/// however it closes, so the chart refetches once rather than per tick.
class _TimeframePickerScreen extends StatefulWidget {
  final int amount;
  final ProgressTimeframeUnit unit;
  final void Function(int amount, ProgressTimeframeUnit unit) onChanged;

  const _TimeframePickerScreen({
    required this.amount,
    required this.unit,
    required this.onChanged,
  });

  @override
  State<_TimeframePickerScreen> createState() => _TimeframePickerScreenState();
}

class _TimeframePickerScreenState extends State<_TimeframePickerScreen> {
  late int _amount = widget.amount;
  late ProgressTimeframeUnit _unit = widget.unit;

  /// The route's open/close animation - while it runs, the hero flights
  /// draw the selected labels, so the wheels hide theirs.
  Animation<double>? _routeAnimation;
  bool _inFlight = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation == _routeAnimation) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = animation?..addStatusListener(_onRouteStatus);
    _inFlight = _isInFlight(animation?.status);
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }

  static bool _isInFlight(AnimationStatus? status) =>
      status != null && status != AnimationStatus.completed;

  void _onRouteStatus(AnimationStatus status) {
    final inFlight = _isInFlight(status);
    if (inFlight != _inFlight) setState(() => _inFlight = inFlight);
  }

  void _setUnit(int index) {
    final unit = ProgressTimeframeUnit.values[index];
    setState(() {
      _unit = unit;
      _amount = _amount.clamp(1, unit.maxAmount);
    });
  }

  Widget _hero(String tag, String label, Widget pill) => _timeframeHero(
        tag,
        _TimeframeSlot(
          label: label,
          style: AgeWheelPicker.selectedLabelStyle,
          pill: pill,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.onChanged(_amount, _unit);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            const Positioned.fill(child: SilenAmbientBackdrop()),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                        AppSpacing.sm, AppSpacing.xs, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SectionEyebrow('Timeframe',
                                  color: AppColors.accent),
                              const SizedBox(height: 4),
                              Text('Show progress for',
                                  style: AppTypography.headlineLg),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: Icon(Icons.close_rounded,
                              color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: AgeWheelPicker(
                          value: _amount,
                          min: 1,
                          max: _unit.maxAmount,
                          onChanged: (v) => setState(() => _amount = v),
                          hideSelectedLabel: _inFlight,
                          selectionBuilder: (pill) =>
                              _hero(_amountHeroTag, '$_amount', pill),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: AgeWheelPicker(
                          value: _unit.index,
                          min: 0,
                          max: ProgressTimeframeUnit.values.length - 1,
                          labelBuilder: (i) =>
                              ProgressTimeframeUnit.values[i].short,
                          onChanged: _setUnit,
                          hideSelectedLabel: _inFlight,
                          selectionBuilder: (pill) =>
                              _hero(_unitHeroTag, _unit.short, pill),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  HeroExpandReveal(
                    child: AnimatedSwitcher(
                      duration: _motion,
                      child: Text(
                        'Last ${_unit.describe(_amount)}',
                        key: ValueKey((_amount, _unit)),
                        textAlign: TextAlign.center,
                        style: AppTypography.headlineSm,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                        0, AppSpacing.marginMobile, AppSpacing.md),
                    child: HeroExpandReveal(
                      child: PrimaryPillButton(
                        label: 'Done',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
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

/// The selected exercise as the section's title - tapping it morphs into
/// [_ExerciseSearchScreen], a quick filter over the tracked exercises.
class _ExerciseSelector extends StatelessWidget {
  final List<TrackedExercise> exercises;
  final String? selectedId;

  /// Null while locked - the title renders but doesn't open.
  final ValueChanged<String>? onSelected;

  const _ExerciseSelector({
    required this.exercises,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    TrackedExercise? selected;
    for (final e in exercises) {
      if (e.exerciseId == selectedId) selected = e;
    }
    final onSelected = this.onSelected;

    return ContainerTransform(
      radius: AppRadius.inset,
      // Transparent so the closed state is just type on the backdrop - the
      // morph still grows from this exact rect into the search screen.
      closedColor: Colors.transparent,
      openBuilder: (_) => _ExerciseSearchScreen(
        exercises: exercises,
        selectedId: selectedId,
        onSelected: onSelected ?? (_) {},
      ),
      closedBuilder: (context, open) => InkWell(
        onTap: onSelected == null ? null : open,
        borderRadius: BorderRadius.circular(AppRadius.inset),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Long names shrink to fit on one line rather than wrap
                  // or ellipsize - the full name always stays readable.
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: _motion,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previous, if (current != null) current],
                      ),
                      child: FittedBox(
                        key: ValueKey(selected?.exerciseId),
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          selected?.exerciseName ?? 'Choose an exercise',
                          maxLines: 1,
                          softWrap: false,
                          style: AppTypography.headlineLg,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withValues(alpha: 0.14),
                    ),
                    child: Icon(Icons.unfold_more_rounded,
                        size: 16, color: AppColors.accent),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${exercises.length} tracked '
                '${exercises.length == 1 ? 'exercise' : 'exercises'} · tap to search',
                style: AppTypography.bodySm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen destination of [_ExerciseSelector]'s container transform: a
/// search field over the already-loaded tracked exercises, filtered locally
/// as the user types - the list is the caller's own logged exercises, so
/// there's nothing to ask the server.
class _ExerciseSearchScreen extends StatefulWidget {
  final List<TrackedExercise> exercises;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const _ExerciseSearchScreen({
    required this.exercises,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  State<_ExerciseSearchScreen> createState() => _ExerciseSearchScreenState();
}

class _ExerciseSearchScreenState extends State<_ExerciseSearchScreen> {
  final _queryController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  List<TrackedExercise> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.exercises;
    return [
      for (final e in widget.exercises)
        if (e.exerciseName.toLowerCase().contains(query)) e,
    ];
  }

  void _select(TrackedExercise exercise) {
    widget.onSelected(exercise.exerciseId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: SilenAmbientBackdrop()),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.marginMobile, AppSpacing.sm, AppSpacing.xs, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionEyebrow('Exercise Progress',
                                color: AppColors.accent),
                            const SizedBox(height: 4),
                            Text('Track an exercise',
                                style: AppTypography.headlineLg),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(Icons.close_rounded,
                            color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.marginMobile),
                  child: TextField(
                    controller: _queryController,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    cursorColor: AppColors.accent,
                    style: AppTypography.bodyLg,
                    onChanged: (value) => setState(() => _query = value),
                    onSubmitted: (_) {
                      if (results.length == 1) _select(results.first);
                    },
                    decoration: InputDecoration(
                      hintText: 'Search your exercises',
                      fillColor: AppColors.onSurface.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        borderSide: BorderSide(
                            color: AppColors.accent.withValues(alpha: 0.5)),
                      ),
                      prefixIcon: Icon(Icons.search_rounded,
                          color: AppColors.onSurfaceVariant),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _queryController.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xl),
                          child: Text('No tracked exercise matches "$_query".',
                              textAlign: TextAlign.center,
                              style: AppTypography.bodyMd
                                  .copyWith(color: AppColors.onSurfaceVariant)),
                        )
                      : ListView.separated(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.only(
                              bottom: MediaQuery.paddingOf(context).bottom +
                                  AppSpacing.lg),
                          itemCount: results.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 1,
                              thickness: 1,
                              indent: AppSpacing.marginMobile,
                              endIndent: AppSpacing.marginMobile,
                              color: _hairline),
                          itemBuilder: (context, index) => _ExerciseResultRow(
                            exercise: results[index],
                            selected:
                                results[index].exerciseId == widget.selectedId,
                            onTap: () => _select(results[index]),
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

class _ExerciseResultRow extends StatelessWidget {
  final TrackedExercise exercise;
  final bool selected;
  final VoidCallback onTap;

  const _ExerciseResultRow({
    required this.exercise,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sessions = exercise.sessionCount;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.marginMobile, vertical: AppSpacing.md),
        child: Row(
          children: [
            // Accent rail marks the current pick without boxing the row.
            AnimatedContainer(
              duration: _motion,
              width: 3,
              height: 32,
              margin: const EdgeInsets.only(right: AppSpacing.sm),
              decoration: BoxDecoration(
                color: selected ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exercise.exerciseName,
                      style: AppTypography.headlineSm.copyWith(
                          fontSize: 16,
                          color: selected
                              ? AppColors.accent
                              : AppColors.highEmphasis)),
                  const SizedBox(height: 2),
                  Text(
                    '$sessions session${sessions == 1 ? '' : 's'} · last '
                    '${DateFormat('MMM d').format(exercise.lastTrainedAtUtc.toLocal())}',
                    style: AppTypography.bodySm,
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 20, color: AppColors.accent)
            else
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: AppColors.outline),
          ],
        ),
      ),
    );
  }
}

extension on ExerciseProgressMetric {
  String get label => switch (this) {
        ExerciseProgressMetric.estimatedOneRm => 'Est. 1RM',
        ExerciseProgressMetric.topSet => 'Top set',
        ExerciseProgressMetric.volume => 'Volume',
        ExerciseProgressMetric.reps => 'Reps',
      };

  bool get isWeight => this != ExerciseProgressMetric.reps;

  /// Top set and Est. 1RM come straight from one set's logged weight, so on
  /// a two-dumbbell exercise they are per hand; Volume already counts both.
  bool get isPerSet =>
      this == ExerciseProgressMetric.estimatedOneRm ||
      this == ExerciseProgressMetric.topSet;

  String unitFor(String weightUnit) => isWeight ? weightUnit : 'reps';

  double valueOf(ExerciseProgressPoint p) => switch (this) {
        ExerciseProgressMetric.estimatedOneRm => p.estimatedOneRmKg,
        ExerciseProgressMetric.topSet => p.topWeightKg,
        ExerciseProgressMetric.volume => p.totalVolumeKg,
        ExerciseProgressMetric.reps => p.totalReps.toDouble(),
      };
}

class _ProgressBody extends StatelessWidget {
  final ExerciseProgress progress;
  final ExerciseProgressMetric metric;
  final ValueChanged<ExerciseProgressMetric> onMetricChanged;
  final bool isPerDumbbell;

  const _ProgressBody({
    required this.progress,
    required this.metric,
    required this.onMetricChanged,
    required this.isPerDumbbell,
  });

  @override
  Widget build(BuildContext context) {
    final points = progress.points;
    if (points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text('No sessions for this exercise in the selected timeframe.',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.onSurfaceVariant)),
      );
    }

    // A bodyweight exercise logs 0 kg on every set - weight-based metrics
    // would just chart a flat zero, so only reps are offered for it.
    final weighted = points.any((p) => p.topWeightKg > 0);
    final metrics = weighted
        ? ExerciseProgressMetric.values
        : const [ExerciseProgressMetric.reps];
    final effective = metrics.contains(metric) ? metric : metrics.first;

    final weightUnit = weightUnitOf(context);
    final unit = effective.unitFor(weightUnit);
    final values = [
      for (final p in points)
        effective.isWeight
            ? toDisplayWeight(effective.valueOf(p), weightUnit)
            : effective.valueOf(p),
    ];
    final latest = values.last;
    final best = values.reduce((a, b) => a > b ? a : b);
    final first = values.first;
    final pct =
        values.length >= 2 && first > 0 ? (latest - first) / first * 100 : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricTabs(
          metrics: metrics,
          selected: effective,
          onChanged: onMetricChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _CountUpValue(value: latest),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(unit,
                  style: AppTypography.numericUnit
                      .copyWith(color: AppColors.onSurfaceVariant)),
            ),
            const Spacer(),
            if (pct != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _DeltaBadge(pct: pct),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Best ${formatDisplayWeight(best)} $unit · '
          '${points.length} session${points.length == 1 ? '' : 's'}'
          '${isPerDumbbell && effective.isPerSet ? perDumbbellSuffix : ''}',
          style: AppTypography.bodySm,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (points.length < 2)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(
                child: Text('Train it again to see your trend.',
                    style: AppTypography.bodySm)),
          )
        else
          SizedBox(
            height: 180,
            child: _MetricChart(points: points, values: values, unit: unit),
          ),
        const SizedBox(height: AppSpacing.xl),
        SectionEyebrow(isPerDumbbell
            ? 'Recent sessions$perDumbbellSuffix'
            : 'Recent sessions'),
        const SizedBox(height: AppSpacing.xs),
        for (final (i, p) in points.reversed.take(3).indexed) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: _hairline),
          _SessionRow(point: p, weightUnit: weightUnit),
        ],
      ],
    );
  }
}

/// Underlined text tabs - lighter than a row of outlined chips.
class _MetricTabs extends StatelessWidget {
  final List<ExerciseProgressMetric> metrics;
  final ExerciseProgressMetric selected;
  final ValueChanged<ExerciseProgressMetric> onChanged;

  const _MetricTabs({
    required this.metrics,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final m in metrics)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(m),
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: _motion,
                      style: AppTypography.labelSm.copyWith(
                        fontSize: 13,
                        fontWeight:
                            m == selected ? FontWeight.w600 : FontWeight.w500,
                        color: m == selected
                            ? AppColors.highEmphasis
                            : AppColors.onSurfaceVariant,
                      ),
                      child: Text(m.label),
                    ),
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: _motion,
                      curve: Curves.easeOutCubic,
                      height: 2,
                      width: m == selected ? 16 : 0,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The headline readout, counting from its previous value to the new one
/// when the metric, exercise or timeframe changes.
class _CountUpValue extends StatelessWidget {
  final double value;

  const _CountUpValue({required this.value});

  @override
  Widget build(BuildContext context) {
    final whole = value % 1 == 0;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        whole ? v.round().toString() : v.toStringAsFixed(1),
        style: AppTypography.displayStat,
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  final double pct;

  const _DeltaBadge({required this.pct});

  @override
  Widget build(BuildContext context) {
    final up = pct >= 0;
    final color = up ? AppColors.accent : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '${up ? '+' : ''}${pct.toStringAsFixed(1)}%',
            style: AppTypography.labelSm
                .copyWith(fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _MetricChart extends StatefulWidget {
  final List<ExerciseProgressPoint> points;
  final List<double> values;
  final String unit;

  const _MetricChart({
    required this.points,
    required this.values,
    required this.unit,
  });

  @override
  State<_MetricChart> createState() => _MetricChartState();
}

/// Press and hold, then drag across the chart to scrub between sessions. The
/// long-press recognizer claims the gesture before the surrounding scroll view
/// can, so a sideways drag reads the line instead of scrolling the page.
class _MetricChartState extends State<_MetricChart> {
  int? _selected;

  @override
  void didUpdateWidget(covariant _MetricChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selected != null && _selected! >= widget.values.length) {
      _selected = null;
    }
  }

  int _indexAt(double dx, double width) {
    final last = widget.values.length - 1;
    if (width <= 0 || last <= 0) return 0;
    return (dx / width * last).round().clamp(0, last);
  }

  void _select(int index) {
    if (index == _selected) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(
                duration: const Duration(milliseconds: 180)),
            (r) => r
              ..onLongPressStart =
                  ((d) => _select(_indexAt(d.localPosition.dx, width)))
              ..onLongPressMoveUpdate =
                  ((d) => _select(_indexAt(d.localPosition.dx, width))),
          ),
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (r) => r
              ..onTapUp = (d) {
                final index = _indexAt(d.localPosition.dx, width);
                if (index == _selected) {
                  setState(() => _selected = null);
                } else {
                  _select(index);
                }
              },
          ),
        },
        child: _buildChart(),
      );
    });
  }

  Widget _buildChart() {
    final points = widget.points;
    final values = widget.values;
    final unit = widget.unit;
    final selected = _selected;
    final spots = [
      for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
    ];
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    // Pad around the actual range rather than anchoring at zero - a lift
    // moving 100 -> 107.5 kg should read as progress, not a flat line.
    final span = maxValue - minValue;
    final pad = span == 0 ? (maxValue == 0 ? 1.0 : maxValue * 0.1) : span * 0.2;
    final minY = (minValue - pad).clamp(0.0, double.infinity);
    final maxY = maxValue + pad;

    final bar = LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.3,
      preventCurveOverShooting: true,
      gradient: LinearGradient(
        colors: [
          AppColors.accent.withValues(alpha: 0.35),
          AppColors.accent,
        ],
      ),
      barWidth: 3,
      isStrokeCapRound: true,
      // Only the latest session is marked - every other point stays
      // part of the line rather than a row of dots.
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, bar) => spot.x == spots.last.x,
        getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
          radius: 5,
          color: AppColors.accent,
          strokeColor: AppColors.background,
          strokeWidth: 2.5,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.accent.withValues(alpha: 0.22),
            AppColors.accent.withValues(alpha: 0),
          ],
        ),
      ),
      showingIndicators: selected == null ? const [] : [selected],
    );

    return LineChart(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 3,
          getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.onSurface.withValues(alpha: 0.05),
              strokeWidth: 1,
              dashArray: const [3, 5]),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i != 0 && i != points.length - 1) {
                  return const SizedBox.shrink();
                }
                final isLast = i == points.length - 1;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    DateFormat('MMM d').format(points[i].date),
                    style: AppTypography.labelCaps.copyWith(
                        fontSize: 10,
                        color: isLast ? AppColors.accent : AppColors.outline),
                  ),
                );
              },
            ),
          ),
        ),
        showingTooltipIndicators: [
          if (selected != null)
            ShowingTooltipIndicators([LineBarSpot(bar, 0, spots[selected])]),
        ],
        lineTouchData: LineTouchData(
          handleBuiltInTouches: false,
          getTouchedSpotIndicator: (bar, indexes) => [
            for (final _ in indexes)
              TouchedSpotIndicatorData(
                FlLine(
                    color: AppColors.accent.withValues(alpha: 0.35),
                    strokeWidth: 1,
                    dashArray: const [3, 3]),
                FlDotData(
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                    radius: 5,
                    color: AppColors.accent,
                    strokeColor: AppColors.background,
                    strokeWidth: 2,
                  ),
                ),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceContainerHighest,
            tooltipRoundedRadius: AppRadius.inset,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touchedSpots) => [
              for (final spot in touchedSpots)
                LineTooltipItem(
                  '${formatDisplayWeight(spot.y)} $unit\n${DateFormat('MMM d').format(points[spot.x.round()].date)}',
                  AppTypography.labelSm.copyWith(color: AppColors.onSurface),
                ),
            ],
          ),
        ),
        lineBarsData: [bar],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final ExerciseProgressPoint point;
  final String weightUnit;

  const _SessionRow({required this.point, required this.weightUnit});

  @override
  Widget build(BuildContext context) {
    final topSet = point.topWeightKg > 0
        ? '${formatWeight(point.topWeightKg, weightUnit)} $weightUnit × ${point.topSetReps}'
        : '${point.totalReps} reps';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(DateFormat('MMM d').format(point.date),
                style: AppTypography.labelSm
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
                '${point.setCount} set${point.setCount == 1 ? '' : 's'}',
                style: AppTypography.bodySm),
          ),
          Text(topSet,
              style: AppTypography.numericUnit.copyWith(
                  fontWeight: FontWeight.w600, color: AppColors.highEmphasis)),
        ],
      ),
    );
  }
}

class _RetryMessage extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _RetryMessage({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: Text('$message Tap to retry.',
          style:
              AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
    );
  }
}

/// Placeholder shown only behind the lock blur - never real data.
abstract final class _Sample {
  static final exercises = [
    TrackedExercise(
        exerciseId: 'sample-bench',
        exerciseName: 'Bench Press',
        sessionCount: 8,
        lastTrainedAtUtc: DateTime(2026)),
    TrackedExercise(
        exerciseId: 'sample-squat',
        exerciseName: 'Back Squat',
        sessionCount: 7,
        lastTrainedAtUtc: DateTime(2026)),
    TrackedExercise(
        exerciseId: 'sample-deadlift',
        exerciseName: 'Deadlift',
        sessionCount: 5,
        lastTrainedAtUtc: DateTime(2026)),
  ];

  static final progress = ExerciseProgress(
    exerciseId: 'sample-bench',
    days: 30,
    points: [
      for (final (i, weight) in [60.0, 62.5, 62.5, 65.0, 67.5, 70.0].indexed)
        ExerciseProgressPoint(
          date: DateTime.now().subtract(Duration(days: (5 - i) * 5)),
          topWeightKg: weight,
          topSetReps: 5,
          estimatedOneRmKg: weight * (1 + 5 / 30),
          totalVolumeKg: weight * 15,
          totalReps: 15,
          setCount: 3,
        ),
    ],
  );
}
