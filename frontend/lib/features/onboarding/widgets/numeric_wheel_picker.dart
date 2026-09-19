import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// The horizontal drag-to-scrub numeric picker used for age/height/weight: a
/// continuous filmstrip of values that grow and brighten as they near
/// the center, a momentum fling that keeps spinning and decelerates after a
/// flick, and a quick settle without overshoot - plus a tick-mark ruler that trails
/// the numbers at a slower parallax speed for a sense of depth. Optionally
/// preceded by a unit-toggle pill pair (cm/ft, kg/lb) - display conversion
/// only, the caller's [value]/[onChanged] stay in whatever unit is active.
class NumericWheelPicker extends StatefulWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final Color? valueColor;

  /// Smaller sizes let decimal measurements fit without overlapping neighbours.
  final double valueFontSize;
  final double neighborFontSize;
  final String? suffixLabel;
  final String Function(int value)? displayFormatter;
  final List<String>? unitOptions;
  final String? selectedUnit;
  final ValueChanged<String>? onUnitChanged;

  /// Height of the scrubbable filmstrip. Callers embedding the picker in a
  /// tighter space (e.g. a summary card) can shrink this independently of
  /// the default used by the full-screen onboarding steps.
  final double filmHeight;

  const NumericWheelPicker({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.valueColor,
    this.valueFontSize = 88,
    this.neighborFontSize = 34,
    this.suffixLabel,
    this.displayFormatter,
    this.unitOptions,
    this.selectedUnit,
    this.onUnitChanged,
    this.filmHeight = 172,
  });

  @override
  State<NumericWheelPicker> createState() => _NumericWheelPickerState();
}

