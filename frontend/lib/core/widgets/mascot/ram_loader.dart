import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'ram_mascot.dart';

/// Sila charging up: the loading animation for the splash screen and any
/// wait long enough to deserve more than a spinner.
///
/// One piece of art ([RamArt.emblem]) animated in code: a steady breathing
/// bob, a head-butt nod every loop (wind up, snap forward, settle), and
/// four-point sparkles in the accent color that twinkle around the horns.
/// With reduce-motion on it renders the still emblem.
class RamLoader extends StatefulWidget {
  final double size;

  const RamLoader({super.key, this.size = 160});

  @override
  State<RamLoader> createState() => _RamLoaderState();
}

class _RamLoaderState extends State<RamLoader>
    with SingleTickerProviderStateMixin {
  /// Every motion below runs a whole number of times per [_loop], so the
  /// controller can simply repeat with no visible seam.
  static const _loop = Duration(milliseconds: 2400);

  late final AnimationController _c =
      AnimationController(vsync: this, duration: _loop)..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(AssetImage(RamArt.emblem.assetPath), context);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// The head-butt: rotation (radians) and forward lunge (fraction of size)
  /// for loop progress [t]. Quiet for the first half, then a slow wind-up
  /// back, a fast snap forward and an overshooting settle.
  static (double, double) _butt(double t) {
    if (t < 0.5) return (0, 0);
    final p = (t - 0.5) / 0.5;
    if (p < 0.35) {
      final e = Curves.easeOut.transform(p / 0.35);
      return (-0.10 * e, -0.02 * e);
    }
    if (p < 0.5) {
      final e = Curves.easeIn.transform((p - 0.35) / 0.15);
      return (-0.10 + 0.18 * e, -0.02 + 0.07 * e);
    }
    final e = Curves.elasticOut.transform((p - 0.5) / 0.5);
    return (0.08 * (1 - e), 0.05 * (1 - e));
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final ram = RamMascot(RamArt.emblem, size: size * 0.82,
        excludeFromSemantics: true);

    if (MediaQuery.disableAnimationsOf(context)) {
      return Semantics(
        label: '$mascotName is loading',
        child: SizedBox.square(dimension: size, child: Center(child: ram)),
      );
    }

    return Semantics(
      label: '$mascotName is loading',
      child: SizedBox.square(
        dimension: size,
        child: AnimatedBuilder(
          animation: _c,
          child: ram,
          builder: (context, child) {
            final t = _c.value;
            final breath = math.sin(t * 2 * 2 * math.pi);
            final (angle, lunge) = _butt(t);
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: Size.square(size),
                  painter: _SparklePainter(t: t, color: AppColors.accent),
                ),
                Transform(
                  alignment: const Alignment(0, 0.6),
                  transform: Matrix4.identity()
                    ..translateByDouble(
                        0, size * (lunge - 0.012 * breath), 0, 1)
                    ..rotateZ(angle)
                    ..scaleByDouble(
                        1 + 0.012 * breath, 1 - 0.012 * breath, 1, 1),
                  child: child,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Four-point sparkles that pop in around the horns, twinkle and fade.
class _SparklePainter extends CustomPainter {
  final double t;
  final Color color;

  _SparklePainter({required this.t, required this.color});

  // (x, y as fractions of size, radius fraction, phase offset). Each sparkle
  // twinkles once per loop at its own phase.
  static const _sparkles = [
    (0.12, 0.18, 0.050, 0.00),
    (0.88, 0.14, 0.060, 0.30),
    (0.94, 0.52, 0.038, 0.62),
    (0.06, 0.58, 0.042, 0.80),
    (0.74, 0.04, 0.032, 0.48),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final (x, y, r, phase) in _sparkles) {
      final p = (t + phase) % 1;
      // Visible for the first 40% of its cycle: grow, then shrink away.
      if (p > 0.4) continue;
      final s = math.sin(p / 0.4 * math.pi);
      final radius = size.width * r * s;
      final c = Offset(size.width * x, size.height * y);
      final waist = radius * 0.22;
      final path = Path()
        ..moveTo(c.dx, c.dy - radius)
        ..quadraticBezierTo(c.dx + waist, c.dy - waist, c.dx + radius, c.dy)
        ..quadraticBezierTo(c.dx + waist, c.dy + waist, c.dx, c.dy + radius)
        ..quadraticBezierTo(c.dx - waist, c.dy + waist, c.dx - radius, c.dy)
        ..quadraticBezierTo(c.dx - waist, c.dy - waist, c.dx, c.dy - radius)
        ..close();
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(p * 0.8);
      canvas.translate(-c.dx, -c.dy);
      paint.color = color.withValues(alpha: 0.9 * s);
      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t || old.color != color;
}
