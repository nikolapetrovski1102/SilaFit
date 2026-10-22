import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/silen_button.dart';

/// Plays the full-screen "you're in" moment after a verified purchase and
/// completes once the user taps through. [perks] are the plan's catalogue
/// features - the first few become the "now unlocked" list.
Future<void> showSubscriptionCelebration(
  BuildContext context, {
  required String planName,
  List<String> perks = const [],
}) {
  return Navigator.of(context).push(PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, __, ___) =>
        SubscriptionCelebration(planName: planName, perks: perks),
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  ));
}

/// The padlock every locked card in the app shows, opening for good: the
/// same `locked_lock` Lottie played backwards (frames 21 -> 0 lift the
/// shackle), then a burst into the tier badge with confetti, a shockwave
/// ring, and the perks that just unlocked ticking in one by one. Haptics
/// land on the unlock, the burst, and each perk.
///
/// One [_timeline] drives the whole choreography so every beat stays in
/// sync; [_burst] runs the confetti physics from the moment of unlock, and
/// [_ambient] loops the badge's glow, rays and title shimmer afterwards.
class SubscriptionCelebration extends StatefulWidget {
  final String planName;
  final List<String> perks;

  const SubscriptionCelebration(
      {super.key, required this.planName, this.perks = const []});

  @override
  State<SubscriptionCelebration> createState() =>
      _SubscriptionCelebrationState();
}

