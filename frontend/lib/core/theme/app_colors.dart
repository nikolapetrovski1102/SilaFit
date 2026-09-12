import 'package:flutter/widgets.dart';

/// "Precision Kinetic" color tokens - the redesign's design system, replacing
/// the previous "Kinetic Pulse" palette wholesale (different literal hex
/// values throughout, not a re-skin of the old ones).
///
/// Dark mode's ground truth is the 4 built `code.html` mockups' Tailwind
/// config (dark canvas #0f1512 / lime accent #d0f043) - the accent had
/// briefly been swapped to Cosmic Orange (#f77e2d) per product direction,
/// but that's been reverted back to the mockups' lime. Light mode's ground
/// truth is `homescreen_inspiration-light`
/// (cream canvas / mustard-gold secondary), with its accent likewise swapped
/// to a truer burgundy (#800020) - see [AppPalette.light]'s doc comment.
///
/// Every screen reads these as static getters rather than threading a
/// `BuildContext`/theme extension through every call site. [setBrightness]
/// is called once per frame from [SilenApp]'s `MaterialApp.builder`, so an
/// appearance-mode flip forces the whole tree to rebuild with the other
/// palette - no per-widget plumbing required.
class AppColors {
  AppColors._();

  static Brightness _brightness = Brightness.dark;
  static AppPalette get _current => paletteFor(_brightness);

  /// Called once per build from the `MaterialApp.builder` - see
  /// [SilenApp] in `main.dart`. Not meant to be called from feature code.
  static void setBrightness(Brightness brightness) => _brightness = brightness;

  /// Resolves the full palette for an explicit [brightness], independent of
  /// whatever [_brightness] is currently set to. `buildSilenTheme` needs
  /// this rather than the ambient getters below - it builds the light and
  /// dark `ThemeData` back-to-back regardless of which mode is active, and
  /// reading the ambient getters for both would bake the *same* (whichever
  /// happened to be current) palette into both themes.
  static AppPalette paletteFor(Brightness brightness) =>
      brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;

  // Surfaces
  static Color get background => _current.background;
  static Color get surface => _current.surface;
  static Color get surfaceContainerLowest => _current.surfaceContainerLowest;
  static Color get surfaceContainerLow => _current.surfaceContainerLow;
  static Color get surfaceContainer => _current.surfaceContainer;
  static Color get surfaceContainerHigh => _current.surfaceContainerHigh;
  static Color get surfaceContainerHighest => _current.surfaceContainerHighest;
  static Color get surfaceBright => _current.surfaceBright;

  // Text
  static Color get onSurface => _current.onSurface;
  static Color get onSurfaceVariant => _current.onSurfaceVariant;
  static Color get highEmphasis => _current.highEmphasis;
  static Color get outline => _current.outline;
  static Color get outlineVariant => _current.outlineVariant;

  // Lime accent (Precision Kinetic "primary" family)
  static Color get accent => _current.accent;
  static Color get onAccent => _current.onAccent;
  static Color get primaryContainer => _current.primaryContainer;
  static Color get onPrimaryContainer => _current.onPrimaryContainer;

  // Gold accent (Pro tier)
  static Color get secondary => _current.secondary;
  static Color get secondaryContainer => _current.secondaryContainer;
  static Color get onSecondaryContainer => _current.onSecondaryContainer;

  // Tertiary (pale blue - e.g. carbs macro bar)
  static Color get tertiaryContainer => _current.tertiaryContainer;

  // Status
  static Color get error => _current.error;
  static Color get errorContainer => _current.errorContainer;
  static Color get onError => _current.onError;
  static Color get onErrorContainer => _current.onErrorContainer;

  /// Semantic mapping onto the DB session-status enum
  /// ('Scheduled' | 'Completed' | 'Missed' | 'ActiveRest').
  static Color forSessionStatus(String status) {
    switch (status) {
      case 'Completed':
        return accent;
      case 'Missed':
        return onSurfaceVariant;
      case 'ActiveRest':
        return secondary;
      case 'Scheduled':
      default:
        return surfaceContainerHigh;
    }
  }
}

