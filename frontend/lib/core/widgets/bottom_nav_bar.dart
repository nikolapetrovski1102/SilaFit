import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart' show AppRadius, AppSpacing;
import '../theme/app_typography.dart';

class NavTab {
  final String label;
  final IconData icon;

  const NavTab(this.label, this.icon);
}

const kSilenNavTabs = [
  NavTab('Home', Icons.space_dashboard_rounded),
  NavTab('Progress', Icons.show_chart_rounded),
  NavTab('Nutrition', Icons.restaurant_rounded),
  NavTab('Settings', Icons.settings_rounded),
];

/// The floating, fully-rounded bottom tab bar shared by all four top-level
/// screens - a pill that sits with margin off every edge (matching the
/// reference mockups' `rounded-full` nav, not a full-bleed rectangle), icon
/// only per tab, with the active tab expanding into a lime pill that also
/// shows its name. Inactive tabs stay icon-only and carry a [Tooltip]
/// instead for accessibility/discoverability.
class SilenBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlobalKey>? tabKeys;

  const SilenBottomNavBar(
      {super.key,
      required this.currentIndex,
      required this.onTap,
      this.tabKeys});

  // iOS gets the frosted-glass tab bar (BackdropFilter blur behind a
  // translucent fill), matching the system UIKit tab bar treatment. The
  // blur is applied to the *full-width bottom band* (edge to edge, full
  // reserved height), not just clipped to the pill's own rounded bounds -
  // otherwise the haze is confined to a thin rounded strip and barely
  // reads as blur at all. The pill then floats on top of that blurred
  // band, unblurred itself, with its usual side margins. Android skips the
  // blur entirely - BackdropFilter is comparatively expensive there and the
  // effect reads inconsistently across GPUs/skia backends.
  bool get _blurred => !kIsWeb && Platform.isIOS;

  // Since Android 15 (targetSdk 35), the platform enforces edge-to-edge and
  // ignores `systemNavigationBarColor` (see the `AnnotatedRegion` in
  // `main.dart`) - the real system nav bar is always transparent now, no
  // matter what that's set to. With `extendBody: true` that means content
  // used to just scroll straight up to the physical nav buttons with
  // nothing behind them. So on Android specifically: give the pill a solid
  // (unblurred) fill instead of a fully transparent one, and fade the band
  // behind/around it into the page background further down (see `build`)
  // so the transition into that always-transparent system bar reads as a
  // deliberate scrim rather than a hard cut to raw content.
  bool get _solidAndroidFill => !kIsWeb && Platform.isAndroid;

  /// Fixed height of the pill itself, excluding the safe-area inset and
  /// hairline gap added below it. Exposed so [RootShell] can run its
  /// [Scaffold] with `extendBody: true` (required for the transparency/blur
  /// above to actually show scrolled content underneath, instead of just
  /// the flat page background) while every tab still reserves this same
  /// footprint as bottom padding on its own scrollable content - otherwise
  /// list items would end up permanently hidden under the pill rather than
  /// sliding past behind it.
  static const double pillHeight = 56;

  /// Total footprint - pill height plus the bottom-safe-area inset and the
  /// hairline gap [build] pads the pill by - that a tab's own content
  /// should reserve as trailing space once the [Scaffold] extends its body
  /// under this bar.
  static double reservedHeight(BuildContext context) =>
      pillHeight + AppSpacing.xxs + MediaQuery.of(context).padding.bottom;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final bandHeight = pillHeight + AppSpacing.xxs + bottomInset;
    final pill = Container(
      height: pillHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: _blurred
            ? AppColors.surfaceContainer.withOpacity(0.72)
            : _solidAndroidFill
                ? AppColors.surfaceContainer
                : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppColors.outlineVariant.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < kSilenNavTabs.length; i++)
            _NavItem(
                key: tabKeys != null && i < tabKeys!.length ? tabKeys![i] : null,
                tab: kSilenNavTabs[i],
                selected: i == currentIndex,
                onTap: () => onTap(i)),
        ],
      ),
    );
    // The floating pill itself, inset from the screen edges/home indicator -
    // this is what actually renders (border, fill, icons), unblurred, on
    // top of whatever sits behind it. Kept tight (just the safe-area inset
    // plus a hairline of cushion) so the pill sits at the very bottom of the
    // display and the reserved chrome band behind it stays as small as the
    // pill itself - see [AppResponsive.referenceHeight], which is
    // calibrated against this exact height.
    final pillFloat = Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.marginMobile,
        right: AppSpacing.marginMobile,
        bottom: bottomInset + AppSpacing.xxs,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: pill,
      ),
    );
    if (!_blurred) {
      if (!_solidAndroidFill) {
        // Web/desktop: unchanged, plainly transparent - no OS nav bar to
        // worry about blending into.
        return SizedBox(height: bandHeight, child: pillFloat);
      }
      // Android: fade the reserved band into the page background towards
      // the bottom, so scrolled content eases into the (always-transparent,
      // see `_solidAndroidFill`) system nav bar instead of cutting straight
      // into it. Stops start the fade around the pill's own vertical
      // center so the gradient is doing its work mostly *behind* the pill
      // and below it, not visibly washing out content still above the pill.
      return SizedBox(
        height: bandHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.background.withOpacity(0),
                      AppColors.background.withOpacity(0.85),
                      AppColors.background,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            pillFloat,
          ],
        ),
      );
    }
    // Blur the full-width bottom band - edge to edge, full reserved height -
    // rather than clipping the blur to just the pill's own rounded bounds.
    // ClipRect constrains BackdropFilter (which otherwise blurs unbounded)
    // to exactly that band; the pill then paints on top of it, crisp. Kept
    // to a plain ClipRect + BackdropFilter with no extra scrim/mask on top -
    // wrapping this in a ShaderMask/Opacity to feather the top edge forces
    // the subtree onto its own offscreen layer (`saveLayer`), and
    // BackdropFilter samples whatever's on the layer immediately behind it
    // at composite time - on an empty freshly-started offscreen layer
    // that's nothing, so the "blur" ends up blurring a blank transparent
    // buffer instead of the real scrolled content.
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: SizedBox(
          height: bandHeight,
          width: double.infinity,
          child: pillFloat,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final NavTab tab;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem(
      {super.key,
      required this.tab,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.onAccent : AppColors.onSurfaceVariant;
    return Tooltip(
      message: tab.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tab.icon, color: color, size: 20),
              if (selected) ...[
                const SizedBox(width: 6),
                Text(
                  tab.label,
                  style: AppTypography.labelSm
                      .copyWith(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
