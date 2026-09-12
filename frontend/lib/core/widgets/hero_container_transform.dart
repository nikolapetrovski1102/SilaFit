import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Hand-rolled "container transform": a tapped element's Hero grows to
/// become part of the new screen, crossfading its own content into the
/// destination's differently-shaped content along the way, and the rest of
/// the destination screen reveals only afterwards rather than all popping
/// in at once. Deliberately hand-rolled rather than pulling in the
/// `animations` package's OpenContainer for this - see the fl_chart comment
/// in pubspec.yaml for this codebase's bar for reaching for a package
/// instead: a large, bug-prone undertaking to hand-roll. A Hero plus a
/// couple of Tweens isn't that.
///
/// Used by the split card -> split detail transition (`splits_screen.dart`
/// / `split_detail_screen.dart`) and the Home "Active split" row -> split
/// library transition (`active_split_card.dart` / `splits_screen.dart`).

/// Pushes [builder] with a container-transform feel: long enough for the
/// Hero flight to read as motion rather than a blink, and a
/// [PageRouteBuilder.transitionsBuilder] that only fades in the destination
/// screen's chrome - the actual grow-and-morph is the Hero flight itself,
/// which the framework runs in the [Overlay] independently of this
/// transitionsBuilder.
Route<T> heroExpandRoute<T>({
  required WidgetBuilder builder,
  Duration transitionDuration = const Duration(milliseconds: 380),
  Duration reverseTransitionDuration = const Duration(milliseconds: 280),
}) {
  return PageRouteBuilder<T>(
    transitionDuration: transitionDuration,
    reverseTransitionDuration: reverseTransitionDuration,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity:
            CurvedAnimation(parent: animation, curve: const Interval(0, 0.5)),
        child: child,
      );
    },
  );
}

/// A straight-line [RectTween] for a Hero's [Hero.createRectTween], instead
/// of the Navigator's default [MaterialRectArcTween] - a card "expanding"
/// in place should grow, not arc across the screen.
Tween<Rect?> straightHeroRectTween(Rect? begin, Rect? end) =>
    RectTween(begin: begin, end: end);

/// A [Hero.flightShuttleBuilder] that crossfades the "from" Hero's child
/// into the "to" Hero's child, instead of Hero's default of hard-swapping
/// to the destination child for the whole flight - for pairs (like a
/// compact card and a plain destination image, or a row and a header) that
/// don't look alike.
///
/// [animation] runs 0 -> 1 from the "from" Hero to the "to" Hero regardless
/// of push/pop, so a plain linear crossfade reads correctly in both
/// directions. [borderRadius] clips both layers - it isn't itself animated
/// between two shapes, since every screen in this app already shares
/// `AppRadius.card`.
Widget crossfadeHeroShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext, {
  BorderRadius? borderRadius,
}) {
  final fromChild = (fromHeroContext.widget as Hero).child;
  final toChild = (toHeroContext.widget as Hero).child;

  // The two ends rarely share an aspect ratio or intrinsic height, and the
  // flight box is tweened between their two rects - so each layer needs to
  // keep laying itself out naturally (OverflowBox) rather than being
  // squashed into a box it doesn't fit, with ClipRect trimming whatever
  // spills past the current box.
  Widget layer(Widget child) => Positioned.fill(
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: double.infinity,
            child: child,
          ),
        ),
      );

  return ClipRRect(
    borderRadius: borderRadius ?? BorderRadius.circular(AppRadius.card),
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Stack(
        children: [
          layer(Opacity(opacity: 1 - animation.value, child: fromChild)),
          layer(Opacity(opacity: animation.value, child: toChild)),
        ],
      ),
    ),
  );
}

/// Wraps [child] so it fades + rises in only after the enclosing route's
/// Hero flight has mostly finished growing (the first [startAt] fraction of
/// the transition is left entirely to the Hero), instead of the
/// destination's own content just being there the instant the route is
/// pushed. That delay is what actually reads as the expanded Hero
/// "revealing" this content, rather than a screen that merely opened on top
/// of it.
class HeroExpandReveal extends StatelessWidget {
  final Widget child;
  final double startAt;

  const HeroExpandReveal({super.key, required this.child, this.startAt = 0.35});

  @override
  Widget build(BuildContext context) {
    // Falls back to an always-complete animation so the content still shows
    // normally if this is ever built without an enclosing route (e.g. a
    // widget test).
    final routeAnimation =
        ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    final reveal = CurvedAnimation(
      parent: routeAnimation,
      curve: Interval(startAt, 1.0, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: reveal,
      child: SlideTransition(
        position:
            reveal.drive(Tween(begin: const Offset(0, 0.06), end: Offset.zero)),
        child: child,
      ),
    );
  }
}
