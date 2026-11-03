import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// A one-shot celebration burst: paper confetti that flips in 3D as it
/// tumbles, curly ribbons, and a few twinkling sparkles. It is hand-rolled
/// with a [CustomPainter] and an [AnimationController] rather than a
/// package, following the project's convention for animations.
///
/// Pieces launch from [origin] (a fraction of the box, so the default fires
/// from just above the middle), then slow down with air drag, sway and fall.
/// Plays once on mount. Give it a new `key` to fire it again.
class ConfettiBurst extends StatefulWidget {
  final int pieceCount;
  final Duration duration;
  final Alignment origin;

  /// How far pieces fly, in logical pixels, before drag stops them.
  final double power;

  const ConfettiBurst({
    super.key,
    this.pieceCount = 46,
    this.duration = const Duration(milliseconds: 2200),
    this.origin = const Alignment(0, -0.1),
    this.power = 260,
  });

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Piece> _pieces;

  // AppColors getters follow the theme, so this can't be const.
  static List<Color> get _palette => [
        AppColors.accent,
        AppColors.accent,
        AppColors.secondary,
        AppColors.tertiaryContainer,
        const Color(0xFFFFF3C4),
        Colors.white,
      ];

  @override
  void initState() {
    super.initState();
    final random = math.Random();
    final palette = _palette;
    _pieces = List.generate(widget.pieceCount, (i) {
      // Mostly upward, fanning out to both sides.
      final angle = -math.pi / 2 + (random.nextDouble() - 0.5) * math.pi * 1.25;
      final roll = random.nextDouble();
      final kind = roll < 0.62
          ? _Kind.paper
          : roll < 0.84
              ? _Kind.ribbon
              : _Kind.sparkle;
      return _Piece(
        kind: kind,
        angle: angle,
        speed: widget.power * (0.55 + random.nextDouble() * 0.6),
        size: kind == _Kind.sparkle
            ? 5 + random.nextDouble() * 4
            : 6 + random.nextDouble() * 5,
        color: kind == _Kind.sparkle
            ? const Color(0xFFFFF6D6)
            : palette[random.nextInt(palette.length)],
        spin: (random.nextDouble() - 0.5) * 9,
        flip: 3 + random.nextDouble() * 6,
        sway: 6 + random.nextDouble() * 12,
        phase: random.nextDouble() * math.pi * 2,
        delay: random.nextDouble() * 0.08,
      );
    });
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _ConfettiPainter(
              pieces: _pieces,
              t: _controller.value,
              origin: widget.origin,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

enum _Kind { paper, ribbon, sparkle }

class _Piece {
  final _Kind kind;
  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double spin;
  final double flip;
  final double sway;
  final double phase;
  final double delay;

  const _Piece({
    required this.kind,
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.spin,
    required this.flip,
    required this.sway,
    required this.phase,
    required this.delay,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final double t;
  final Alignment origin;

  const _ConfettiPainter(
      {required this.pieces, required this.t, required this.origin});

  @override
  void paint(Canvas canvas, Size size) {
    final start = origin.alongSize(size);
    final paint = Paint();
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      // Air drag: the launch decays exponentially; gravity takes over.
      final travel = 1 - math.exp(-4.2 * local);
      final dx = math.cos(p.angle) * p.speed * travel +
          math.sin(local * 9 + p.phase) * p.sway * local;
      final dy = math.sin(p.angle) * p.speed * travel +
          260 * local * local;
      final fade = local < 0.7 ? 1.0 : 1 - (local - 0.7) / 0.3;
      final pos = start + Offset(dx, dy);

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      switch (p.kind) {
        case _Kind.paper:
          canvas.rotate(p.spin * local * math.pi);
          // Scaling one axis by a cosine reads as the paper flipping over;
          // the back face is drawn a little darker.
          final flip = math.cos(local * p.flip * math.pi + p.phase);
          final face = flip >= 0
              ? p.color
              : Color.lerp(p.color, Colors.black, 0.28)!;
          paint
            ..style = PaintingStyle.fill
            ..color = face.withValues(alpha: fade);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset.zero,
                  width: p.size,
                  height: p.size * 0.62 * flip.abs().clamp(0.08, 1.0)),
              const Radius.circular(1.2),
            ),
            paint,
          );
        case _Kind.ribbon:
          canvas.rotate(p.spin * local * 0.6);
          final path = Path()..moveTo(0, -p.size);
          for (var k = 1; k <= 6; k++) {
            final y = -p.size + k * p.size * 0.42;
            final x = math.sin(k * 1.6 + local * 14 + p.phase) * p.size * 0.38;
            path.lineTo(x, y);
          }
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = p.color.withValues(alpha: fade);
          canvas.drawPath(path, paint);
        case _Kind.sparkle:
          final twinkle =
              0.55 + 0.45 * math.sin(local * 22 + p.phase).abs();
          final r = p.size * twinkle;
          paint
            ..style = PaintingStyle.fill
            ..color = p.color.withValues(alpha: fade * twinkle);
          canvas.drawPath(_star(r), paint);
          paint.color = p.color.withValues(alpha: fade * 0.25 * twinkle);
          canvas.drawCircle(Offset.zero, r * 0.9, paint);
      }
      canvas.restore();
    }
  }

  /// A four-point twinkle star.
  static Path _star(double r) {
    final w = r * 0.22;
    return Path()
      ..moveTo(0, -r)
      ..quadraticBezierTo(w, -w, r, 0)
      ..quadraticBezierTo(w, w, 0, r)
      ..quadraticBezierTo(-w, w, -r, 0)
      ..quadraticBezierTo(-w, -w, 0, -r)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.t != t;
}
