import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import 'confetti_burst.dart';
import 'ram_mascot.dart';

/// Sila celebrating: a short, choreographed routine for big moments like a
/// finished workout or a streak milestone.
///
/// 1. Sila crouches to wind up.
/// 2. Sila leaps and does a full turn in the air. The back-view art is shown
///    while Sila faces away, so the spin looks three-dimensional.
/// 3. Sila lands with a squash and throws a fist pump (the charging pose).
///    Confetti fires, a shock ring spreads across the floor and light rays
///    fade in behind.
/// 4. Sila pops back to standing and keeps breathing while the rays turn.
///
/// Tapping Sila plays the routine again. With reduced motion turned on, Sila
/// stands still in front of the glow, with no confetti and no haptics.
class CelebratingRam extends StatefulWidget {
  /// Height of the ram itself. The stage around it is wider and taller, to
  /// leave room for the leap and the rays.
  final double size;

  /// Called when Sila lands, the loudest beat of the routine.
  final VoidCallback? onLanded;

  /// Light haptic feedback on the crouch and a heavier one on landing.
  final bool haptics;

  const CelebratingRam({
    super.key,
    this.size = 150,
    this.onLanded,
    this.haptics = true,
  });

  /// The stage size for a ram of [size].
  static Size stageFor(double size) => Size(size * 1.6, size * 1.42);

  @override
  State<CelebratingRam> createState() => _CelebratingRamState();
}

