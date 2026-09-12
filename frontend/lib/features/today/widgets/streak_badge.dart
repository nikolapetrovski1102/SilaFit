import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// The streak counter shown top-right next to Home's greeting. Both tap and
/// a horizontal swipe open the streak history sheet - tap for the quick
/// path, swipe for a one-handed "flick it open" gesture that mirrors the
/// bottom nav's own swipe-to-switch feel. A light press-scale and a
/// finger-following slide give both gestures the same tactile, springy
/// response as the rest of the app's hand-rolled (no-animation-package)
/// interactions.
class StreakBadge extends StatefulWidget {
  final int streakDays;
  final double scale;
  final VoidCallback onTap;

  const StreakBadge(
      {super.key, required this.streakDays, required this.scale, required this.onTap});

  @override
  State<StreakBadge> createState() => _StreakBadgeState();
}

class _StreakBadgeState extends State<StreakBadge> {
  // How far a swipe has to travel before it counts as "open it", vs. a
  // stray drag that should just snap back with nothing happening.
  static const _dragThreshold = 26.0;
  // Clamped well short of the threshold's round trip so the badge reads as
  // gently elastic rather than something that can be dragged off-screen.
  static const _maxDrag = 34.0;

  bool _pressed = false;
  bool _dragging = false;
  double _dragExtent = 0;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  void _handleDragStart(DragStartDetails _) {
    setState(() => _dragging = true);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragExtent = (_dragExtent + details.delta.dx).clamp(-_maxDrag, _maxDrag);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final triggered = _dragExtent.abs() > _dragThreshold;
    setState(() {
      _dragging = false;
      // Snapping this back to zero now (rather than animating it manually)
      // is what the wrapping AnimatedContainer below picks up and eases
      // out for us once `_dragging` flips its duration back on.
      _dragExtent = 0;
    });
    if (triggered) {
      HapticFeedback.selectionClick();
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      // Zero duration while a finger is actively moving it (so it tracks
      // 1:1 with the drag), then eased back on for the release snap-back -
      // the same trick used for a real spring without a physics dependency.
      child: AnimatedContainer(
        duration: _dragging ? Duration.zero : const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(_dragExtent, 0, 0),
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.xs * scale, vertical: AppSpacing.xxs * scale),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_fire_department_rounded,
                    color: AppColors.accent, size: 24 * scale),
                SizedBox(width: AppSpacing.xxs * scale),
                Text('${widget.streakDays}',
                    style: AppTypography.headlineSm.copyWith(fontSize: 22 * scale)),
                SizedBox(width: 2 * scale),
                Icon(Icons.chevron_right_rounded,
                    color: AppColors.onSurfaceVariant, size: 16 * scale),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
