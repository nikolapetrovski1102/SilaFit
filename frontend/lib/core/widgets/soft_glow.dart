import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A solid circle of [diameter] as it would look under
/// `ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)`, drawn as a single
/// radial gradient instead of a live Gaussian blur.
///
/// Impeller (Flutter's Android renderer) has no raster cache, so an
/// `ImageFiltered` blur is recomputed on the GPU every frame anything on
/// screen scrolls or animates - with full-screen sigma 70-90 backdrops that
/// alone was enough to drop frames on low-end Android phones. The gradient's
/// stops follow the exact blurred-disc falloff, so it reads the same at a
/// fraction of the cost.
///
/// Lays out at [diameter] like the original circle (so alignment/positioning
/// math is unchanged) and paints the glow past its bounds, the way the blur
/// did.
class SoftGlow extends StatelessWidget {
  final double diameter;
  final double sigma;
  final Color color;

  const SoftGlow({
    super.key,
    required this.diameter,
    required this.sigma,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final radius = diameter / 2;
    final extent = radius + 3 * sigma;
    final profile = _profileFor(radius, sigma);
    return SizedBox(
      width: diameter,
      height: diameter,
      child: OverflowBox(
        maxWidth: extent * 2,
        maxHeight: extent * 2,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                for (final v in profile)
                  color.withValues(alpha: color.a * v),
              ],
              stops: [
                for (var i = 0; i < profile.length; i++)
                  i / (profile.length - 1),
              ],
            ),
          ),
          child: SizedBox(width: extent * 2, height: extent * 2),
        ),
      ),
    );
  }

  static const _stopCount = 14;
  static final _cache = <(double, double), List<double>>{};

  /// Intensity of a unit disc of [radius] blurred by [sigma], sampled at
  /// evenly spaced distances from the center out to `radius + 3 * sigma`.
  static List<double> _profileFor(double radius, double sigma) =>
      _cache.putIfAbsent((radius, sigma), () {
        final extent = radius + 3 * sigma;
        return [
          for (var i = 0; i < _stopCount; i++)
            _blurredDisc(extent * i / (_stopCount - 1), radius, sigma),
        ];
      });

  // I(rho) = integral over x in [-R, R] of
  //   gaussian(x - rho) * erf(sqrt(R^2 - x^2) / (sigma * sqrt2)).
  static double _blurredDisc(double rho, double radius, double sigma) {
    if (sigma <= 0) return rho <= radius ? 1 : 0;
    const samples = 96;
    final dx = 2 * radius / samples;
    final norm = 1 / (sigma * math.sqrt(2 * math.pi));
    var sum = 0.0;
    for (var i = 0; i < samples; i++) {
      final x = -radius + (i + 0.5) * dx;
      final g = norm * math.exp(-math.pow(x - rho, 2) / (2 * sigma * sigma));
      final half = math.sqrt(radius * radius - x * x);
      sum += g * _erf(half / (sigma * math.sqrt2)) * dx;
    }
    return sum.clamp(0.0, 1.0);
  }

  // Abramowitz & Stegun 7.1.26 (max error 1.5e-7).
  static double _erf(double x) {
    final t = 1 / (1 + 0.3275911 * x.abs());
    final y = 1 -
        (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t -
                    0.284496736) *
                t +
            0.254829592) *
            t *
            math.exp(-x * x);
    return x >= 0 ? y : -y;
  }
}
