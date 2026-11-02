import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/silen_button.dart';

// Mirrors the bounds dbo.split_day_exercise_upsert enforces.
const _kMaxSets = 20;
const _kMaxReps = 100;

const _kItemExtent = 44.0;
const _kWheelHeight = _kItemExtent * 5;

/// Bottom sheet with three vertical wheels - sets, min reps and max reps -
/// that snap to a value as they're flicked. The rep wheels keep each other
/// honest: pushing min past max drags max along with it (and vice versa),
/// so the range can never be saved inverted.
///
/// Returns `(sets, repsLow, repsHigh)`, or null if dismissed.
Future<(int, int, int)?> showSetsRepsSheet(
  BuildContext context, {
  required int initialSets,
  required int initialLow,
  required int initialHigh,
}) {
  return showModalBottomSheet<(int, int, int)>(
    context: context,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
    builder: (_) => _SetsRepsSheet(
      initialSets: initialSets.clamp(1, _kMaxSets),
      initialLow: initialLow.clamp(1, _kMaxReps),
      initialHigh: initialHigh.clamp(initialLow.clamp(1, _kMaxReps), _kMaxReps),
    ),
  );
}

class _SetsRepsSheet extends StatefulWidget {
  final int initialSets;
  final int initialLow;
  final int initialHigh;

  const _SetsRepsSheet({
    required this.initialSets,
    required this.initialLow,
    required this.initialHigh,
  });

  @override
  State<_SetsRepsSheet> createState() => _SetsRepsSheetState();
}

class _SetsRepsSheetState extends State<_SetsRepsSheet> {
  late int _sets = widget.initialSets;
  late int _low = widget.initialLow;
  late int _high = widget.initialHigh;

  // Wheels are zero-indexed; every value is index + 1.
  late final _setsWheel =
      FixedExtentScrollController(initialItem: widget.initialSets - 1);
  late final _lowWheel =
      FixedExtentScrollController(initialItem: widget.initialLow - 1);
  late final _highWheel =
      FixedExtentScrollController(initialItem: widget.initialHigh - 1);

  @override
  void dispose() {
    _setsWheel.dispose();
    _lowWheel.dispose();
    _highWheel.dispose();
    super.dispose();
  }

  void _follow(FixedExtentScrollController wheel, int value) {
    if (!wheel.hasClients) return;
    wheel.animateToItem(value - 1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic);
  }

  void _onLow(int value) {
    setState(() {
      _low = value;
      if (_high < value) {
        _high = value;
        _follow(_highWheel, value);
      }
    });
  }

  void _onHigh(int value) {
    setState(() {
      _high = value;
      if (_low > value) {
        _low = value;
        _follow(_lowWheel, value);
      }
    });
  }

  String get _summary => _low == _high
      ? '$_sets × $_low reps'
      : '$_sets × $_low–$_high reps';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
            AppSpacing.marginMobile, AppSpacing.marginMobile, AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sets and reps', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.xxs),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, if (current != null) current],
              ),
              child: Text(
                _summary,
                key: ValueKey(_summary),
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: _label('SETS')),
                Expanded(child: _label('MIN REPS')),
                Expanded(child: _label('MAX REPS')),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: _kWheelHeight,
              child: Stack(
                children: [
                  // Selection band behind the centre row of every wheel.
                  Center(
                    child: Container(
                      height: _kItemExtent,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadius.inset),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _NumberWheel(
                          controller: _setsWheel,
                          max: _kMaxSets,
                          selected: _sets,
                          onChanged: (v) => setState(() => _sets = v),
                        ),
                      ),
                      Expanded(
                        child: _NumberWheel(
                          controller: _lowWheel,
                          max: _kMaxReps,
                          selected: _low,
                          onChanged: _onLow,
                        ),
                      ),
                      Expanded(
                        child: _NumberWheel(
                          controller: _highWheel,
                          max: _kMaxReps,
                          selected: _high,
                          onChanged: _onHigh,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryPillButton(
              label: 'Save',
              onPressed: () => Navigator.of(context).pop((_sets, _low, _high)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        textAlign: TextAlign.center,
        style: AppTypography.labelCaps.copyWith(color: AppColors.accent),
      );
}

/// One vertical wheel of 1..[max]. Rows shrink and fade toward the edges
/// and the wheel snaps to the nearest value, with a selection tick each
/// time a new value crosses the centre.
class _NumberWheel extends StatelessWidget {
  final FixedExtentScrollController controller;
  final int max;
  final int selected;
  final ValueChanged<int> onChanged;

  const _NumberWheel({
    required this.controller,
    required this.max,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      // Fade the top and bottom rows out into the sheet.
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.black,
          Colors.black,
          Colors.transparent
        ],
        stops: [0, 0.3, 0.7, 1],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: _kItemExtent,
        physics: const FixedExtentScrollPhysics(),
        diameterRatio: 1.6,
        perspective: 0.004,
        squeeze: 1.0,
        overAndUnderCenterOpacity: 0.45,
        onSelectedItemChanged: (index) {
          HapticFeedback.selectionClick();
          onChanged(index + 1);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: max,
          builder: (context, index) {
            final value = index + 1;
            final isSelected = value == selected;
            return Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 140),
                style: (isSelected
                        ? AppTypography.headlineMd
                        : AppTypography.bodyLg)
                    .copyWith(
                  color: isSelected
                      ? AppColors.onSurface
                      : AppColors.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                child: Text('$value'),
              ),
            );
          },
        ),
      ),
    );
  }
}
