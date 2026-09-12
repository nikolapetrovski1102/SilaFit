import 'package:flutter/widgets.dart';

/// Viewport-height-aware scale factor for screens that want to fit their
/// content into one screen's worth of space without scrolling (currently
/// just Home/Today), instead of hand-tuning sizes per device class.
///
/// Every other screen keeps using the fixed [AppSpacing]/[AppTypography]
/// scale untouched - this is deliberately opt-in per screen rather than a
/// global text-scaling layer, so the rest of the app's density stays
/// predictable.
class AppResponsive {
  AppResponsive._();

  /// Visible body height this scale was tuned against - a mid-size phone
  /// (iPhone 13-class) once the status bar and the floating bottom-nav pill
  /// are subtracted. Screens with more room than this scale up slightly;
  /// tighter ones (small phones, or split-screen/desktop windows) scale
  /// down so content still reads as one deliberate composition rather than
  /// clipping or forcing a scroll.
  ///
  /// Bumped +24 alongside [SilenBottomNavBar]'s slimmer reserved band (60px
  /// of chrome above the safe-area inset, down from 84) so the same
  /// physical device still lands at ~1.0x instead of drifting toward
  /// [_maxScale] just because the nav got smaller.
  static const double referenceHeight = 684;

  static const double _minScale = 0.82;
  static const double _maxScale = 1.08;

  /// [viewportHeight] should be the space actually available to the
  /// screen's own content - the constraint captured just inside the tab's
  /// body, not the raw device [MediaQuery] size (which still includes the
  /// nav bar and safe-area insets this content never draws under).
  ///
  /// Also eases off against the system text-scale setting: a viewer who
  /// has already bumped their OS font size gets extra height pressure from
  /// that alone, so this scale backs off further rather than compounding
  /// the two into an overflow.
  static double scaleFor(BuildContext context, double viewportHeight) {
    final heightRatio = viewportHeight / referenceHeight;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final eased = textScale > 1.0 ? heightRatio / textScale : heightRatio;
    return eased.clamp(_minScale, _maxScale);
  }
}
