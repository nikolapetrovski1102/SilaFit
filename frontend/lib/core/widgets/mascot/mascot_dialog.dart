import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../silen_button.dart';
import 'confetti_burst.dart';
import 'ram_mascot.dart';
import '../../../l10n/l10n.dart';

/// The mascot's modal moment - custom alerts, congratulations, milestones.
/// The card fades in, then Sila is scrubbed in with a graffiti marker
/// zigzag ([ScribbleReveal]) and stays still - no hops or bounces.
///
/// With [showConfetti] on, the dialog becomes a celebration: the card gets
/// an accent glow and confetti bursts from behind Sila once the scrub is
/// done.
class MascotDialog extends StatelessWidget {
  final RamArt pose;
  final String title;
  final String message;
  final String? _actionLabel;
  String get actionLabel => _actionLabel ?? tr('Nice');
  final VoidCallback? onAction;
  final bool showConfetti;

  static const double _mascotSize = 148;

  const MascotDialog({
    super.key,
    required this.pose,
    required this.title,
    required this.message,
    String? actionLabel,
    this.onAction,
    this.showConfetti = false,
  }) : _actionLabel = actionLabel;

  /// Shows the dialog with a plain fade, so nothing jumps before the scrub.
  static Future<void> show(
    BuildContext context, {
    required RamArt pose,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    bool showConfetti = false,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: tr('Dismiss'),
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, __) => MascotDialog(
        pose: pose,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
        showConfetti: showConfetti,
      ),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
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
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.xxl, AppSpacing.xl, AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: showConfetti
                  ? Border.all(color: AppColors.accent.withValues(alpha: 0.35))
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
                _DialogMascot(pose: pose, confetti: showConfetti),
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

/// Sila scrubbed in, a beat after the dialog's fade, with an optional
/// confetti burst from behind once the scrub has finished.
class _DialogMascot extends StatefulWidget {
  final RamArt pose;
  final bool confetti;

  const _DialogMascot({required this.pose, required this.confetti});

  @override
  State<_DialogMascot> createState() => _DialogMascotState();
}

class _DialogMascotState extends State<_DialogMascot> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final mascot = RamMascot(
      widget.pose,
      size: MascotDialog._mascotSize,
      scribbleIn: true,
      scribbleDelay: const Duration(milliseconds: 160),
      onRevealed: widget.confetti && !_revealed
          ? () {
              if (!mounted) return;
              setState(() => _revealed = true);
              HapticFeedback.mediumImpact();
            }
          : null,
    );
    if (!widget.confetti) return mascot;
    return SizedBox.square(
      dimension: MascotDialog._mascotSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_revealed && !MediaQuery.disableAnimationsOf(context))
            const Positioned(
              left: -120,
              right: -120,
              top: -140,
              bottom: -60,
              child: IgnorePointer(child: ConfettiBurst()),
            ),
          mascot,
        ],
      ),
    );
  }
}
