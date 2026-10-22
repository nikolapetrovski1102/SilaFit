import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/dumbbell_icon.dart';
import '../../../core/widgets/silen_button.dart';
import 'onboarding_step_transition.dart';

/// One page of the intro carousel: an icon mark plus headline/subhead.
class IntroSlideData {
  final Widget iconMark;
  final String headline;
  final String subhead;

  const IntroSlideData({
    required this.iconMark,
    required this.headline,
    required this.subhead,
  });
}

/// The swipeable intro carousel: Skip top-right on every slide, a
/// [PageView] of [slides], a dot indicator, the CTA, and the "Already have
/// an account? Log in" link. There's deliberately no back arrow - swiping
/// right is the way back - so the only step-level navigation out of here is
/// [onDone] (the CTA on the last slide) or [onSkip].
class IntroCarousel extends StatefulWidget {
  final List<IntroSlideData> slides;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onDone;
  final VoidCallback onSkip;
  final VoidCallback onLogin;

  const IntroCarousel({
    super.key,
    required this.slides,
    required this.initialPage,
    required this.onPageChanged,
    required this.onDone,
    required this.onSkip,
    required this.onLogin,
  });

  @override
  State<IntroCarousel> createState() => _IntroCarouselState();
}

class _IntroCarouselState extends State<IntroCarousel> {
  late final PageController _pageController =
      PageController(initialPage: widget.initialPage);
  late int _page = widget.initialPage;

  bool get _isLast => _page == widget.slides.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onCta() {
    if (_isLast) {
      widget.onDone();
      return;
    }
    _pageController.nextPage(
      duration: MediaQuery.disableAnimationsOf(context)
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                AppSpacing.sm, AppSpacing.marginMobile, 0),
            child: SizedBox(
              height: 48,
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: widget.onSkip,
                  child: Text('Skip',
                      style: AppTypography.bodyMd
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ),
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.slides.length,
              onPageChanged: (page) {
                HapticFeedback.selectionClick();
                setState(() => _page = page);
                widget.onPageChanged(page);
              },
              itemBuilder: (context, i) =>
                  _IntroSlidePage(data: widget.slides[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.marginMobile),
            child: Column(
              children: [
                // Driven by the live scroll offset, so the indicator tracks
                // the finger mid-swipe instead of jumping once it settles.
                AnimatedBuilder(
                  animation: _pageController,
                  builder: (context, _) {
                    final position = _pageController.hasClients &&
                            _pageController.position.haveDimensions
                        ? _pageController.page ?? _page.toDouble()
                        : _page.toDouble();
                    return _SlideDots(
                        position: position, dotCount: widget.slides.length);
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryPillButton(
                  label: _isLast ? 'Continue' : 'Get started',
                  onPressed: _onCta,
                ),
                const SizedBox(height: AppSpacing.sm),
                GestureDetector(
                  onTap: widget.onLogin,
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
        ],
      ),
    );
  }
}

class _IntroSlidePage extends StatelessWidget {
  final IntroSlideData data;
  const _IntroSlidePage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
      child: Column(
        children: [
          const Spacer(flex: 2),
          OnboardingStepContentTransition(child: data.iconMark),
          const Spacer(flex: 2),
          OnboardingStepContentTransition(
            incomingOffset: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(data.headline,
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineLg),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  data.subhead,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

/// The slide-position indicator: a track of dim dots with one lime capsule
/// that glides between them on slide change, rather than each dot abruptly
/// resizing in place - reads as a single continuous shape sliding along a
/// rail instead of two shapes independently swelling and shrinking.
class _SlideDots extends StatelessWidget {
  final double position; // fractional page, straight from the PageView
  final int dotCount;

  const _SlideDots({required this.position, required this.dotCount});

  static const _dotSize = 9.0;
  static const _activeWidth = 32.0;
  static const _spacing = 12.0;

  @override
  Widget build(BuildContext context) {
    const pitch = _dotSize + _spacing;
    final totalWidth = dotCount * _dotSize + (dotCount - 1) * _spacing;

    // Worm effect: over the first half of a swipe the pill's leading edge
    // stretches to the next dot, over the second half the trailing edge
    // catches up - so it reads as the pill crawling between dots.
    final clamped = position.clamp(0.0, (dotCount - 1).toDouble());
    final from = clamped.floorToDouble();
    final t = clamped - from;
    final head = from + (t * 2).clamp(0.0, 1.0);
    final tail = from + (t * 2 - 1).clamp(0.0, 1.0);
    final left = tail * pitch + _dotSize / 2 - _activeWidth / 2;
    final right = head * pitch + _dotSize / 2 + _activeWidth / 2;

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
          Positioned(
            left: left,
            top: 0,
            child: Container(
              width: right - left,
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
