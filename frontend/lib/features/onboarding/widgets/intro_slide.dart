import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/dumbbell_icon.dart';
import '../../../core/widgets/silen_button.dart';
import 'onboarding_step_transition.dart';

/// One of the 2 intro carousel slides: Skip top-right, an icon mark in a
/// circle, headline/subhead, a dot indicator for the slide position, the
/// CTA, and the "Already have an account? Log in" link.
class IntroSlide extends StatelessWidget {
  final Widget iconMark;
  final String headline;
  final String subhead;
  final int dotIndex; // 0-based, out of [dotCount]
  final int dotCount;
  final String ctaLabel;
  final VoidCallback onCta;
  final VoidCallback onSkip;
  final VoidCallback onLogin;
  final VoidCallback? onBack;

  const IntroSlide({
    super.key,
    required this.iconMark,
    required this.headline,
    required this.subhead,
    required this.dotIndex,
    required this.dotCount,
    required this.ctaLabel,
    required this.onCta,
    required this.onSkip,
    required this.onLogin,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                children: [
                  if (onBack != null)
                    IconButton(
                      tooltip: 'Back',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      color: AppColors.onSurfaceVariant,
                    )
                  else
                    const SizedBox(width: 48, height: 48),
                  const Spacer(),
                  TextButton(
                    onPressed: onSkip,
                    child: Text('Skip',
                        style: AppTypography.bodyMd
                            .copyWith(color: AppColors.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 3),
            OnboardingStepContentTransition(child: iconMark),
            const Spacer(flex: 2),
            OnboardingStepContentTransition(
              incomingOffset: 14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(headline,
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineLg),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    subhead,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 2),
            _SlideDots(dotIndex: dotIndex, dotCount: dotCount),
            const SizedBox(height: AppSpacing.xl),
            PrimaryPillButton(label: ctaLabel, onPressed: onCta),
            const SizedBox(height: AppSpacing.sm),
            GestureDetector(
              onTap: onLogin,
              child: RichText(
                text: TextSpan(
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.onSurfaceVariant),
                  children: [
                    const TextSpan(text: 'Already have an account? '),
                    TextSpan(
                        text: 'Log in',
                        style: TextStyle(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

/// The slide-position indicator: a track of dim dots with one lime capsule
/// that glides between them on slide change, rather than each dot abruptly
/// resizing in place - reads as a single continuous shape sliding along a
/// rail instead of two shapes independently swelling and shrinking.
class _SlideDots extends StatelessWidget {
  final int dotIndex;
  final int dotCount;

  const _SlideDots({required this.dotIndex, required this.dotCount});

  static const _dotSize = 9.0;
  static const _activeWidth = 32.0;
  static const _spacing = 12.0;

  @override
  Widget build(BuildContext context) {
    const pitch = _dotSize + _spacing;
    final totalWidth = dotCount * _dotSize + (dotCount - 1) * _spacing;
    final activeCenterX = dotIndex * pitch + _dotSize / 2;

    return SizedBox(
      width: totalWidth,
      height: _dotSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              for (var i = 0; i < dotCount; i++) ...[
                Container(
                  width: _dotSize,
                  height: _dotSize,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                ),
                if (i != dotCount - 1) const SizedBox(width: _spacing),
              ],
            ],
          ),
          AnimatedPositioned(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            left: activeCenterX - _activeWidth / 2,
            top: 0,
            child: Container(
              width: _activeWidth,
              height: _dotSize,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The lime-outlined circle every intro/notification icon mark sits in,
/// with a small gold accent dot at the top-right - matches the reference
/// screenshots' mark treatment exactly.
class OnboardingIconMark extends StatelessWidget {
  final Widget child;
  final double size;
  final bool showDot;

  const OnboardingIconMark(
      {super.key, required this.child, this.size = 200, this.showDot = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.outlineVariant),
            ),
            alignment: Alignment.center,
            child: MediaQuery.disableAnimationsOf(context)
                ? child
                : TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    child: child,
                    builder: (context, progress, child) => Opacity(
                      opacity: progress,
                      child: Transform.translate(
                        offset: Offset(0, 8 * (1 - progress)),
                        child: child,
                      ),
                    ),
                  ),
          ),
          if (showDot)
            Positioned(
              top: size * 0.22,
              right: size * 0.22,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: AppColors.secondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Slide 1's mark: the same custom soft-edged dumbbell used on Today's
/// active-split row (see `SoftDumbbellIcon`), just bigger - drawn level/
/// resting already, unlike `Icons.fitness_center`'s tilted glyph, so no
/// counter-rotation is needed here.
class DumbbellIconMark extends StatelessWidget {
  const DumbbellIconMark({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingIconMark(
      child: SoftDumbbellIcon(size: 130, color: AppColors.accent),
    );
  }
}

/// Slide 2's mark: an ascending bar-chart glyph, last bar lime/tallest.
class BarChartIconMark extends StatelessWidget {
  const BarChartIconMark({super.key});

  @override
  Widget build(BuildContext context) {
    const heights = [34.0, 52.0, 42.0, 80.0, 24.0];
    return OnboardingIconMark(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < heights.length; i++) ...[
            Container(
              width: 13,
              height: heights[i],
              decoration: BoxDecoration(
                color: i == 3
                    ? AppColors.accent
                    : AppColors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            if (i != heights.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}
