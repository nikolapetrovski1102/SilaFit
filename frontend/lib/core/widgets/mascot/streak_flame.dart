import 'package:flutter/material.dart';

import 'flame_mascot.dart';

/// The streak icon: Sila's flame grows as the streak grows.
///
/// | Streak      | Art                |
/// |-------------|--------------------|
/// | 0 days      | [FlameArt.sleepy]  |
/// | 1-6 days    | [FlameArt.spark]   |
/// | 7-29 days   | [FlameArt.flame]   |
/// | 30+ days    | [FlameArt.blaze]   |
///
/// Moving to a new stage pops the new art in with a short scale animation.
class StreakFlame extends StatelessWidget {
  final int streakDays;
  final double size;

  const StreakFlame({super.key, required this.streakDays, required this.size});

  /// Streak length at which the flame grows into [FlameArt.flame].
  static const flameAt = 7;

  /// Streak length at which the flame grows into [FlameArt.blaze].
  static const blazeAt = 30;

  static FlameArt artFor(int streakDays) {
    if (streakDays <= 0) return FlameArt.sleepy;
    if (streakDays < flameAt) return FlameArt.spark;
    if (streakDays < blazeAt) return FlameArt.flame;
    return FlameArt.blaze;
  }

  /// The streak length that unlocks the next stage, or null once the flame
  /// is already a blaze.
  static int? nextStageAt(int streakDays) {
    if (streakDays < flameAt) return flameAt;
    if (streakDays < blazeAt) return blazeAt;
    return null;
  }

  // The blaze art is wider (its hands reach out), so its body renders
  // smaller inside the same square; scaling it up keeps the visual "growth"
  // reading correctly from spark to flame to blaze.
  static double _scaleFor(FlameArt art) => switch (art) {
        FlameArt.spark || FlameArt.sleepy => 0.9,
        FlameArt.blaze => 1.2,
        _ => 1.0,
      };

  @override
  Widget build(BuildContext context) {
    final art = artFor(streakDays);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      width: size,
      height: size,
      child: OverflowBox(
        maxWidth: size * 1.2,
        maxHeight: size * 1.2,
        alignment: Alignment.bottomCenter,
        child: AnimatedSwitcher(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 420),
          switchInCurve: Curves.elasticOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            alignment: Alignment.bottomCenter,
            child: child,
          ),
          child: FlameMascot(
            art,
            key: ValueKey(art),
            size: size * _scaleFor(art),
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}
