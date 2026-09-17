import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Soft blurred accent circles behind the login/register content. They're
/// already in place at first frame - no fade/pop-in - so they read as part
/// of the backdrop rather than a decoration that animates on ("in advance").
///
/// [layout] picks which of [_layouts]'s preset positions the circles rest
/// at. [LoginScreen] passes a constant, so its circles never move. The
/// email registration wizard passes its current step index instead, so
/// each step change ([RegisterScreen._goTo]) glides them to the next
/// layout - [AnimatedAlign]'s own ease-in/ease-out curve - then they hold
/// still again until the next step. The OAuth-only path never advances
/// past step 0, so a Google/Apple sign-up never triggers this at all.
class AuthBlobBackground extends StatelessWidget {
  final int layout;

  const AuthBlobBackground({super.key, this.layout = 0});

  static const _layouts = <List<Alignment>>[
    [Alignment(-1.35, -1.15), Alignment(1.45, -0.25), Alignment(0.15, 1.35)],
    [Alignment(1.35, -1.05), Alignment(-1.25, 0.25), Alignment(0.55, 1.4)],
    [Alignment(-1.1, -0.55), Alignment(1.15, 0.55), Alignment(-0.35, 1.4)],
    [Alignment(0.95, -1.25), Alignment(-1.45, 0.55), Alignment(1.2, 1.25)],
    // Register/login's step layouts above all rest their third blob well
    // past the bottom edge (y >= 1.25) - fine there, since QuestionScaffold's
    // CTA/footer content always occupies that space anyway. Full-page forms
    // like SplitBuilderScreen/MySplitsScreen scroll to whatever height their
    // content needs, so that third blob is often the only color that would
    // ever reach the lower half of the screen - pulled up to a more central
    // y and blown up in `_sizeOverrides`/`_alphaOverrides` below so its glow
    // actually bridges the gap between short content and the true bottom,
    // instead of just warming the very edge of it.
    [Alignment(-1.2, -1.05), Alignment(1.3, -0.15), Alignment(-0.25, 0.55)],
  ];

  static const _defaultSizes = [260.0, 220.0, 240.0];
  static const _defaultAlphas = [0.32, 0.32, 0.32];

  // Layout 3's third blob is enlarged/brightened relative to the shared
  // defaults - see the comment on that layout's alignment above.
  static const _sizeOverrides = {3: [260.0, 220.0, 460.0]};
  static const _alphaOverrides = {3: [0.32, 0.32, 0.4]};

  @override
  Widget build(BuildContext context) {
    final index = layout % _layouts.length;
    final targets = _layouts[index];
    final sizes = _sizeOverrides[index] ?? _defaultSizes;
    final alphas = _alphaOverrides[index] ?? _defaultAlphas;
    final colors = [
      AppColors.accent,
      AppColors.secondary,
      AppColors.tertiaryContainer,
    ];

    return IgnorePointer(
      child: ClipRect(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
          child: Stack(
            children: [
              for (var i = 0; i < targets.length; i++)
                AnimatedAlign(
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeInOut,
                  alignment: targets[i],
                  child: Container(
                    width: sizes[i],
                    height: sizes[i],
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors[i].withValues(alpha: alphas[i]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
