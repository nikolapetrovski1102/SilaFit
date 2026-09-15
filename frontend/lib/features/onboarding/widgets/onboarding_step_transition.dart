import 'package:flutter/material.dart';

/// Supplies the route-like transition animation for the currently changing
/// onboarding step. The page itself slides horizontally; descendants opt in
/// to the softer fade/fall treatment with [OnboardingStepContentTransition].
class OnboardingStepTransitionScope
    extends InheritedNotifier<Animation<double>> {
  const OnboardingStepTransitionScope({
    super.key,
    required Animation<double> animation,
    required super.child,
  }) : super(notifier: animation);

  static Animation<double>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<OnboardingStepTransitionScope>()
      ?.notifier;
}

/// Applies motion only to a screen's meaningful content. Navigation chrome,
/// the background and the bottom CTA remain solid while the whole page uses
/// the standard horizontal slide supplied by the flow.
class OnboardingStepContentTransition extends StatelessWidget {
  final Widget child;
  final double incomingOffset;
  final double outgoingOffset;

  const OnboardingStepContentTransition({
    super.key,
    required this.child,
    this.incomingOffset = 18,
    this.outgoingOffset = 28,
  });

  @override
  Widget build(BuildContext context) {
    final animation = OnboardingStepTransitionScope.maybeOf(context);
    if (animation == null || MediaQuery.disableAnimationsOf(context)) {
      return child;
    }

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final progress = animation.value.clamp(0.0, 1.0);
        final isLeaving = animation.status == AnimationStatus.reverse;
        final distance = isLeaving ? outgoingOffset : incomingOffset;
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, distance * (1 - progress)),
            child: child,
          ),
        );
      },
    );
  }
}
