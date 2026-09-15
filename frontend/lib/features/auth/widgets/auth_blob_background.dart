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
  ];

  static const _sizes = [260.0, 220.0, 240.0];

  @override
  Widget build(BuildContext context) {
    final targets = _layouts[layout % _layouts.length];
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
                    width: _sizes[i],
                    height: _sizes[i],
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors[i].withValues(alpha: 0.32),
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