class _SubscriptionCelebrationState extends State<SubscriptionCelebration>
    with TickerProviderStateMixin {
  static const _maxPerks = 4;

  // Fractions of [_timeline]. The burst is the hinge everything else hangs
  // off: the lock is gone and the badge arrives exactly there.
  static const _unlockStart = 0.10;
  static const _burstAt = 0.30;
  static const _perksStart = 0.55;
  static const _perkStagger = 0.06;

  // The lock Lottie's shackle has settled shut by frame 21 of 50.
  static const _lockedFrame = 21 / 50;

  late final AnimationController _timeline;
  late final AnimationController _burst;
  late final AnimationController _ambient;
  late final List<_Confetti> _confetti;

  bool _clicked = false;
  bool _burst0 = false;
  int _perksBuzzed = 0;
  bool _reduceMotion = false;

  List<String> get _perks => widget.perks.take(_maxPerks).toList();

  @override
  void initState() {
    super.initState();
    _timeline = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3800))
      ..addListener(_onTick);
    _burst = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600));
    _ambient = AnimationController(
        vsync: this, duration: const Duration(seconds: 6));
    _confetti = _Confetti.spray(math.Random(), 120);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion == _reduceMotion && _timeline.isAnimating) return;
    _reduceMotion = reduceMotion;
    if (_reduceMotion) {
      // Land on the finished frame: the badge and perks, no motion. Flags
      // first - setting the value runs [_onTick].
      _clicked = _burst0 = true;
      _perksBuzzed = _perks.length;
      _timeline.value = 1;
      HapticFeedback.mediumImpact();
    } else if (_timeline.value == 0) {
      _timeline.forward();
    }
  }

  @override
  void dispose() {
    _timeline.dispose();
    _burst.dispose();
    _ambient.dispose();
    super.dispose();
  }

  void _onTick() {
    final t = _timeline.value;
    if (!_clicked && t >= _burstAt - 0.04) {
      _clicked = true;
      HapticFeedback.selectionClick();
    }
    if (!_burst0 && t >= _burstAt) {
      _burst0 = true;
      HapticFeedback.heavyImpact();
      _burst.forward();
      _ambient.repeat();
    }
    while (_perksBuzzed < _perks.length &&
        t >= _perksStart + _perksBuzzed * _perkStagger + 0.04) {
      _perksBuzzed++;
      HapticFeedback.lightImpact();
    }
  }

  /// [_timeline] eased across one beat of the choreography.
  double _beat(double start, double end, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(
          ((_timeline.value - start) / (end - start)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
        animation: Listenable.merge([_timeline, _burst, _ambient]),
        builder: (context, _) {
          final glow = _beat(_burstAt - 0.05, _burstAt + 0.25);
          return Stack(
            fit: StackFit.expand,
            children: [
              // The room lights up in the accent colour on the burst.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.42),
                    radius: 0.95,
                    colors: [
                      accent.withValues(alpha: 0.26 * glow),
                      accent.withValues(alpha: 0.06 * glow),
                      AppColors.background.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.45, 1],
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.marginMobile),
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      SizedBox(height: 210, child: _badgeStage(accent)),
                      const SizedBox(height: AppSpacing.md),
                      _headline(accent),
                      const SizedBox(height: AppSpacing.lg),
                      for (var i = 0; i < _perks.length; i++)
                        _perkRow(i, accent),
                      const Spacer(flex: 3),
                      _continueButton(),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _badgeStage(Color accent) {
    final lockIn = _beat(0, _unlockStart, Curves.easeOutBack);
    final unlock = _beat(_unlockStart, _burstAt - 0.02, Curves.easeInOutCubic);
    final lockOut = _beat(_burstAt, _burstAt + 0.08, Curves.easeIn);
    final badgeIn = _beat(_burstAt, _burstAt + 0.22, Curves.elasticOut);
    final pulse = 0.5 + 0.5 * math.sin(_ambient.value * 2 * math.pi * 2);

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Slow-turning light rays behind the badge.
        if (badgeIn > 0)
          Opacity(
            opacity: (badgeIn * 0.9).clamp(0.0, 1.0),
            child: CustomPaint(
              size: const Size.square(320),
              painter: _RaysPainter(
                  color: accent, turn: _ambient.value, intensity: 0.7 + 0.3 * pulse),
            ),
          ),
        // Confetti and the shockwave ring, painted from the badge's centre
        // and allowed to spill across the whole screen.
        CustomPaint(
          size: const Size.square(1),
          painter: _BurstPainter(
            confetti: _confetti,
            elapsed: _burst.value * _burst.duration!.inMilliseconds / 1000,
            progress: _burst.value,
            ringColor: accent,
            palette: [
              accent,
              AppColors.secondary,
              AppColors.tertiaryContainer,
              const Color(0xFFF7D774),
              AppColors.onSurface,
            ],
          ),
        ),
        // The padlock, opening.
        if (lockOut < 1)
          Opacity(
            opacity: (lockIn * (1 - lockOut)).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: (0.6 + 0.4 * lockIn) * (1 + 0.35 * lockOut),
              child: Container(
                width: 128,
                height: 128,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceContainerHigh,
                  border: Border.all(
                      color: accent.withValues(alpha: 0.35 + 0.4 * unlock),
                      width: 2),
                ),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
                  child: Lottie.asset(
                    'assets/lottie_animations/locked_lock.json',
                    fit: BoxFit.contain,
                    controller: AlwaysStoppedAnimation(
                        _lockedFrame * (1 - unlock)),
                  ),
                ),
              ),
            ),
          ),
        // The tier badge.
        if (badgeIn > 0)
          Transform.scale(
            scale: 0.35 + 0.65 * badgeIn,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(accent, Colors.white, 0.25)!,
                    accent,
                    Color.lerp(accent, Colors.black, 0.18)!,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35 + 0.25 * pulse),
                    blurRadius: 36 + 18 * pulse,
                    spreadRadius: 2 + 4 * pulse,
                  ),
                ],
              ),
              child: Icon(Icons.workspace_premium_rounded,
                  size: 68, color: AppColors.onAccent),
            ),
          ),
      ],
    );
  }

  Widget _headline(Color accent) {
    final reveal = _beat(_burstAt + 0.10, _burstAt + 0.30);
    final shimmer = _ambient.value;
    return Opacity(
      opacity: reveal,
      child: Transform.translate(
        offset: Offset(0, 18 * (1 - reveal)),
        child: Column(
          children: [
            Text('WELCOME TO',
                style: AppTypography.labelCaps
                    .copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 6),
            // A band of light sweeps across the plan name every loop.
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  AppColors.onSurface,
                  accent,
                  AppColors.onSurface,
                ],
                stops: [
                  (shimmer * 1.6 - 0.45).clamp(0.0, 1.0),
                  (shimmer * 1.6 - 0.3).clamp(0.0, 1.0),
                  (shimmer * 1.6 - 0.15).clamp(0.0, 1.0),
                ],
              ).createShader(bounds),
              child: Text(
                'SilaFit ${widget.planName}',
                textAlign: TextAlign.center,
                style: AppTypography.headlineLg.copyWith(fontSize: 34),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Everything is unlocked. Let\'s make it count.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMd
                  .copyWith(color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _perkRow(int index, Color accent) {
    final start = _perksStart + index * _perkStagger;
    final reveal = _beat(start, start + 0.12);
    final tick = _beat(start + 0.03, start + 0.15, Curves.elasticOut);
    return Opacity(
      opacity: reveal,
      child: Transform.translate(
        offset: Offset(24 * (1 - reveal), 0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Transform.scale(
                scale: tick,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded,
                      size: 16, color: AppColors.onAccent),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(_perks[index],
                    style: AppTypography.bodyMd
                        .copyWith(color: AppColors.onSurface)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _continueButton() {
    final reveal = _beat(0.86, 1);
    return IgnorePointer(
      ignoring: reveal < 0.5,
      child: Opacity(
        opacity: reveal,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - reveal)),
          child: PrimaryPillButton(
            label: 'Let\'s go',
            icon: Icons.arrow_forward_rounded,
            height: 52,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

/// One piece of confetti's launch parameters. Positions are derived on the
/// fly from elapsed time, so the painter holds no per-frame state.
class _Confetti {
  final double vx;
  final double vy;
  final double size;
  final double spin;
  final double phase;
  final int colorIndex;
  final bool isRibbon;
  final double life;

  const _Confetti(this.vx, this.vy, this.size, this.spin, this.phase,
      this.colorIndex, this.isRibbon, this.life);

  /// A fountain: mostly upward, fanned wide, at mixed speeds so the cloud
  /// has depth instead of moving as one ring.
  static List<_Confetti> spray(math.Random rng, int count) {
    return List.generate(count, (_) {
      final angle = -math.pi / 2 + (rng.nextDouble() - 0.5) * 2.4;
      final speed = 420 + rng.nextDouble() * 680;
      return _Confetti(
        math.cos(angle) * speed,
        math.sin(angle) * speed,
        5 + rng.nextDouble() * 6,
        (rng.nextDouble() - 0.5) * 18,
        rng.nextDouble() * math.pi * 2,
        rng.nextInt(5),
        rng.nextDouble() < 0.45,
        1.8 + rng.nextDouble() * 0.8,
      );
    });
  }
}

class _BurstPainter extends CustomPainter {
  final List<_Confetti> confetti;
  final double elapsed;
  final double progress;
  final Color ringColor;
  final List<Color> palette;

  static const _drag = 1.7;
  static const _gravity = 980.0;

  _BurstPainter({
    required this.confetti,
    required this.elapsed,
    required this.progress,
    required this.ringColor,
    required this.palette,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final centre = size.center(Offset.zero);

    // Shockwave: one ring racing outwards over the first ~0.7s.
    final ring = (elapsed / 0.7).clamp(0.0, 1.0);
    if (ring < 1) {
      final eased = Curves.easeOutCubic.transform(ring);
      canvas.drawCircle(
        centre,
        66 + 220 * eased,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - eased) + 0.5
          ..color = ringColor.withValues(alpha: 0.8 * (1 - eased)),
      );
    }

    // Linear drag with gravity, solved in closed form so any frame can be
    // painted directly from elapsed time.
    final decay = (1 - math.exp(-_drag * elapsed)) / _drag;
    final paint = Paint();
    for (final c in confetti) {
      if (elapsed > c.life) continue;
      final x = c.vx * decay;
      final y = c.vy * decay +
          _gravity / _drag * (elapsed - decay);
      final fade = ((c.life - elapsed) / 0.5).clamp(0.0, 1.0);
      paint.color = palette[c.colorIndex].withValues(alpha: fade);
      final angle = c.phase + c.spin * elapsed;

      canvas.save();
      canvas.translate(centre.dx + x, centre.dy + y);
      canvas.rotate(angle);
      if (c.isRibbon) {
        // Squash one axis with the spin so ribbons seem to flip in 3D.
        final flip = math.cos(angle * 1.7).abs() * 0.85 + 0.15;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero,
                width: c.size * 0.55,
                height: c.size * 1.7 * flip),
            const Radius.circular(1.5),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, c.size * 0.42, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.elapsed != elapsed || old.ringColor != ringColor;
}

class _RaysPainter extends CustomPainter {
  final Color color;
  final double turn;
  final double intensity;

  static const _rays = 12;

  _RaysPainter(
      {required this.color, required this.turn, required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final shader = RadialGradient(
      colors: [
        color.withValues(alpha: 0.30 * intensity),
        color.withValues(alpha: 0),
      ],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    final paint = Paint()..shader = shader;

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(turn * 2 * math.pi / 3);
    const sweep = math.pi / _rays * 0.55;
    for (var i = 0; i < _rays; i++) {
      final a = i * 2 * math.pi / _rays;
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(math.cos(a - sweep) * radius, math.sin(a - sweep) * radius)
        ..lineTo(math.cos(a + sweep) * radius, math.sin(a + sweep) * radius)
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RaysPainter old) =>
      old.turn != turn || old.intensity != intensity || old.color != color;
}
