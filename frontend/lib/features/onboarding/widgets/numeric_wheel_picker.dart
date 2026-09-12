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
/// flick, and a magnetic spring settle with a little landing "pop" on the
/// value that comes to rest - plus a tick-mark ruler underneath that trails
/// the numbers at a slower parallax speed for a sense of depth. Optionally
/// preceded by a unit-toggle pill pair (cm/ft, kg/lb) - display conversion
/// only, the caller's [value]/[onChanged] stay in whatever unit is active.
class NumericWheelPicker extends StatefulWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final Color? valueColor;
  final String? suffixLabel;
  final String Function(int value)? displayFormatter;
  final List<String>? unitOptions;
  final String? selectedUnit;
  final ValueChanged<String>? onUnitChanged;

  const NumericWheelPicker({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.valueColor,
    this.suffixLabel,
    this.displayFormatter,
    this.unitOptions,
    this.selectedUnit,
    this.onUnitChanged,
  });

  @override
  State<NumericWheelPicker> createState() => _NumericWheelPickerState();
}

class _NumericWheelPickerState extends State<NumericWheelPicker>
    with TickerProviderStateMixin {
  static const _pxPerUnit = 58.0;
  static const _viewportWidth = 320.0;
  static const _filmHeight = 152.0;
  static const _slotRadius = 2; // slots rendered on each side of center

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
    duration: const Duration(milliseconds: 200),
  )..addListener(() {
      setState(() => _dragOffsetPx =
          _settleFrom * (1 - Curves.easeOutCubic.transform(_settle.value)));
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

  // A brief, crisp scale tick on whichever value just landed in center -
  // felt more than seen, confirming the pick without any wobble.
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  )..addListener(() => setState(() {}));

  @override
  void didUpdateWidget(covariant NumericWheelPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    _fling.dispose();
    _pop.dispose();
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
    if (velocity.abs() > 180) {
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
    _fling.animateWith(FrictionSimulation(0.05, 0, velocity)).whenComplete(() {
      if (!_isDragging) _settleNow();
    });
  }

  void _settleNow([_]) {
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
    final firstGap = _pxPerUnit + _centerGapExtra;
    return sign * (a <= 1 ? a * firstGap : firstGap + (a - 1) * _pxPerUnit);
  }

  Widget _buildSlot(int offset) {
    final v = widget.value + offset;
    if (v < widget.min || v > widget.max) return const SizedBox.shrink();

    final u = offset + _dragOffsetPx / _pxPerUnit;
    final x = _slotX(u);
    final t = (1 - u.abs()).clamp(0.0, 1.0);
    final fontSize = _lerp(30, 76, t);
    final color = Color.lerp(
        AppColors.onSurfaceVariant, widget.valueColor ?? AppColors.accent, t)!;

    // The value resting at dead center also carries a brief, crisp scale
    // tick timed to when it actually lands, not to the drag itself - decays
    // monotonically to 1.0 rather than oscillating, so it reads as a firm
    // confirmation rather than a bounce.
    final popT = Curves.easeOut.transform(_pop.value.clamp(0.0, 1.0));
    final popScale = offset == 0 ? 1 + (1 - popT) * 0.06 : 1.0;

    return Transform.translate(
      offset: Offset(x, _lerp(10, 0, t)),
      child: Opacity(
        opacity: _lerp(0.28, 1.0, t),
        child: Transform.scale(
          scale: popScale,
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
                    height: _filmHeight,
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

class _TickRuler extends StatelessWidget {
  final double width;

  const _TickRuler({required this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(width: width, height: 1, color: AppColors.outlineVariant),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(21, (i) {
              final isCenter = i == 10;
              return Container(
                width: 2,
                height: isCenter ? 24 : 12,
                decoration: BoxDecoration(
                  color: isCenter ? AppColors.accent : AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final option in options) ...[
          GestureDetector(
            onTap: () {
              if (option != selected) HapticFeedback.selectionClick();
              onSelected(option);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: option == selected
                    ? AppColors.accent
                    : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                option,
                style: AppTypography.labelSm.copyWith(
                  color: option == selected
                      ? AppColors.onAccent
                      : AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ],
    );
  }
}
