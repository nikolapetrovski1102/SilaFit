import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// How hot the streak fire burns.
enum StreakHeat { out, lit, hot, blazing }

/// The streak icon: a fire that lights up and burns hotter as the streak
/// grows.
///
/// | Streak      | Heat                  |
/// |-------------|-----------------------|
/// | 0 days      | [StreakHeat.out]      |
/// | 1-6 days    | [StreakHeat.lit]      |
/// | 7-29 days   | [StreakHeat.hot]      |
/// | 30+ days    | [StreakHeat.blazing]  |
///
/// Moving to a new stage pops the new fire in with a short scale animation.
class StreakFire extends StatelessWidget {
  final int streakDays;
  final double size;

  const StreakFire({super.key, required this.streakDays, required this.size});

  /// Streak length at which the fire runs hot ([StreakHeat.hot]).
  static const hotAt = 7;

  /// Streak length at which the fire is blazing ([StreakHeat.blazing]).
  static const blazingAt = 30;

  static StreakHeat heatFor(int streakDays) {
    if (streakDays <= 0) return StreakHeat.out;
    if (streakDays < hotAt) return StreakHeat.lit;
    if (streakDays < blazingAt) return StreakHeat.hot;
    return StreakHeat.blazing;
  }

  /// The streak length that unlocks the next stage, or null once the fire
  /// is already blazing.
  static int? nextStageAt(int streakDays) {
    if (streakDays < hotAt) return hotAt;
    if (streakDays < blazingAt) return blazingAt;
    return null;
  }

  // Top-to-bottom flame gradients: yellow tip into an orange/red base, each
  // stage a little hotter than the last.
  static const _lit = [Color(0xFFFFC94A), Color(0xFFFF8A1F), Color(0xFFF2621E)];
  static const _hot = [Color(0xFFFFE066), Color(0xFFFF7A1A), Color(0xFFE8401C)];
  static const _blazing = [
    Color(0xFFFFF3B0),
    Color(0xFFFFB627),
    Color(0xFFFF5A1F),
    Color(0xFFD62A1E),
  ];

  static double _scaleFor(StreakHeat heat) => switch (heat) {
        StreakHeat.out => 0.92,
        StreakHeat.lit => 1.0,
        StreakHeat.hot => 1.06,
        StreakHeat.blazing => 1.14,
      };

  Widget _fire(StreakHeat heat) {
    final iconSize = size * _scaleFor(heat);
    if (heat == StreakHeat.out) {
      return Icon(Icons.local_fire_department_outlined,
          key: ValueKey(heat),
          size: iconSize,
          color: AppColors.onSurfaceVariant);
    }
    final colors = switch (heat) {
      StreakHeat.lit => _lit,
      StreakHeat.hot => _hot,
      _ => _blazing,
    };
    final glow = switch (heat) {
      StreakHeat.lit => 0.0,
      StreakHeat.hot => 0.35,
      _ => 0.55,
    };
    return ShaderMask(
      key: ValueKey(heat),
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      ).createShader(bounds),
      child: Icon(
        Icons.local_fire_department_rounded,
        size: iconSize,
        color: Colors.white,
        shadows: glow == 0
            ? null
            : [
                Shadow(
                  color: const Color(0xFFFF7A1A).withValues(alpha: glow),
                  blurRadius: iconSize * 0.35,
                ),
              ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heat = heatFor(streakDays);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: OverflowBox(
          maxWidth: size * 1.2,
          maxHeight: size * 1.2,
          alignment: Alignment.bottomCenter,
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 420),
            switchInCurve: Curves.elasticOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
            child: _fire(heat),
          ),
        ),
      ),
    );
  }
}
