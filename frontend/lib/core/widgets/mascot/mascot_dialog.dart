import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../silen_button.dart';
import 'celebrating_ram.dart';
import 'ram_mascot.dart';

/// The mascot's modal moment - custom alerts, congratulations, milestones.
/// Scale+fade entrance via [Curves.easeOutBack] for a springy, premium feel.
///
/// With [showConfetti] on, the dialog becomes a celebration: Sila leaps out
/// of the top of the card, spins, lands with a fist pump and fires confetti
/// ([CelebratingRam]). [pose] is then only the reduced-motion fallback
/// framing, since the routine picks its own poses.
class MascotDialog extends StatelessWidget {
  final RamArt pose;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool showConfetti;

  static const double _celebrateSize = 150;

  const MascotDialog({
    super.key,
    required this.pose,
    required this.title,
    required this.message,
    this.actionLabel = 'Nice',
    this.onAction,
    this.showConfetti = false,
  });

  /// Shows the dialog with the shared scale+fade+easeOutBack entrance.
  static Future<void> show(
    BuildContext context, {
    required RamArt pose,
    required String title,
    required String message,
    String actionLabel = 'Nice',
    VoidCallback? onAction,
    bool showConfetti = false,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (context, _, __) => MascotDialog(
        pose: pose,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
        showConfetti: showConfetti,
      ),
      transitionBuilder: (context, animation, _, child) {
        final eased = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
        return Opacity(
          opacity: animation.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.82 + 0.18 * eased.value,
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xxl,
                AppSpacing.xl, AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: showConfetti
                  ? Border.all(
                      color: AppColors.accent.withValues(alpha: 0.35))
                  : null,
              // A soft accent glow lifts a celebration off the backdrop.
              boxShadow: showConfetti
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.18),
                        blurRadius: 40,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showConfetti)
                  // The stage is taller than the space it takes, so Sila
                  // leaps up and out of the top of the card.
                  SizedBox(
                    height: _celebrateSize * 1.1,
                    child: OverflowBox(
                      alignment: Alignment.bottomCenter,
                      maxWidth: CelebratingRam.stageFor(_celebrateSize).width,
                      maxHeight: CelebratingRam.stageFor(_celebrateSize).height,
                      child: const CelebratingRam(size: _celebrateSize),
                    ),
                  )
                else
                  RamMascot(pose, size: 148),
                const SizedBox(height: AppSpacing.lg),
                Text(title,
                    style: AppTypography.headlineMd,
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message,
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryPillButton(
                  label: actionLabel,
                  onPressed: () {
                    Navigator.of(context).pop();
                    onAction?.call();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
