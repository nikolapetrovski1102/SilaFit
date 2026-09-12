import 'package:flutter/material.dart';

/// A custom-drawn dumbbell glyph - plates, collars and bar are rounded rects
/// with modest corner radii, so the silhouette reads as a crisp, purposeful
/// plate-and-bar shape rather than `Icons.fitness_center`'s sharp corners or
/// a fully pill-shaped blob.
/// Used anywhere the app needs a dumbbell mark (Today's active-split row,
/// onboarding's first slide) so both stay pixel-identical, just scaled.
///
/// Drawn on a fixed 100x56 design grid and scaled uniformly to [size] (the
/// widget's rendered width; height follows the grid's 56/100 aspect), so
/// the roundedness reads the same at any size instead of stretching.
class SoftDumbbellIcon extends StatelessWidget {
  final double size;
  final Color color;

  static const _aspect = 56 / 100;

  const SoftDumbbellIcon({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * _aspect,
      child: CustomPaint(painter: _SoftDumbbellPainter(color)),
    );
  }
}

class _SoftDumbbellPainter extends CustomPainter {
  final Color color;

  _SoftDumbbellPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final fill = Paint()..color = color;

    RRect plate(double left) => RRect.fromRectAndRadius(
          Rect.fromLTWH(left * s, 2 * s, 16 * s, 52 * s),
          Radius.circular(3.5 * s),
        );
    RRect collar(double left) => RRect.fromRectAndRadius(
          Rect.fromLTWH(left * s, 15 * s, 8 * s, 26 * s),
          Radius.circular(2 * s),
        );
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(28 * s, 22 * s, 44 * s, 12 * s),
      Radius.circular(2.5 * s),
    );

    for (final shape in [collar(2), plate(12), bar, plate(72), collar(90)]) {
      canvas.drawRRect(shape, fill);
      // A faint top-to-bottom sheen, clipped to the shape itself - just
      // enough to read as smooth/lit rather than a flat cutout.
      canvas.save();
      canvas.clipRRect(shape);
      canvas.drawRect(
        shape.outerRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withOpacity(0.25), Colors.transparent],
          ).createShader(shape.outerRect),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SoftDumbbellPainter oldDelegate) =>
      oldDelegate.color != color;
}
