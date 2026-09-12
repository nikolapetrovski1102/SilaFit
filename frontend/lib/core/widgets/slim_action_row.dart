import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// A single-line, low-profile tappable row - icon, a small caps label over
/// one line of value text, and a trailing glyph. Shared by Home's "Active
/// split" and "AI insights" teaser so both read as quiet secondary rows
/// under the day's hero card rather than two more full-size cards.
class SlimActionRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final String value;
  final Widget trailing;
  final Color? background;
  final Color? borderColor;
  final Gradient? gradient;
  final VoidCallback? onTap;

  /// Overrides the value text's style - callers that want to read as more
  /// than a quiet secondary line (e.g. a bigger, bolder value) can pass
  /// their own instead of the default `bodyMd`. Unset for every other
  /// caller, so this is purely additive.
  final TextStyle? valueStyle;

  /// Overrides the leading icon entirely (e.g. a custom-painted glyph)
  /// instead of the plain Material `Icon` built from [icon]/[iconColor].
  /// Unset for every other caller, so this is purely additive.
  final Widget? iconWidget;

  /// Lets this row grow alongside a fit-to-height hero card above it (see
  /// `TodayOverviewCard`) instead of staying visually undersized next to it
  /// on a tall screen. Defaults to 1 for any caller that isn't in a scaled
  /// layout.
  final double scale;

  const SlimActionRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    required this.value,
    required this.trailing,
    this.background,
    this.borderColor,
    this.gradient,
    this.onTap,
    this.scale = 1,
    this.valueStyle,
    this.iconWidget,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md * scale, vertical: 10 * scale),
        decoration: BoxDecoration(
          color: gradient == null ? (background ?? AppColors.surfaceContainer) : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: borderColor == null ? null : Border.all(color: borderColor!),
        ),
        child: Row(
          children: [
            Container(
              width: 36 * scale,
              height: 36 * scale,
              decoration:
                  BoxDecoration(color: iconBackground, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: iconWidget ?? Icon(icon, color: iconColor, size: 18 * scale),
            ),
            SizedBox(width: AppSpacing.sm * scale),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTypography.labelCaps
                          .copyWith(fontSize: 10 * scale)),
                  // FittedBox instead of a fixed font size + ellipsis: a
                  // short value (e.g. "Split active") would otherwise sit at
                  // the same oversized point size as a long split name that
                  // truncates, when what actually reads well is the value
                  // filling the row's width and shrinking only as far as it
                  // needs to for longer text.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        maxLines: 1,
                        style: (valueStyle ?? AppTypography.bodyMd)
                            .copyWith(color: AppColors.highEmphasis),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: AppSpacing.xs * scale),
            trailing,
          ],
        ),
      ),
    );
  }
}
