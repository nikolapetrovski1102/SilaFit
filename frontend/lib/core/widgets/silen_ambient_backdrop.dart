import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Soft ambient glow used behind Home and its related detail screens.
///
/// The blurred shapes are static, so the repaint boundary lets Flutter cache
/// them while the foreground content scrolls. The accent-dependent key makes
/// sure switching between light and dark themes refreshes the cached layer.
class SilenAmbientBackdrop extends StatelessWidget {
  const SilenAmbientBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.paletteFor(brightness).accent;

    return IgnorePointer(
      child: RepaintBoundary(
        key: ValueKey(accent),
        child: ClipRect(
          child: Stack(
            children: [
              Positioned(
                top: -140,
                right: -120,
                child: _GlowBlob(diameter: 340, color: accent),
              ),
              Positioned(
                bottom: -160,
                left: -130,
                child: _GlowBlob(diameter: 380, color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final double diameter;
  final Color color;

  const _GlowBlob({required this.diameter, required this.color});

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.28),
        ),
      ),
    );
  }
}
