import 'package:flutter/material.dart';

import 'scribble_reveal.dart';

/// The app's mascot is Sila the ram. Used as the `semanticLabel` on every
/// mascot image so screen readers announce something meaningful instead of
/// skipping a purely decorative-looking image.
const mascotName = 'Sila';

/// Every piece of art in the Sila ram set, under `assets/mascot/ram/`.
/// The art has no sticker border: the dark ink outline is the edge, so one
/// set reads on both the light and the dark theme.
///
/// - [standing], [charging]: full-body poses for dialogs, toasts and heroes.
/// - [back]: the full body from behind.
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
///
/// With [scribbleIn], Sila is revealed by a graffiti scrub ([ScribbleReveal])
/// once the image has loaded, then stays still. This is how Sila arrives in
/// dialogs, toasts and speech bubbles: no hops, bobs or bounces.
class RamMascot extends StatelessWidget {
  final RamArt art;
  final double size;

  /// Reveal Sila with the zigzag marker scrub instead of showing it at once.
  final bool scribbleIn;

  /// Wait before the scrub starts (only with [scribbleIn]).
  final Duration scribbleDelay;

  /// Fires once Sila is fully revealed (only with [scribbleIn]).
  final VoidCallback? onRevealed;

  /// Set this when nearby text already says what the image means (for
  /// example the streak count), so screen readers don't announce "Sila"
  /// twice.
  final bool excludeFromSemantics;

  const RamMascot(
    this.art, {
    super.key,
    required this.size,
    this.excludeFromSemantics = false,
    this.scribbleIn = false,
    this.scribbleDelay = Duration.zero,
    this.onRevealed,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      art.assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      // The art is 512-1024px but shown at ~100-200 logical px; decoding at
      // display size instead of full size saves 1-4MB per pose.
      cacheWidth: size.isFinite
          ? (size * MediaQuery.devicePixelRatioOf(context)).ceil()
          : null,
      filterQuality: FilterQuality.medium,
      semanticLabel: excludeFromSemantics ? null : mascotName,
      excludeFromSemantics: excludeFromSemantics,
      gaplessPlayback: true,
      // Start the scrub only once the art is decoded, so the marker never
      // sweeps over an empty box.
      frameBuilder: scribbleIn
          ? (context, child, frame, wasSynchronouslyLoaded) => frame == null
              ? SizedBox.square(dimension: size)
              : ScribbleReveal(
                  delay: scribbleDelay,
                  onRevealed: onRevealed,
                  child: child,
                )
          : null,
    );
  }
}
