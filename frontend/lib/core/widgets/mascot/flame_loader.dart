import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'mascot_pose.dart';

/// Sila "on fire": the loading animation for the splash screen and any wait
/// long enough to deserve more than a spinner.
///
/// Built from layered art under `assets/mascot/flame/{dark,light}/loader_*`,
/// all on one shared 640x640 canvas with the body at the same spot, so the
/// layers stack without jitter:
///
/// - `loader_base`, `loader_flicker_b`: identical body,
///   different flame tips; quick crossfades between them read as flicker.
/// - `loader_blink`: swapped in for a beat every few seconds.
///
/// The rising embers are drawn in code; there is deliberately no glow or
/// back fire behind Sila. With reduce-motion on it
/// renders the still base pose.
class FlameLoader extends StatefulWidget {
  final double size;

  const FlameLoader({super.key, this.size = 160});

  @override
  State<FlameLoader> createState() => _FlameLoaderState();
}

/// Flip once the light-theme loader_* set is in assets/mascot/flame/light/.
const _hasLightSet = false;

String _asset(Brightness brightness, String name) {
  final theme =
      brightness == Brightness.light && _hasLightSet ? 'light' : 'dark';
  return 'assets/mascot/flame/$theme/loader_$name.png';
}

class _FlameLoaderState extends State<FlameLoader>
    with SingleTickerProviderStateMixin {
  /// Every motion below runs a whole number of times per [_loop], so the
  /// controller can simply repeat with no visible seam.
  static const _loop = Duration(milliseconds: 7200);

  late final AnimationController _c =
      AnimationController(vsync: this, duration: _loop)..repeat();

  static const _poses = ['base', 'flicker_b', 'base', 'flicker_b'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final b = Theme.of(context).brightness;
    for (final n in const ['base', 'flicker_b', 'blink']) {
      precacheImage(AssetImage(_asset(b, n)), context);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _img(String path, double opacity) => Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Image.asset(path,
            width: widget.size,
            height: widget.size,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium),
      );

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final size = widget.size;

    if (MediaQuery.disableAnimationsOf(context)) {
      return Semantics(
        label: '$mascotName is loading',
        child: _img(_asset(brightness, 'base'), 1),
      );
    }

    return Semantics(
      label: '$mascotName is loading',
      child: SizedBox.square(
        dimension: size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value; // 0..1 over 7.2s
            double wave(int cycles, [double phase = 0]) =>
                math.sin((t * cycles + phase) * 2 * math.pi);

            // Flicker: 8 cycles of 4 poses (225ms per pose), crossfading
            // over the last 40% of each slot.
            final slots = t * 8 * _poses.length;
            final slot = slots.floor() % _poses.length;
            final within = slots - slots.floor();
            final blend = ((within - 0.6) / 0.4).clamp(0.0, 1.0);
            final current = _poses[slot];
            final next = _poses[(slot + 1) % _poses.length];

            // Blink twice per loop, ~160ms each.
            final blinkPhase = (t * 2) % 1;
            final blinking = blinkPhase > 0.55 && blinkPhase < 0.572;

            // Breathing squash/stretch from the bottom edge.
            final breath = wave(4);

            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: Size.square(size),
                  painter: _EmberPainter(
                    t: t,
                    color: AppColors.accent,
                  ),
                ),
                Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.identity()
                    ..scaleByDouble(
                        1 - 0.015 * breath, 1 + 0.025 * breath, 1, 1),
                  child: blinking
                      ? _img(_asset(brightness, 'blink'), 1)
                      : Stack(children: [
                          _img(_asset(brightness, current), 1),
                          if (blend > 0 && next != current)
                            _img(_asset(brightness, next), blend),
                        ]),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Small sparks that leave the flame tips, drift sideways and fade out.
class _EmberPainter extends CustomPainter {
  final double t;
  final Color color;

  _EmberPainter({required this.t, required this.color});

  // (start x as fraction of width, horizontal drift, radius, phase offset,
  // cycles per loop). Cycles are whole numbers so the loop stays seamless.
  static const _embers = [
    (0.42, -0.08, 0.016, 0.00, 4),
    (0.55, 0.10, 0.012, 0.35, 4),
    (0.48, 0.04, 0.020, 0.62, 3),
    (0.60, 0.14, 0.010, 0.15, 5),
    (0.38, -0.12, 0.013, 0.80, 5),
    (0.52, -0.03, 0.009, 0.48, 6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final (x0, drift, r, phase, cycles) in _embers) {
      final p = (t * cycles + phase) % 1; // 0 = leaving the tips, 1 = gone
      final y = size.height * (0.30 - 0.32 * p);
      final x = size.width * (x0 + drift * p) +
          math.sin(p * math.pi * 3 + phase * 6) * size.width * 0.015;
      final fade = p < 0.15 ? p / 0.15 : (1 - p);
      final radius = size.width * r * (1 - 0.5 * p);
      paint
        ..color = color.withValues(alpha: 0.35 * fade)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 1.2);
      canvas.drawCircle(Offset(x, y), radius * 2, paint);
      paint
        ..color = color.withValues(alpha: 0.95 * fade)
        ..maskFilter = null;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_EmberPainter old) => old.t != t || old.color != color;
}
