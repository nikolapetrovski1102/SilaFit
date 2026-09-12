import 'package:flutter/widgets.dart';

import 'app_colors.dart';

/// "Precision Kinetic" type scale - Hanken Grotesk exclusively (the previous
/// Space Grotesk + JetBrains Mono mix is gone). Names mirror the scale
/// documented in the design system so a screen built from a mockup can map
/// class-for-class onto a text style here.
///
/// The typeface ships as a bundled asset (see `pubspec.yaml`'s `fonts:`
/// section and `assets/fonts/HankenGrotesk-Variable.ttf`) rather than through
/// `google_fonts`, which fetches the file over the network the first time
/// each weight is used - a slow-startup/jank source on a cold cache (every
/// fresh install, and every simulator reset during dev).
class AppTypography {
  AppTypography._();

  static const _family = 'HankenGrotesk';

  static TextStyle get labelCaps => TextStyle(
        fontFamily: _family,
        fontSize: 11,
        height: 14 / 11,
        letterSpacing: 0.05 * 11,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurfaceVariant,
      );

  static TextStyle get bodyMd => TextStyle(
        fontFamily: _family,
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w400,
        color: AppColors.onSurface,
      );

  static TextStyle get labelSm => TextStyle(
        fontFamily: _family,
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurface,
      );

  static TextStyle get bodyLg => TextStyle(
        fontFamily: _family,
        fontSize: 16,
        height: 24 / 16,
        fontWeight: FontWeight.w400,
        color: AppColors.onSurface,
      );

  /// Numeric readouts (metrics, telemetry) - tabular figures so digits don't
  /// jitter horizontally as they change.
  static TextStyle get numericUnit => TextStyle(
        fontFamily: _family,
        fontSize: 14,
        height: 18 / 14,
        letterSpacing: 0.01 * 14,
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: AppColors.onSurface,
      );

  static TextStyle get headlineSm => TextStyle(
        fontFamily: _family,
        fontSize: 18,
        height: 24 / 18,
        letterSpacing: -0.01 * 18,
        fontWeight: FontWeight.w600,
        color: AppColors.highEmphasis,
      );

  static TextStyle get headlineMd => TextStyle(
        fontFamily: _family,
        fontSize: 22,
        height: 28 / 22,
        letterSpacing: -0.015 * 22,
        fontWeight: FontWeight.w600,
        color: AppColors.highEmphasis,
      );

  static TextStyle get headlineLg => TextStyle(
        fontFamily: _family,
        fontSize: 28,
        height: 34 / 28,
        letterSpacing: -0.02 * 28,
        fontWeight: FontWeight.w600,
        color: AppColors.highEmphasis,
      );

  static TextStyle get displayStatMobile => TextStyle(
        fontFamily: _family,
        fontSize: 38,
        height: 42 / 38,
        letterSpacing: -0.03 * 38,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: AppColors.highEmphasis,
      );

  /// The largest hero readout - the actively-selected value in a scrubbable
  /// picker (onboarding's age/height/weight wheels). Bigger than
  /// [displayStat] because it stands alone as the sole focal point of the
  /// screen rather than sitting in a stat grid.
  static TextStyle get displayStatXl => TextStyle(
        fontFamily: _family,
        fontSize: 76,
        height: 80 / 76,
        letterSpacing: -0.03 * 76,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: AppColors.highEmphasis,
      );

  static TextStyle get displayStat => TextStyle(
        fontFamily: _family,
        fontSize: 48,
        height: 52 / 48,
        letterSpacing: -0.03 * 48,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: AppColors.highEmphasis,
      );

  // --- Back-compat aliases -------------------------------------------------
  // A handful of not-yet-restyled screens (restyled in later redesign
  // phases) still reference these older Kinetic Pulse style names. Kept as
  // thin aliases onto the new scale so the app keeps compiling mid-rollout;
  // remove once every call site above has migrated to the named styles.
  static TextStyle get bodySm => TextStyle(
        fontFamily: _family,
        fontSize: 13,
        height: 18 / 13,
        fontWeight: FontWeight.w400,
        color: AppColors.onSurfaceVariant,
      );

  static TextStyle get metricMd => numericUnit.copyWith(
        fontSize: 24,
        height: 28 / 24,
        color: AppColors.highEmphasis,
      );

  static TextStyle get metricDisplay => displayStatMobile;
}
