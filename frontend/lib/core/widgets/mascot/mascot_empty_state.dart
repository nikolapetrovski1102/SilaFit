import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../silen_button.dart';
import 'mascot_pose.dart';

/// A static mascot illustration + text block for empty states (e.g. no
/// splits yet). Unlike [MascotDialog] this is inline content, not a modal.
class MascotEmptyState extends StatelessWidget {
  final MascotPose pose;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const MascotEmptyState({
    super.key,
    required this.pose,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(pose.assetPath, height: 132, semanticLabel: mascotName),
          const SizedBox(height: AppSpacing.lg),
          Text(title, style: AppTypography.headlineSm, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(
              message,
              style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.lg),
            PrimaryPillButton(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}
