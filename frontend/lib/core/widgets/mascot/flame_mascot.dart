import 'package:flutter/material.dart';

import 'mascot_pose.dart';

/// Every piece of art in the "Sila" flame-spirit set. Each one ships as a
/// light and a dark variant under `assets/mascot/flame/{light,dark}/`:
/// burgundy and mustard on cream for light mode, and soft lime on teal for
/// dark mode, matching [AppPalette].
///
/// - [spark], [flame], [blaze]: the three growth stages, used for streaks.
/// - [determined], [laughing], [smug], [sleepy], [shocked]: expressions.
enum FlameArt {
  spark,
  flame,
  blaze,
  determined,
  laughing,
  smug,
  sleepy,
  shocked,
}

extension FlameArtAsset on FlameArt {
  String assetPathFor(Brightness brightness) {
    final theme = brightness == Brightness.dark ? 'dark' : 'light';
    return 'assets/mascot/flame/$theme/$name.png';
  }
}

/// Renders one [FlameArt] in the variant that matches the ambient theme.
/// The art is square with the flame resting on the bottom edge, so
/// differently sized flames placed side by side share a baseline.
class FlameMascot extends StatelessWidget {
  final FlameArt art;
  final double size;

  /// Set this when nearby text already says what the image means (for
  /// example the streak count), so screen readers don't announce "Silen"
  /// twice.
  final bool excludeFromSemantics;

  const FlameMascot(
    this.art, {
    super.key,
    required this.size,
    this.excludeFromSemantics = false,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      art.assetPathFor(Theme.of(context).brightness),
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: excludeFromSemantics ? null : mascotName,
      excludeFromSemantics: excludeFromSemantics,
      gaplessPlayback: true,
    );
  }
}
