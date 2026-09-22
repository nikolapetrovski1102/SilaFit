import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// Full-screen overlay that softly dims the screen, cuts out a rounded-rect
/// spotlight hole around [targetKey] with an accent ring, and displays the
/// floating [TourGuideCard] above the bottom navigation bar.
class TourSpotlightOverlay extends StatefulWidget {
  final GlobalKey? targetKey;
  final int stepIndex;
  final int stepCount;
  final String title;
  final String description;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final String nextLabel;
  final double cardBottom;

  const TourSpotlightOverlay({
    super.key,
    this.targetKey,
    required this.stepIndex,
    required this.stepCount,
    required this.title,
    required this.description,
    required this.onNext,
    required this.onSkip,
    this.nextLabel = 'Next',
    this.cardBottom = 100,
  });

  @override
  State<TourSpotlightOverlay> createState() => _TourSpotlightOverlayState();
}

class _TourSpotlightOverlayState extends State<TourSpotlightOverlay>
    with TickerProviderStateMixin {
  Rect? _targetRect;
  late final AnimationController _fadeController;
  late final AnimationController _pulseController;
  late final Animation<double> _fade;
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _ticker = createTicker((_) => _updateRect());
    _ticker.start();
  }

  @override
  void didUpdateWidget(covariant TourSpotlightOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetKey != widget.targetKey ||
        oldWidget.stepIndex != widget.stepIndex) {
      _targetRect = null;
    }
  }

  void _updateRect() {
    if (!mounted) return;
    if (widget.targetKey == null) {
      if (_targetRect != null) {
        setState(() => _targetRect = null);
      }
      return;
    }

    final keyContext = widget.targetKey!.currentContext;
    if (keyContext == null) return;

    final renderBox = keyContext.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached || !renderBox.hasSize) return;

    final overlayBox = context.findRenderObject() as RenderBox?;
    if (overlayBox == null || !overlayBox.attached || !overlayBox.hasSize) return;

    final targetSize = renderBox.size;
    if (targetSize.width <= 0 || targetSize.height <= 0) return;

    final localOrigin =
        overlayBox.globalToLocal(renderBox.localToGlobal(Offset.zero));
    final newRect = localOrigin & targetSize;

    if (_targetRect == null) {
      setState(() => _targetRect = newRect);
    } else {
      final diff = (_targetRect!.left - newRect.left).abs() +
          (_targetRect!.top - newRect.top).abs() +
          (_targetRect!.width - newRect.width).abs() +
          (_targetRect!.height - newRect.height).abs();
      if (diff > 0.5) {
        setState(() => _targetRect = newRect);
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final showCardAtTop =
        _targetRect != null && (_targetRect!.bottom > screenHeight - 250);

    return FadeTransition(
      opacity: _fade,
      child: Stack(
        children: [
          // Softly dimmed backdrop with spotlight cutout
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onNext,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _SpotlightPainter(
                      targetRect: _targetRect,
                      overlayColor:
                          const Color(0xFF000000).withValues(alpha: 0.74),
                      glowPhase: _pulseController.value,
                    ),
                  );
                },
              ),
            ),
          ),
          // Floating TourGuideCard - dynamically positioned to avoid covering the spotlight
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            left: AppSpacing.marginMobile,
            right: AppSpacing.marginMobile,
            top: showCardAtTop
                ? mediaQuery.padding.top + AppSpacing.md
                : null,
            bottom: showCardAtTop ? null : widget.cardBottom,
            child: TourGuideCard(
              stepIndex: widget.stepIndex,
              stepCount: widget.stepCount,
              title: widget.title,
              description: widget.description,
              nextLabel: widget.nextLabel,
              onNext: widget.onNext,
              onSkip: widget.onSkip,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final Color overlayColor;
  final double padding;
  final double radius;
  final double glowPhase;

  _SpotlightPainter({
    this.targetRect,
    required this.overlayColor,
    this.padding = 8,
    this.radius = 20,
    this.glowPhase = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = overlayColor;
    final fullPath = Path()..addRect(Offset.zero & size);

    if (targetRect != null &&
        targetRect!.width > 0 &&
        targetRect!.height > 0) {
      final paddedRect = targetRect!.inflate(padding);
      final rrect =
          RRect.fromRectAndRadius(paddedRect, Radius.circular(radius));
      final holePath = Path()..addRRect(rrect);
      final combined =
          Path.combine(PathOperation.difference, fullPath, holePath);
      canvas.drawPath(combined, paint);

      // Outer glowing halo around the spotlighted element
      final glowAlpha = (0.22 + 0.18 * glowPhase).clamp(0.0, 1.0);
      final glowPaint = Paint()
        ..color = AppColors.accent.withValues(alpha: glowAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawRRect(rrect, glowPaint);

      // Crisp accent border ring
      final strokeAlpha = (0.75 + 0.25 * glowPhase).clamp(0.0, 1.0);
      final strokePaint = Paint()
        ..color = AppColors.accent.withValues(alpha: strokeAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawRRect(rrect, strokePaint);
    } else {
      canvas.drawPath(fullPath, paint);
    }
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      targetRect != oldDelegate.targetRect ||
      glowPhase != oldDelegate.glowPhase ||
      overlayColor != oldDelegate.overlayColor;
}

/// A floating, minimalistic explanation card that appears on each page
/// during the post-onboarding walkthrough.
class TourGuideCard extends StatelessWidget {
  final int stepIndex; // 0-based
  final int stepCount;
  final String title;
  final String description;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final String nextLabel;

  const TourGuideCard({
    super.key,
    required this.stepIndex,
    required this.stepCount,
    required this.title,
    required this.description,
    required this.onNext,
    required this.onSkip,
    this.nextLabel = 'Next',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  '${(stepIndex + 1).toString().padLeft(2, '0')} / ${stepCount.toString().padLeft(2, '0')}',
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onSkip,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Skip',
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            style: AppTypography.headlineSm.copyWith(
              color: AppColors.highEmphasis,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            description,
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _TourPillDots(current: stepIndex, total: stepCount),
              const Spacer(),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        nextLabel,
                        style: AppTypography.headlineSm.copyWith(
                          color: AppColors.onAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded,
                          size: 16, color: AppColors.onAccent),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TourPillDots extends StatelessWidget {
  final int current;
  final int total;

  const _TourPillDots({required this.current, required this.total});

  static const _dotSize = 7.0;
  static const _activeWidth = 22.0;
  static const _spacing = 6.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: i == current ? _activeWidth : _dotSize,
            height: _dotSize,
            decoration: BoxDecoration(
              color: i == current
                  ? AppColors.accent
                  : AppColors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
          if (i < total - 1) const SizedBox(width: _spacing),
        ],
      ],
    );
  }
}
