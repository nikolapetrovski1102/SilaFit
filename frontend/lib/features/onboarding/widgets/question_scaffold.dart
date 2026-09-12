import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/silen_button.dart';

/// Shared chrome for every question/notification-permission step: circular
/// back button + thin animated fill-bar progress up top, headline, the
/// step's own body in the middle, and a pinned-bottom CTA.
class QuestionScaffold extends StatelessWidget {
  final VoidCallback onBack;
  final int progressStep; // 1-based
  final int progressStepCount;
  final String headline;
  final Widget body;
  final String ctaLabel;
  final VoidCallback? onCta;
  final bool ctaLoading;
  final Widget? belowCta;

  const QuestionScaffold({
    super.key,
    required this.onBack,
    required this.progressStep,
    required this.progressStepCount,
    required this.headline,
    required this.body,
    required this.ctaLabel,
    required this.onCta,
    this.ctaLoading = false,
    this.belowCta,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _BackButton(onTap: onBack),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _ProgressBar(
                      step: progressStep, stepCount: progressStepCount),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(headline, style: AppTypography.headlineLg),
            const SizedBox(height: AppSpacing.xl),
            Expanded(child: body),
            PrimaryPillButton(
                label: ctaLabel, onPressed: onCta, isLoading: ctaLoading),
            if (belowCta != null) ...[
              const SizedBox(height: AppSpacing.sm),
              belowCta!,
            ],
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: AppColors.surfaceContainerHigh),
        child: Icon(Icons.arrow_back, size: 18, color: AppColors.onSurface),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int step;
  final int stepCount;
  const _ProgressBar({required this.step, required this.stepCount});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              width: constraints.maxWidth * (step / stepCount).clamp(0, 1),
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
        );
      },
    );
  }
}
