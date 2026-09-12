/// "Precision Kinetic" spacing scale. Shared everywhere so no screen
/// hand-rolls its own magic-number padding.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 4; // space-2xs
  static const double xs = 8; // space-xs
  static const double sm = 12; // space-sm
  static const double md = 16; // space-md
  static const double lg = 20; // space-lg
  static const double xl = 24; // space-xl
  static const double xxl = 32; // space-2xl
  static const double xxxl = 40; // space-3xl

  /// Page horizontal padding ("margin-mobile" in the design system).
  static const double marginMobile = 20;

  /// Card internal padding.
  static const double cardPadding = 20;

  /// Generic inter-element gutter (e.g. between grid tiles).
  static const double gutter = 16;

  /// Back-compat alias for [marginMobile] - remove once every screen has
  /// migrated off the old name.
  static const double gutterMobile = marginMobile;
}

/// "Precision Kinetic" corner-radius scale. Cards are a fixed 18px
/// everywhere (not the old 12px "xl" token) - confirmed as the true
/// standard across all 4 built reference mockups.
class AppRadius {
  AppRadius._();

  /// Standard card radius - the single most common radius in the system.
  static const double card = 18;

  /// Inner/inset wells (input fields, recessed tracks, small tiles).
  static const double inset = 12;

  /// Small tiles (distinct name for the same 12px value, for call-site
  /// clarity).
  static const double smallTile = 12;

  /// Pills, chips, buttons, nav bar.
  static const double full = 9999;

  // --- Back-compat aliases ------------------------------------------------
  static const double sm = inset;
  static const double defaultRadius = inset;
  static const double lg = card;
  static const double xl = card;
}