class _CelebratingRamState extends State<CelebratingRam>
    with TickerProviderStateMixin {
  // Beats of the routine, as fractions of [_routine].
  static const _crouchEnd = 0.10;
  static const _land = 0.40;
  static const _settle = 0.84;

  late final AnimationController _routine = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600))
    ..addListener(_onTick);

  // Keeps running after the routine: turns the rays and drives the breath.
  late final AnimationController _ambient = AnimationController(
      vsync: this, duration: const Duration(seconds: 12));

  Timer? _startTimer;
  bool _reduceMotion = false;
  bool _started = false;
  bool _landed = false;
  bool _wound = false;
  int _burst = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    for (final art in const [RamArt.standing, RamArt.charging, RamArt.back]) {
      precacheImage(AssetImage(art.assetPath), context);
    }
    if (_reduceMotion) {
      _routine.value = 1;
      _ambient.stop();
    } else if (!_started) {
      _started = true;
      _ambient.repeat();
      // A beat after the dialog lands, so the leap isn't lost in its entrance.
      _startTimer = Timer(const Duration(milliseconds: 220), _play);
    }
  }

  void _play() {
    if (_reduceMotion || _routine.isAnimating) return;
    _landed = false;
    _wound = false;
    _routine.forward(from: 0);
  }

  void _onTick() {
    final t = _routine.value;
    if (!_wound && t > 0.02) {
      _wound = true;
      if (widget.haptics) HapticFeedback.selectionClick();
    }
    if (!_landed && t >= _land) {
      _landed = true;
      if (widget.haptics) HapticFeedback.heavyImpact();
      widget.onLanded?.call();
      setState(() => _burst++);
    }
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _routine.dispose();
    _ambient.dispose();
    super.dispose();
  }

  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final stage = CelebratingRam.stageFor(size);
    final floor = size * 0.06; // gap under the feet for the shadow

    return Semantics(
      label: '$mascotName is celebrating',
      image: true,
      child: GestureDetector(
        onTap: _play,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.fromSize(
          size: stage,
          child: AnimatedBuilder(
            animation: Listenable.merge([_routine, _ambient]),
            builder: (context, _) {
              final t = _routine.value;
              final a = _ambient.value;
              final m = _Motion.at(t, a, size, _reduceMotion);
              final chest = Offset(stage.width / 2,
                  stage.height - floor - size * 0.55 + m.lift);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Rays and glow behind Sila.
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RaysPainter(
                        center: chest,
                        radius: size * 0.9,
                        rotation: a * math.pi * 2,
                        intensity: m.rays,
                        glow: m.glow,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  // Contact shadow and the landing shock ring.
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _FloorPainter(
                        center: Offset(stage.width / 2, stage.height - floor),
                        width: size * 0.56,
                        shadow: m.shadow,
                        ring: m.ring,
                        ringColor: AppColors.accent,
                      ),
                    ),
                  ),
                  // Sila.
                  Positioned(
                    left: (stage.width - size) / 2,
                    bottom: floor,
                    width: size,
                    height: size,
                    child: Transform(
                      alignment: Alignment.bottomCenter,
                      transform: Matrix4.identity()
                        ..translateByDouble(m.shake, m.lift, 0.0, 1.0)
                        ..setEntry(3, 2, 0.0014)
                        ..rotateY(m.spin)
                        ..rotateZ(m.tilt)
                        ..scaleByDouble(m.scaleX, m.scaleY, 1.0, 1.0),
                      // All three poses stay built, so swapping them never
                      // waits on an image decode.
                      child: IndexedStack(
                        index: m.art.index,
                        children: [
                          for (final art in _Pose.values)
                            RamMascot(art.ram,
                                size: size, excludeFromSemantics: true),
                        ],
                      ),
                    ),
                  ),
                  if (_burst > 0 && !_reduceMotion)
                    Positioned.fill(
                      child: ConfettiBurst(
                        key: ValueKey(_burst),
                        // Fired from just over Sila's horns, so it rains
                        // down around Sila instead of across the face.
                        origin: Alignment(
                          0,
                          ((stage.height - floor - size * 1.02) /
                                  stage.height) *
                                  2 -
                              1,
                        ),
                        power: size * 1.5,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _Pose {
  standing(RamArt.standing),
  charging(RamArt.charging),
  back(RamArt.back);

  final RamArt ram;
  const _Pose(this.ram);
}

/// Everything about Sila's body at one instant of the routine.
class _Motion {
  final _Pose art;
  final double lift; // negative is up
  final double shake;
  final double spin;
  final double tilt;
  final double scaleX;
  final double scaleY;
  final double shadow; // 0..1 strength of the contact shadow
  final double ring; // 0..1 progress of the shock ring, 0 = none
  final double rays; // 0..1
  final double glow; // 0..1

  const _Motion({
    required this.art,
    required this.lift,
    required this.shake,
    required this.spin,
    required this.tilt,
    required this.scaleX,
    required this.scaleY,
    required this.shadow,
    required this.ring,
    required this.rays,
    required this.glow,
  });

  static double _seg(double t, double a, double b) =>
      _CelebratingRamState._seg(t, a, b);

  factory _Motion.at(double t, double a, double size, bool still) {
    const crouchEnd = _CelebratingRamState._crouchEnd;
    const land = _CelebratingRamState._land;
    const settle = _CelebratingRamState._settle;
    final breath = math.sin(a * math.pi * 2 * 4); // a 3s breath

    if (still) {
      return const _Motion(
        art: _Pose.standing,
        lift: 0,
        shake: 0,
        spin: 0,
        tilt: 0,
        scaleX: 1,
        scaleY: 1,
        shadow: 1,
        ring: 0,
        rays: 0.45,
        glow: 0.8,
      );
    }

    var art = _Pose.standing;
    var lift = 0.0, shake = 0.0, spin = 0.0, tilt = 0.0;
    var sx = 1.0, sy = 1.0;

    if (t < crouchEnd) {
      // Wind up: sink and widen.
      final c = Curves.easeOutCubic.transform(_seg(t, 0, crouchEnd));
      sy = 1 - 0.14 * c;
      sx = 1 + 0.10 * c;
    } else if (t < land) {
      // Airborne: a parabola, stretched on the way up and the way down.
      final p = _seg(t, crouchEnd, land);
      lift = -size * 0.34 * 4 * p * (1 - p);
      final stretch = p < 0.5 ? 0.13 * (1 - p * 2) : 0.07 * (p - 0.5) * 2;
      sy = 1 + stretch;
      sx = 1 - stretch * 0.6;
      tilt = -0.07 * math.sin(p * math.pi);
      // One full turn, eased so it whips through the back view.
      spin = math.pi *
          2 *
          Curves.easeInOutCubic.transform(_seg(t, crouchEnd + 0.03, land - 0.03));
      if (math.cos(spin) < 0) art = _Pose.back;
    } else {
      art = t < settle ? _Pose.charging : _Pose.standing;
      // Landing: a damped squash-and-stretch spring.
      final q = _seg(t, land, land + 0.26);
      final s = 0.17 * math.exp(-4.5 * q) * math.cos(q * math.pi * 2.6);
      sy = 1 - s;
      sx = 1 + s * 0.7;
      // The fist pump shudders as it lands.
      final k = _seg(t, land, land + 0.2);
      shake = math.sin(k * math.pi * 6) * size * 0.012 * (1 - k);
      if (t >= settle) {
        // Pop back to standing.
        final r = _seg(t, settle, 1);
        final pop = 0.07 * math.exp(-4 * r) * math.sin(r * math.pi * 2.5);
        sy = 1 + pop;
        sx = 1 - pop * 0.6;
      }
      if (t >= 1) {
        sy = 1 + 0.016 * breath;
        sx = 1 - 0.008 * breath;
      }
    }

    final air = (-lift / (size * 0.34)).clamp(0.0, 1.0);
    final afterLand = _seg(t, land - 0.02, land + 0.12);
    return _Motion(
      art: art,
      lift: lift,
      shake: shake,
      spin: spin,
      tilt: tilt,
      scaleX: sx,
      scaleY: sy,
      shadow: 1 - 0.6 * air,
      ring: t >= land && t < land + 0.24 ? _seg(t, land, land + 0.24) : 0,
      rays: Curves.easeOut.transform(afterLand) * (0.85 - 0.25 * _seg(t, 0.7, 1)),
      glow: 0.35 +
          0.5 * Curves.easeOut.transform(afterLand) +
          0.08 * breath * _seg(t, 0.9, 1),
    );
  }
}

class _RaysPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final double rotation;
  final double intensity;
  final double glow;
  final Color color;

  const _RaysPainter({
    required this.center,
    required this.radius,
    required this.rotation,
    required this.intensity,
    required this.glow,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromCircle(center: center, radius: radius);

    if (glow > 0) {
      canvas.drawCircle(
        center,
        radius * 0.78,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: 0.42 * glow),
            color.withValues(alpha: 0.12 * glow),
            color.withValues(alpha: 0),
          ], stops: const [0, 0.45, 1])
              .createShader(Rect.fromCircle(center: center, radius: radius * 0.78)),
      );
    }

    if (intensity <= 0) return;
    const count = 14;
    const half = 0.085; // half the angular width of each ray
    final paint = Paint()
      ..shader = RadialGradient(colors: [
        color.withValues(alpha: 0.38 * intensity),
        color.withValues(alpha: 0.14 * intensity),
        color.withValues(alpha: 0),
      ], stops: const [0.15, 0.55, 1])
          .createShader(bounds)
      ..blendMode = BlendMode.plus;
    for (var i = 0; i < count; i++) {
      // Alternate long and short rays for a less mechanical burst.
      final r = radius * (i.isEven ? 1.0 : 0.72);
      final angle = rotation + i * math.pi * 2 / count;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + math.cos(angle - half) * r,
            center.dy + math.sin(angle - half) * r)
        ..lineTo(center.dx + math.cos(angle + half) * r,
            center.dy + math.sin(angle + half) * r)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) =>
      old.center != center ||
      old.rotation != rotation ||
      old.intensity != intensity ||
      old.glow != glow ||
      old.color != color;
}

class _FloorPainter extends CustomPainter {
  final Offset center;
  final double width;
  final double shadow;
  final double ring;
  final Color ringColor;

  const _FloorPainter({
    required this.center,
    required this.width,
    required this.shadow,
    required this.ring,
    required this.ringColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = width * (0.55 + 0.45 * shadow);
    final rect = Rect.fromCenter(center: center, width: w, height: w * 0.16);
    // A blurred oval: a RadialGradient would stay circular inside the
    // flat rect and shrink to a dot.
    canvas.drawOval(
      rect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.42 * shadow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.05),
    );

    if (ring > 0 && ring < 1) {
      final e = Curves.easeOutCubic.transform(ring);
      final rw = width * (0.5 + 1.5 * e);
      canvas.drawOval(
        Rect.fromCenter(center: center, width: rw, height: rw * 0.22),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - e) + 0.5
          ..color = ringColor.withValues(alpha: 0.8 * (1 - e)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FloorPainter old) =>
      old.shadow != shadow || old.ring != ring || old.width != width;
}
