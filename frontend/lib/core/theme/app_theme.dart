import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart' show AppRadius;
import 'app_typography.dart';

/// Assembles a [ThemeData] from the Kinetic Pulse tokens for the given
/// [brightness]. Deliberately does NOT lean on `ColorScheme.fromSeed` - the
/// Stitch palette isn't a Material-generated scheme, it's hand-picked, so
/// the scheme below just carries the handful of slots Flutter widgets
/// require (text selection, splash color, etc.) while every screen still
/// reads `AppColors` directly for everything else.
///
/// Reads its colors from `AppColors.paletteFor(brightness)` - the palette
/// matching *this call's* `brightness` - rather than the `AppColors` ambient
/// getters, which resolve off whatever brightness happens to be currently
/// active. `MaterialApp` builds both the light and dark `ThemeData` on every
/// rebuild regardless of which one is in use, so reading the ambient
/// getters here would bake the same (whichever was current) palette into
/// both, leaving the other `ThemeMode` looking unchanged when selected.
ThemeData buildSilenTheme(Brightness brightness) {
  final base = brightness == Brightness.dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);
  final palette = AppColors.paletteFor(brightness);

  return base.copyWith(
    scaffoldBackgroundColor: palette.background,
    colorScheme: base.colorScheme.copyWith(
      surface: palette.surface,
      onSurface: palette.onSurface,
      primary: palette.accent,
      onPrimary: palette.onAccent,
      secondary: palette.secondary,
      error: palette.error,
      onError: palette.onError,
      errorContainer: palette.errorContainer,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: palette.onSurface,
      displayColor: palette.highEmphasis,
    ),
    splashFactory: InkRipple.splashFactory,
    highlightColor: palette.accent.withOpacity(0.08),
    splashColor: palette.accent.withOpacity(0.12),
    dividerColor: palette.outlineVariant,
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.accent,
      linearTrackColor: palette.surfaceContainerHighest,
      circularTrackColor: palette.surfaceContainerHighest,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.accent,
      selectionColor: palette.accent,
      selectionHandleColor: palette.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceContainerLow,
      hintStyle: AppTypography.bodyMd.copyWith(color: palette.onSurfaceVariant),
      labelStyle: AppTypography.labelSm,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.inset),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.inset),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.inset),
        borderSide: BorderSide(color: palette.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.inset),
        borderSide: BorderSide(color: palette.error, width: 1),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surfaceContainerHigh,
      contentTextStyle: AppTypography.bodySm.copyWith(color: palette.onSurface),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
