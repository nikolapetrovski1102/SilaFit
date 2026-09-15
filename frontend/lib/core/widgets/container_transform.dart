import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import 'swipe_down_to_close.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A shared card/button-to-screen morph, including the return transition.
class ContainerTransform extends StatelessWidget {
  final Widget Function(BuildContext, VoidCallback) closedBuilder;
  final WidgetBuilder openBuilder;
  final VoidCallback? onClosed;
  final Color? closedColor;
  final double radius;

  const ContainerTransform({
    super.key,
    required this.closedBuilder,
    required this.openBuilder,
    this.onClosed,
    this.closedColor,
    this.radius = AppRadius.card,
  });

  @override
  Widget build(BuildContext context) {
    // OpenContainer relies on animation status changes to restore its source.
    // A zero-duration route avoids that lifecycle for reduced motion.
    if (MediaQuery.disableAnimationsOf(context)) {
      return closedBuilder(context, () async {
        await Navigator.of(context).push<void>(PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, _, __) =>
              SwipeDownToClose(child: openBuilder(context)),
        ));
        onClosed?.call();
      });
    }
    return OpenContainer<void>(
      transitionDuration: const Duration(milliseconds: 450),
      transitionType: ContainerTransitionType.fade,
      closedElevation: 0,
      openElevation: 0,
      closedColor: closedColor ?? AppColors.surfaceContainer,
      openColor: Theme.of(context).scaffoldBackgroundColor,
      middleColor: Theme.of(context).scaffoldBackgroundColor,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      openShape: const RoundedRectangleBorder(),
      tappable: false,
      closedBuilder: closedBuilder,
      openBuilder: (context, _) =>
          SwipeDownToClose(child: openBuilder(context)),
      onClosed: (_) => onClosed?.call(),
    );
  }
}