/// One immutable set of color tokens for a single [Brightness]. Holding
/// these as plain fields (rather than the old pair of static-const classes)
/// lets [AppColors.paletteFor] hand out either palette explicitly, so
/// `buildSilenTheme` can build the light and dark `ThemeData` from their own
/// palettes instead of both reading whichever one [AppColors] currently has
/// active.
class AppPalette {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.surfaceBright,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.highEmphasis,
    required this.outline,
    required this.outlineVariant,
    required this.accent,
    required this.onAccent,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiaryContainer,
    required this.error,
    required this.errorContainer,
    required this.onError,
    required this.onErrorContainer,
  });

  final Color background;
  final Color surface;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color surfaceBright;

  final Color onSurface;
  final Color onSurfaceVariant;
  final Color highEmphasis;
  final Color outline;
  final Color outlineVariant;

  final Color accent;
  final Color onAccent;
  final Color primaryContainer;
  final Color onPrimaryContainer;

  final Color secondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;

  final Color tertiaryContainer;

  final Color error;
  final Color errorContainer;
  final Color onError;
  final Color onErrorContainer;

  /// Dark palette - ground truth from the 4 built Precision Kinetic
  /// `code.html` mockups' Tailwind config, including the accent family
  /// (lime #d0f043) - reverted back to this after a brief swap to Cosmic
  /// Orange (#f77e2d). This is the app's default mode.
  static const dark = AppPalette(
    background: Color(0xFF0F1512),
    surface: Color(0xFF0F1512),
    surfaceContainerLowest: Color(0xFF0A0F0D),
    surfaceContainerLow: Color(0xFF171D1A),
    surfaceContainer: Color(0xFF1B211E),
    surfaceContainerHigh: Color(0xFF252B28),
    surfaceContainerHighest: Color(0xFF303633),
    surfaceBright: Color(0xFF343B37),
    onSurface: Color(0xFFDEE4DF),
    onSurfaceVariant: Color(0xFFC6C9AF),
    highEmphasis: Color(0xFFFFFFFF),
    outline: Color(0xFF8F937B),
    outlineVariant: Color(0xFF454935),
    accent: Color(0xFFD0F043),
    onAccent: Color(0xFF1D2900),
    primaryContainer: Color(0xFFD0F043),
    onPrimaryContainer: Color(0xFF3A4A00),
    secondary: Color(0xFFE6C367),
    secondaryContainer: Color(0xFF735800),
    onSecondaryContainer: Color(0xFFF6D173),
    tertiaryContainer: Color(0xFFC7E7FA),
    error: Color(0xFFFFB4AB),
    errorContainer: Color(0xFF93000A),
    onError: Color(0xFF690005),
    onErrorContainer: Color(0xFFFFDAD6),
  );

  /// Light palette - warm cream/ink counterpart to Precision Kinetic's dark
  /// mode, extracted from `homescreen_inspiration-light` (the reference
  /// screenshot, not a built `code.html` mockup like the dark side has).
  /// Same strategy as the olive palette it replaces - light mode never puts
  /// light text on a bright accent, it puts white/cream text on a *deep*
  /// ink-toned fill - with a true burgundy (#800020) standing in for the
  /// reference's muted wine tone, and the reference's mustard-gold secondary
  /// carried over almost unchanged since it already fit.
  static const light = AppPalette(
    background: Color(0xFFF5EEDD),
    surface: Color(0xFFF5EEDD),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFEFE6D0),
    surfaceContainer: Color(0xFFE8DCC0),
    surfaceContainerHigh: Color(0xFFDCCDA9),
    surfaceContainerHighest: Color(0xFFCBB98F),
    surfaceBright: Color(0xFFFFFFFF),
    onSurface: Color(0xFF241B12),
    onSurfaceVariant: Color(0xFF6E624A),
    highEmphasis: Color(0xFF1A130C),
    outline: Color(0xFFA0916D),
    outlineVariant: Color(0xFFE1D3AE),
    accent: Color(0xFF800020),
    onAccent: Color(0xFFFBEFE2),
    primaryContainer: Color(0xFFF0D9DD),
    onPrimaryContainer: Color(0xFF800020),
    secondary: Color(0xFF8A5A12),
    secondaryContainer: Color(0xFFF5C463),
    onSecondaryContainer: Color(0xFF3F2600),
    tertiaryContainer: Color(0xFFC7E7FA),
    error: Color(0xFFBA1A1A),
    errorContainer: Color(0xFFFFDAD6),
    onError: Color(0xFFFFFFFF),
    onErrorContainer: Color(0xFF93000A),
  );
}
