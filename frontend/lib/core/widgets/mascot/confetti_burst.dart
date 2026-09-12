import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// A one-shot confetti burst - a fixed set of colored rectangles fired
/// outward from the center and fading as they fall, hand-rolled via
/// [CustomPainter] + [AnimationController] rather than a package, per the
/// project's hand-roll-animation convention. Plays once on mount and stops;
/// give it a `key` if you need to replay it.
class ConfettiBurst extends StatefulWidget {
  final int pieceCount;
  final Duration duration;

  const ConfettiBurst({super.key, this.pieceCount = 26, this.duration = const Duration(milliseconds: 1400)});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiPiece> _pieces;

  // Not `const` - AppColors.accent/secondary are runtime getters (dark/light
  // aware), not compile-time constants.
  static List<Color> get _palette => [
        AppColors.accent,
        AppColors.secondary,
        AppColors.tertiaryContainer,
        Colors.white,
      ];

  @override
  void initState() {
    super.initState();
    final random = math.Random();
    final palette = _palette;
    _pieces = List.generate(widget.pieceCount, (_) {
      final angle = random.nextDouble() * math.pi - math.pi; // -pi..0 (upward fan)
      return _ConfettiPiece(
        angle: angle,
        speed: 120 + random.nextDouble() * 140,
        size: 5 + random.nextDouble() * 5,
        color: palette[random.nextInt(palette.length)],
        spin: (random.nextDouble() - 0.5) * 10,
        delay: random.nextDouble() * 0.15,
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
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ConfettiPainter(pieces: _pieces, t: _controller.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ConfettiPiece {
  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double spin;
  final double delay;

  const _ConfettiPiece({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.spin,
    required this.delay,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;
  final double t;

  const _ConfettiPainter({required this.pieces, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.35);
    for (final piece in pieces) {
      final local = ((t - piece.delay) / (1 - piece.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final eased = Curves.easeOutCubic.transform(local);
      final dx = math.cos(piece.angle) * piece.speed * eased;
      // Gravity pulls the arc downward as it progresses.
      final dy = math.sin(piece.angle) * piece.speed * eased +
          140 * eased * eased;
      final opacity = (1 - local).clamp(0.0, 1.0);

      final paint = Paint()..color = piece.color.withOpacity(opacity);
      canvas.save();
      canvas.translate(center.dx + dx, center.dy + dy);
      canvas.rotate(piece.spin * eased * math.pi);
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset.zero, width: piece.size, height: piece.size * 0.6),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.t != t;
}
