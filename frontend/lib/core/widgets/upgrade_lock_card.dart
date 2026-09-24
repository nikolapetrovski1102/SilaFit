import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'section_card.dart';
import 'section_eyebrow.dart';
import 'silen_button.dart';

/// The upgrade prompt that sits over a blurred PRO/Advanced feature (the
/// Progress screen, the suggested-split library). The caller owns the blur
/// and decides where [onUnlock] goes - normally the plans screen.
class UpgradeLockCard extends StatefulWidget {
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onUnlock;

  const UpgradeLockCard({
    super.key,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onUnlock,
  });

  @override
  State<UpgradeLockCard> createState() => _UpgradeLockCardState();
}

class _UpgradeLockCardState extends State<UpgradeLockCard>
    with SingleTickerProviderStateMixin {
  late final _lockController = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    // Same beat as the account gate: let the screen settle, then lock.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _lockController.value = 1;
      } else {
        _lockController.forward();
      }
    });
  }

  @override
  void dispose() {
    _lockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      background: AppColors.surfaceContainerHigh,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(8),
            child: ColorFiltered(
              colorFilter:
                  ColorFilter.mode(AppColors.secondary, BlendMode.srcIn),
              child: Lottie.asset(
                'assets/lottie_animations/locked_lock.json',
                fit: BoxFit.contain,
                repeat: false,
                controller: _lockController,
                onLoaded: (composition) {
                  // 2x the natural speed.
                  _lockController.duration = composition.duration ~/ 2;
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(widget.title,
              style: AppTypography.headlineSm, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.message,
            style:
                AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          SectionEyebrow('PRO · ADVANCED', color: AppColors.secondary),
          const SizedBox(height: AppSpacing.md),
          PrimaryPillButton(
            label: widget.actionLabel,
            icon: Icons.auto_awesome_rounded,
            onPressed: widget.onUnlock,
          ),
        ],
      ),
    );
  }
}