class _NumericWheelPickerState extends State<NumericWheelPicker>
    with TickerProviderStateMixin {
  static const _pxPerUnit = 72.0;
  static const _viewportWidth = 320.0;
  static const _slotRadius = 1; // slots rendered on each side of center

  // Extra px of spacing straddling the centered value only - the two gaps
  // nearest the selection read as deliberately roomier than the rest of the
  // filmstrip, so the current pick visually separates itself from its
  // neighbors instead of sitting in a perfectly even row of numbers.
  static const _centerGapExtra = 26.0;

  // Live sub-unit drag offset, in px, always in (-_pxPerUnit, _pxPerUnit) -
  // this is what makes the picker track the finger (or the fling)
  // continuously instead of only visibly reacting once a whole unit has
  // been crossed.
  double _dragOffsetPx = 0;
  bool _isDragging = false;

  // Eases whatever's left of `_dragOffsetPx` back to 0 once a drag or fling
  // ends - quick and decisive, no overshoot, so the wheel reads as snapping
  // precisely to the value rather than wobbling into place.
  double _settleFrom = 0;
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..addListener(() {
      setState(() => _dragOffsetPx =
          _settleFrom * (1 - Curves.easeOutQuint.transform(_settle.value)));
    });

  // Drives momentum after a fast flick: an unbounded controller animated
  // with a friction simulation, its per-tick delta fed through the exact
  // same crossing logic a real drag uses. Tuned tight (high drag) so a flick
  // decelerates fast and stops decisively instead of floating on.
  double _flingLastValue = 0;
  late final AnimationController _fling = AnimationController.unbounded(
    vsync: this,
  )..addListener(() {
      final v = _fling.value;
      _applyDelta(v - _flingLastValue);
      _flingLastValue = v;
    });

  @override
  void dispose() {
    _settle.dispose();
    _fling.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    _isDragging = true;
    _settle.stop();
    _fling.stop();
  }

  void _applyDelta(double deltaPx) {
    setState(() {
      _dragOffsetPx += deltaPx;
      while (_dragOffsetPx <= -_pxPerUnit) {
        final next = (widget.value + 1).clamp(widget.min, widget.max);
        if (next == widget.value) {
          _dragOffsetPx = 0; // pinned at max - stop tracking past the edge
          break;
        }
        _dragOffsetPx += _pxPerUnit;
        widget.onChanged(next);
        HapticFeedback.selectionClick();
      }
      while (_dragOffsetPx >= _pxPerUnit) {
        final next = (widget.value - 1).clamp(widget.min, widget.max);
        if (next == widget.value) {
          _dragOffsetPx = 0; // pinned at min
          break;
        }
        _dragOffsetPx -= _pxPerUnit;
        widget.onChanged(next);
        HapticFeedback.selectionClick();
      }
    });
  }

  void _onDragUpdate(DragUpdateDetails details) =>
      _applyDelta(details.delta.dx);

  void _onDragEnd(DragEndDetails details) {
    _isDragging = false;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() > 220) {
      _startFling(velocity);
    } else {
      _settleNow();
    }
  }

  void _onDragCancel() {
    _isDragging = false;
    _settleNow();
  }

  void _startFling(double velocity) {
    _flingLastValue = 0;
    _fling.value = 0;
    final softenedVelocity = velocity.clamp(-1800.0, 1800.0);
    _fling
        .animateWith(FrictionSimulation(0.025, 0, softenedVelocity))
        .whenComplete(() {
      if (!_isDragging) _settleNow();
    });
  }

  void _settleNow() {
    if (_dragOffsetPx == 0) return;
    _settleFrom = _dragOffsetPx;
    _settle.forward(from: 0);
  }

  String _format(int v) => widget.displayFormatter?.call(v) ?? '$v';

  // Maps a slot's continuous distance from center, in whole units (`u`),
  // to its x position in px. Linear beyond the first neighbor on each
  // side, but the center-to-neighbor span is widened by
  // `_centerGapExtra` so the selected value gets extra breathing room -
  // this stays a pure function of `u` so it interpolates exactly as
  // smoothly through a drag/fling/value-crossing as the old uniform
  // spacing did.
  double _slotX(double u) {
    final sign = u < 0 ? -1.0 : 1.0;
    final a = u.abs();
    const firstGap = _pxPerUnit + _centerGapExtra;
    return sign * (a <= 1 ? a * firstGap : firstGap + (a - 1) * _pxPerUnit);
  }

  Widget _buildSlot(int offset) {
    final v = widget.value + offset;
    if (v < widget.min || v > widget.max) return const SizedBox.shrink();

    final u = offset + _dragOffsetPx / _pxPerUnit;
    final x = _slotX(u);
    final t = (1 - u.abs()).clamp(0.0, 1.0);
    final fontSize = _lerp(widget.neighborFontSize, widget.valueFontSize, t);
    final color = Color.lerp(
        AppColors.onSurfaceVariant, widget.valueColor ?? AppColors.accent, t)!;

    return Transform.translate(
      offset: Offset(x, _lerp(10, 0, t)),
      child: Opacity(
        opacity: _lerp(0.14, 1.0, t),
        child: Text(
          _format(v),
          textAlign: TextAlign.center,
          style: AppTypography.displayStatXl.copyWith(
            fontSize: fontSize,
            letterSpacing: -0.03 * fontSize,
            color: color,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.unitOptions != null) ...[
          _UnitTogglePills(
            options: widget.unitOptions!,
            selected: widget.selectedUnit!,
            onSelected: widget.onUnitChanged!,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        GestureDetector(
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: _onDragCancel,
          behavior: HitTestBehavior.opaque,
          // LayoutBuilder hands both the filmstrip and the ruler the real
          // available width - the same width the CTA button and progress bar
          // above it get - so the whole picker reads as one deliberately
          // full-width control instead of a fixed-width island with its
          // ruler/shadowed fade edges landing at a different, narrower point
          // than the screen's actual margins.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fullWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : _viewportWidth;
              return Column(
                children: [
                  SizedBox(
                    width: fullWidth,
                    height: widget.filmHeight,
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black,
                          Colors.black,
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.22, 0.78, 1.0],
                      ).createShader(bounds),
                      blendMode: BlendMode.dstIn,
                      child: Stack(
                        fit: StackFit.expand,
                        clipBehavior: Clip.hardEdge,
                        alignment: Alignment.center,
                        children: [
                          for (var o = -_slotRadius; o <= _slotRadius; o++)
                            _buildSlot(o),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Transform.translate(
                    offset: Offset(_dragOffsetPx * 0.35, 0),
                    child: _TickRuler(width: fullWidth),
                  ),
                ],
              );
            },
          ),
        ),
        if (widget.suffixLabel != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(widget.suffixLabel!.toUpperCase(),
              style: AppTypography.labelCaps
                  .copyWith(color: AppColors.onSurfaceVariant)),
        ],
      ],
    );
  }
}

/// A tape-measure ruler: soft, rounded ticks (every 5th slightly taller,
/// like inch marks) at low contrast, with a bold accent bar fixed at center
/// marking the current value - the bar stays put while the whole tick row
/// slides beneath it as the value changes. Sized and spaced generously so it
/// reads as a deliberate control rather than a thin decorative line.
class _TickRuler extends StatelessWidget {
  final double width;

  const _TickRuler({required this.width});

  static const _tickCount = 25;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_tickCount, (i) {
              final isMajor = i % 5 == 0;
              return Container(
                width: 2.5,
                height: isMajor ? 26 : 14,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant
                      .withValues(alpha: isMajor ? 0.9 : 0.45),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
          Container(
            width: 6,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitTogglePills extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  const _UnitTogglePills(
      {required this.options,
      required this.selected,
      required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (option != selected) HapticFeedback.selectionClick();
                  onSelected(option);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: option == selected
                        ? AppColors.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.inset),
                  ),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    style: AppTypography.labelSm.copyWith(
                      color: option == selected
                          ? AppColors.onAccent
                          : AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                    child: Text(option),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
