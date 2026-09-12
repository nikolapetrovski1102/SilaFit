import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// The rounded surface-container card every screen builds its sections
/// from. Precision Kinetic depth comes purely from background-color
/// layering across the surface-container-* steps, never from box shadows
/// or hairline borders - deliberately flat, no elevation.
class SectionCard extends StatelessWidget {
  final Widget child;
  final Color? background;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    required this.child,
    this.background,
    this.padding = const EdgeInsets.all(AppSpacing.cardPadding),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: child,
    );
  }
}
