import 'package:flutter/material.dart';

import 'ram_mascot.dart';

/// The streak icon: Sila wakes up and gets fired up as the streak grows.
///
/// | Streak      | Art                   |
/// |-------------|-----------------------|
/// | 0 days      | [RamArt.sleepy]       |
/// | 1-6 days    | [RamArt.smug]         |
/// | 7-29 days   | [RamArt.determined]   |
/// | 30+ days    | [RamArt.emblem]       |
///
/// Moving to a new stage pops the new art in with a short scale animation.
class StreakRam extends StatelessWidget {
  final int streakDays;
  final double size;

  const StreakRam({super.key, required this.streakDays, required this.size});

  /// Streak length at which Sila gets locked in ([RamArt.determined]).
  static const lockedInAt = 7;

  /// Streak length at which Sila becomes the champion ([RamArt.emblem]).
  static const championAt = 30;

  static RamArt artFor(int streakDays) {
    if (streakDays <= 0) return RamArt.sleepy;
    if (streakDays < lockedInAt) return RamArt.smug;
    if (streakDays < championAt) return RamArt.determined;
    return RamArt.emblem;
  }

  /// The streak length that unlocks the next stage, or null once Sila is
  /// already the champion.
  static int? nextStageAt(int streakDays) {
    if (streakDays < lockedInAt) return lockedInAt;
    if (streakDays < championAt) return championAt;
    return null;
  }

  // The emblem is the bigger, icon-style head, so it gets a little extra
  // size to read as the top stage.
  static double _scaleFor(RamArt art) => art == RamArt.emblem ? 1.15 : 1.0;

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
          child: RamMascot(
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
