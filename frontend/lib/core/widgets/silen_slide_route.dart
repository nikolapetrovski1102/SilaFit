import 'package:flutter/material.dart';

/// Page transition mirroring [RegisterScreen]'s step-to-step motion: the
/// incoming screen slides in from the right over the outgoing one (no
/// parallax on the outgoing page), using the same easing/duration as the
/// register wizard's `AnimatedSwitcher` step transition.
class SilenSlideRoute<T> extends PageRouteBuilder<T> {
  SilenSlideRoute({required WidgetBuilder builder})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration: const Duration(milliseconds: 360),
          reverseTransitionDuration: const Duration(milliseconds: 280),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeIn,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            );
          },
        );
}
