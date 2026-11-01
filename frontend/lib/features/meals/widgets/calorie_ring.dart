import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/progress_ring.dart';

/// Shared by the Nutrition screen's calorie ring and the targets editor's,
/// so tapping the one flies it into the other.
const kCalorieRingHeroTag = 'nutrition-calorie-ring';

/// The calorie ring at any size: stroke and type are proportions of the
/// diameter, so it reads the same at 128 px on the Nutrition screen, 240 px
/// in the editor and every size the Hero passes through between them.
class CalorieRing extends StatelessWidget {
  /// 0.0 - 1.0.
  final double progress;

  /// The big number in the middle, and the caps label under it.
  final int value;
  final String label;

  /// Stroke width as a fraction of the diameter.
  final double strokeFraction;

  /// See [RadialProgressRing.initialProgress].
  final double? initialProgress;

  const CalorieRing({
    super.key,
    required this.progress,
    required this.value,
    required this.label,
    this.strokeFraction = 0.086,
    this.initialProgress,
  });

  @override
  Widget build(BuildContext context) {
    return _RingLayout(
      progress: progress,
      strokeFraction: strokeFraction,
      initialProgress: initialProgress,
      center: (size) => _RingCenter(value: value, label: label, size: size),
    );
  }

  /// Wraps [ring] in the shared Hero. [onTap] makes it a button.
  static Widget hero({required CalorieRing ring, VoidCallback? onTap}) {
    final hero = Hero(
      tag: kCalorieRingHeroTag,
      flightShuttleBuilder: _shuttle,
      child: ring,
    );
    if (onTap == null) return hero;
    return Semantics(
      button: true,
      label: 'Edit daily calorie and macro targets',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: hero,
      ),
    );
  }

  /// In flight the ring morphs - arc, stroke and size - while the two
  /// centers cross-fade. The route animation runs 0 -> 1 on push and back
  /// to 0 on pop, so 0 is always the Nutrition screen's face and 1 the
  /// editor's.
  static Widget _shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final from = (fromHeroContext.widget as Hero).child as CalorieRing;
    final to = (toHeroContext.widget as Hero).child as CalorieRing;
    final push = direction == HeroFlightDirection.push;
    final base = push ? from : to;
    final editor = push ? to : from;
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic);

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, _) {
          final t = curved.value;
          final progress = lerpDouble(base.progress, editor.progress, t)!;
          return _RingLayout(
            progress: progress,
            initialProgress: progress,
            animate: false,
            strokeFraction:
                lerpDouble(base.strokeFraction, editor.strokeFraction, t)!,
            center: (size) => Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: (1 - t * 2).clamp(0.0, 1.0),
                  child: _RingCenter(
                      value: base.value, label: base.label, size: size),
                ),
                Opacity(
                  opacity: (t * 2 - 1).clamp(0.0, 1.0),
                  child: _RingCenter(
                      value: editor.value, label: editor.label, size: size),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RingLayout extends StatelessWidget {
  final double progress;
  final double strokeFraction;
  final double? initialProgress;
  final bool animate;
  final Widget Function(double size) center;

  const _RingLayout({
    required this.progress,
    required this.strokeFraction,
    required this.center,
    this.initialProgress,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = math.min(constraints.maxWidth, constraints.maxHeight);
      final stroke = size * strokeFraction;
      return Center(
        child: RadialProgressRing(
          progress: progress,
          size: size,
          strokeWidth: stroke,
          initialProgress: initialProgress,
          duration: animate ? const Duration(milliseconds: 600) : Duration.zero,
          child: Padding(
            padding: EdgeInsets.all(stroke + size * 0.06),
            child: center(size),
          ),
        ),
      );
    });
  }
}

class _RingCenter extends StatelessWidget {
  final int value;
  final String label;
  final double size;

  const _RingCenter({
    required this.value,
    required this.label,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$value',
              maxLines: 1,
              style: AppTypography.displayStatMobile
                  .copyWith(fontSize: size * 0.22, height: 1.05)),
          Text(label,
              maxLines: 1,
              style: AppTypography.labelCaps.copyWith(
                  fontSize: math.max(9, size * 0.08),
                  color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}
