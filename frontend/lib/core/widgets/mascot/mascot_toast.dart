import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'mascot_pose.dart';

/// A lighter, non-blocking mascot moment - an inline banner that slides in
/// from the top and auto-dismisses, for a milestone that doesn't need to
/// interrupt the user the way [MascotDialog] does.
class MascotToast {
  MascotToast._();

  static void show(
    BuildContext context, {
    required MascotPose pose,
    required String message,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _MascotToastView(
        pose: pose,
        message: message,
        duration: duration,
        onDismissed: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _MascotToastView extends StatefulWidget {
  final MascotPose pose;
  final String message;
  final Duration duration;
  final VoidCallback onDismissed;

  const _MascotToastView({
    required this.pose,
    required this.message,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_MascotToastView> createState() => _MascotToastViewState();
}

class _MascotToastViewState extends State<_MascotToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _controller.forward();
    Future.delayed(widget.duration, () async {
      if (!mounted) return;
      await _controller.reverse();
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    return Positioned(
      top: topInset + AppSpacing.sm,
      left: AppSpacing.marginMobile,
      right: AppSpacing.marginMobile,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Opacity(
          opacity: _controller.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -16 * (1 - curved.value)),
            child: child,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                Image.asset(widget.pose.assetPath,
                    width: 44, height: 44, semanticLabel: mascotName),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(widget.message, style: AppTypography.bodyMd),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
