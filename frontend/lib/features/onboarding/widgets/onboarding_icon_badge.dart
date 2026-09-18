import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders one of the branded assessment icons from
/// `assets/branding/onboarding/` - a transparent glyph (no card background),
/// exported as separate light/dark-theme files (different stroke color per
/// theme) rather than a single tintable glyph. Picks the file matching
/// [Theme.of(context).brightness].
class OnboardingIconBadge extends StatelessWidget {
  /// Base file name, e.g. `'gender_male'` for
  /// `gender_male_light.svg` / `gender_male_dark.svg`.
  final String asset;
  final double size;

  const OnboardingIconBadge(this.asset, {super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).brightness == Brightness.dark
        ? 'dark'
        : 'light';
    return SvgPicture.asset(
      'assets/branding/onboarding/${asset}_$theme.svg',
      width: size,
      height: size,
    );
  }
}
