import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart' show AppRadius;
import '../theme/app_typography.dart';

/// The pill-shaped, lime-filled call-to-action button used for every
/// primary action across the app ("Start Workout", "Continue", ...).
/// Fixed h48 per the Precision Kinetic button spec, with a subtle
/// press-down scale for tactile feedback.
class PrimaryPillButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// Defaults to the spec's fixed 48. Screens that scale their own layout
  /// to fit the viewport can pass a scaled value so the button grows with
  /// the rest of the content instead of looking undersized next to bigger
  /// type - callers are responsible for keeping it at or above a
  /// comfortable tap-target size.
  final double height;

  const PrimaryPillButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.height = 48,
  });

  @override
  State<PrimaryPillButton> createState() => _PrimaryPillButtonState();
}

class _PrimaryPillButtonState extends State<PrimaryPillButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null || widget.isLoading) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null || widget.isLoading;
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: SizedBox(
          width: double.infinity,
          height: widget.height,
          child: ElevatedButton(
            onPressed: widget.isLoading ? null : widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              disabledBackgroundColor: AppColors.accent.withOpacity(0.5),
              foregroundColor: AppColors.onAccent,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full)),
              elevation: 0,
            ),
            child: widget.isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.onAccent),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 20),
                        const SizedBox(width: 8)
                      ],
                      // Flexible + ellipsis: a caller that scales the card
                      // around this button (see FitHeight) can end up with
                      // more padding eating into the button's own width
                      // while this label stays a fixed size - shrink the
                      // label instead of overflowing the button.
                      Flexible(
                        child: Text(widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.headlineSm.copyWith(
                                color: AppColors.onAccent, fontSize: 16)),
                      ),
                    ],
                  ),
          ),
        ),
      ),
      behavior: disabled ? HitTestBehavior.deferToChild : HitTestBehavior.opaque,
    );
  }
}

/// A muted pill button for secondary/tertiary actions on a dark surface.
class SecondaryPillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? foregroundColor;

  const SecondaryPillButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: AppColors.surfaceContainerHigh,
          foregroundColor: foregroundColor ?? AppColors.onSurface,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.full)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8)
            ],
            Text(
              label,
              style: AppTypography.headlineSm.copyWith(
                  fontSize: 16,
                  color: foregroundColor ?? AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
