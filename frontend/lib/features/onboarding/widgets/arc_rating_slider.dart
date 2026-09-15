import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// A drag-to-adjust curved rating slider: a handle glides along a rising
/// arc between [values].length discrete stops, with the current stop's
/// number and label read out beside it. Used for "how would you rate
/// yourself" style questions (training experience) where a single
/// continuous gesture reads better than a list of rows.
class ArcRatingSlider extends StatefulWidget {
  final List<String> values; // backend-canonical values, low -> high
  final Map<String, String> labels; // value -> display label
  final List<int>? displayNumbers;
  final String? selected;
  final ValueChanged<String> onSelected;

  const ArcRatingSlider({
    super.key,
    required this.values,
    required this.labels,
    this.displayNumbers,
    required this.selected,
    required this.onSelected,
  }) : assert(displayNumbers == null || displayNumbers.length == values.length);

  @override
  State<ArcRatingSlider> createState() => _ArcRatingSliderState();
}

class _ArcRatingSliderState extends State<ArcRatingSlider>
    with SingleTickerProviderStateMixin {
  static const _height = 330.0;
  static const _handleSize = 78.0;

  late double _t = _tFor(widget.selected);
  Offset _pointerDownPosition = Offset.zero;
  double _gestureStartT = 0;
  int? _lastHapticStop;

  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(_onSnapTick);
  double _snapFrom = 0;
  double _snapTo = 0;

  double _tFor(String? value) {
    if (value == null || widget.values.length < 2) return 0;
    final i = widget.values.indexOf(value);
    return i == -1 ? 0 : i / (widget.values.length - 1);
  }

  int get _stopCount => widget.values.length;

  @override
  void initState() {
    super.initState();
    if (widget.selected == null && widget.values.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.selected == null) {
          widget.onSelected(widget.values[widget.values.length ~/ 2]);
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant ArcRatingSlider old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      final newT = _tFor(widget.selected);
      if ((newT - _t).abs() > 0.001) setState(() => _t = newT);
    }
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  void _onPanDown(DragDownDetails d) {
    _snap.stop();
    _pointerDownPosition = d.localPosition;
    _gestureStartT = _t;
    _lastHapticStop = (_t * (_stopCount - 1)).round();
  }

  void _updateDrag(Offset position, Size size) {
    final geometry = _ArcGeometry(size);
    final drag = position - _pointerDownPosition;
    final horizontal = drag.dx / (geometry.end.dx - geometry.start.dx);
    final vertical = -drag.dy / (geometry.start.dy - geometry.end.dy);

    // Follow whichever axis the finger is intentionally moving most. This
    // makes both a simple horizontal swipe and a diagonal trace of the curve
    // cover the full range without double-counting diagonal movement.
    final deltaT = horizontal.abs() >= vertical.abs() ? horizontal : vertical;
    final nextT = (_gestureStartT + deltaT).clamp(0.0, 1.0);
    final nextStop = (nextT * (_stopCount - 1)).round();
    if (nextStop != _lastHapticStop) {
      _lastHapticStop = nextStop;
      HapticFeedback.selectionClick();
    }
    setState(() => _t = nextT);
  }

  void _selectAt(Offset position, Size size) {
    if (_stopCount < 2) return;
    final nearestT = _ArcGeometry(size).closestT(position);
    final nearestStop = (nearestT * (_stopCount - 1)).round();
    _animateTo(nearestStop / (_stopCount - 1));
    final value = widget.values[nearestStop];
    if (value != widget.selected) {
      HapticFeedback.selectionClick();
      widget.onSelected(value);
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_stopCount < 2) return;
    final nearestStop = (_t * (_stopCount - 1)).round();
    _animateTo(nearestStop / (_stopCount - 1));
    final value = widget.values[nearestStop];
    if (value != widget.selected) {
      HapticFeedback.lightImpact();
      widget.onSelected(value);
    }
  }

  void _animateTo(double target) {
    _snapFrom = _t;
    _snapTo = target;
    _snap.forward(from: 0);
  }

  void _onSnapTick() {
    setState(() {
      _t = _snapFrom +
          (_snapTo - _snapFrom) * Curves.easeOutCubic.transform(_snap.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final stopIndex = (_t * (_stopCount - 1)).round().clamp(0, _stopCount - 1);
    final value = widget.values.isEmpty ? null : widget.values[stopIndex];
    final label = widget.labels[value] ?? '';
    final displayNumber = widget.displayNumbers?[stopIndex] ?? (stopIndex + 1);
    final visualTickCount = widget.displayNumbers?.last ?? _stopCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceContainerHigh,
              ),
              child: Icon(Icons.question_mark_rounded,
                  size: 11, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text('Drag to adjust',
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: _height,
          width: double.infinity,
          child: LayoutBuilder(builder: (context, constraints) {
            final size = Size(constraints.maxWidth, _height);
            final geometry = _ArcGeometry(size);
            final handlePos = geometry.point(_t);
            return GestureDetector(
              key: const Key('fitness-rating-gesture'),
              behavior: HitTestBehavior.opaque,
              onPanDown: _onPanDown,
              onPanStart: (d) => _updateDrag(d.localPosition, size),
              onPanUpdate: (d) => _updateDrag(d.localPosition, size),
              onPanEnd: _onPanEnd,
              onTapUp: (d) => _selectAt(d.localPosition, size),
              onPanCancel: () => _animateTo(
                ((_t * (_stopCount - 1)).round()) / (_stopCount - 1),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(
                    size: size,
                    painter: _ArcPainter(t: _t, stopCount: visualTickCount),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$displayNumber',
                            style: AppTypography.displayStatXl.copyWith(
                              color: AppColors.highEmphasis,
                              fontSize: 104,
                              height: 0.92,
                              fontWeight: FontWeight.w700,
                            )),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(label,
                            textAlign: TextAlign.right,
                            style: AppTypography.headlineSm.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            )),
                      ],
                    ),
                  ),
                  Positioned(
                    left: handlePos.dx - _handleSize / 2,
                    top: handlePos.dy - _handleSize / 2,
                    child: IgnorePointer(
                      child: Container(
                        key: const Key('fitness-rating-thumb'),
                        width: _handleSize,
                        height: _handleSize,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(23),
                          border: Border.all(
                            color: AppColors.outlineVariant
                                .withValues(alpha: 0.55),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF000000)
                                  .withValues(alpha: 0.14),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Container(
                            width: 27,
                            height: 27,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: AppColors.accent, width: 3),
                            ),
                            child: Center(
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.surfaceContainerLowest,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// The rising cubic-bezier track the handle drags along: it leaves the lower
/// endpoint vertically and arrives at the upper endpoint horizontally.
class _ArcGeometry {
  final Size size;
  _ArcGeometry(this.size);

  static const _edgeInset = _ArcRatingSliderState._handleSize / 2 + 5;
  static const _curveFactor = 0.56;

  Offset get start => Offset(_edgeInset, size.height - _edgeInset);
  Offset get end => Offset(size.width - _edgeInset, _edgeInset);
  Offset get startControl => Offset(
        start.dx,
        start.dy - (start.dy - end.dy) * _curveFactor,
      );
  Offset get endControl => Offset(
        end.dx - (end.dx - start.dx) * _curveFactor,
        end.dy,
      );

  Offset point(double t) {
    final mt = 1 - t;
    return Offset(
      mt * mt * mt * start.dx +
          3 * mt * mt * t * startControl.dx +
          3 * mt * t * t * endControl.dx +
          t * t * t * end.dx,
      mt * mt * mt * start.dy +
          3 * mt * mt * t * startControl.dy +
          3 * mt * t * t * endControl.dy +
          t * t * t * end.dy,
    );
  }

  Offset tangent(double t) => Offset(
        3 * (1 - t) * (1 - t) * (startControl.dx - start.dx) +
            6 * (1 - t) * t * (endControl.dx - startControl.dx) +
            3 * t * t * (end.dx - endControl.dx),
        3 * (1 - t) * (1 - t) * (startControl.dy - start.dy) +
            6 * (1 - t) * t * (endControl.dy - startControl.dy) +
            3 * t * t * (end.dy - endControl.dy),
      );

  /// Finds the point on the painted curve that is closest to the pointer.
  /// A short sampling pass followed by local refinement keeps dragging glued
  /// to the arc even near its more vertical lower-left section.
  double closestT(Offset position) {
    const samples = 48;
    var bestT = 0.0;
    var bestDistance = double.infinity;
    for (var i = 0; i <= samples; i++) {
      final candidateT = i / samples;
      final distance = (point(candidateT) - position).distanceSquared;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestT = candidateT;
      }
    }

    var low = (bestT - 1 / samples).clamp(0.0, 1.0);
    var high = (bestT + 1 / samples).clamp(0.0, 1.0);
    for (var i = 0; i < 10; i++) {
      final left = low + (high - low) / 3;
      final right = high - (high - low) / 3;
      final leftDistance = (point(left) - position).distanceSquared;
      final rightDistance = (point(right) - position).distanceSquared;
      if (leftDistance < rightDistance) {
        high = right;
      } else {
        low = left;
      }
    }
    return (low + high) / 2;
  }
}

class _ArcPainter extends CustomPainter {
  final double t;
  final int stopCount;
  _ArcPainter({required this.t, required this.stopCount});

  Path _tracePath(_ArcGeometry g, double t0, double t1) {
    const steps = 32;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final s = t0 + (t1 - t0) * i / steps;
      final p = g.point(s);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _ArcGeometry(size);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = AppColors.outlineVariant.withValues(alpha: 0.55);
    canvas.drawPath(_tracePath(geometry, 0, 1), trackPaint);

    if (t > 0) {
      final filledPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = AppColors.accent;
      canvas.drawPath(_tracePath(geometry, 0, t), filledPaint);
    }

    if (stopCount > 1) {
      final tickPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = AppColors.onSurface.withValues(alpha: 0.5);
      for (var i = 0; i < stopCount; i++) {
        final stopT = i / (stopCount - 1);
        final center = geometry.point(stopT);
        final tangent = geometry.tangent(stopT);
        final len = tangent.distance;
        if (len == 0) continue;
        final normal = Offset(-tangent.dy / len, tangent.dx / len);
        final halfLength = i == 0 || i == stopCount - 1 ? 13.0 : 10.0;
        canvas.drawLine(
          center + normal * halfLength,
          center - normal * halfLength,
          tickPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.stopCount != stopCount;
}
