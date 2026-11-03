import 'package:flutter/material.dart';

/// The app's mascot is Sila the ram. Used as the `semanticLabel` on every
/// mascot image so screen readers announce something meaningful instead of
/// skipping a purely decorative-looking image.
const mascotName = 'Sila';

/// Every piece of art in the Sila ram set, under `assets/mascot/ram/`.
/// The art has no sticker border: the dark ink outline is the edge, so one
/// set reads on both the light and the dark theme.
///
/// - [standing], [charging]: full-body poses for dialogs, toasts and heroes.
/// - [back]: the full body from behind. `CelebratingRam` shows it mid-spin.
/// - [emblem]: a front-facing head for small spots like the streak chip.
/// - [determined], [laughing], [smug], [sleepy], [shocked]: expressions.
enum RamArt {
  standing,
  charging,
  back,
  emblem,
  determined,
  laughing,
  smug,
  sleepy,
  shocked,
}

extension RamArtAsset on RamArt {
  String get assetPath => 'assets/mascot/ram/$name.png';
}

/// Renders one [RamArt]. Every image is square with the art resting on the
/// bottom edge, so differently sized pieces placed side by side share a
/// baseline.
class RamMascot extends StatelessWidget {
  final RamArt art;
  final double size;

  /// Set this when nearby text already says what the image means (for
  /// example the streak count), so screen readers don't announce "Sila"
  /// twice.
  final bool excludeFromSemantics;

  const RamMascot(
    this.art, {
    super.key,
    required this.size,
    this.excludeFromSemantics = false,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      art.assetPath,
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
