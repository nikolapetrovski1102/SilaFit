import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/silen_button.dart';

/// The "OR" divider + Google/Apple pill buttons, shared by [RegisterScreen]
/// and [LoginScreen] - both hand the same idToken/identityToken to the same
/// login-or-register backend routes (`POST /auth/login/{google,apple}`), so
/// there's exactly one OAuth entry point to keep in sync rather than two
/// screens each hand-rolling their own copy.
class OAuthSignInButtons extends StatelessWidget {
  final bool isBusy;
  final VoidCallback onGoogle;
  final VoidCallback onApple;

  const OAuthSignInButtons({
    super.key,
    required this.isBusy,
    required this.onGoogle,
    required this.onApple,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: AppColors.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text('OR', style: AppTypography.labelCaps),
            ),
            Expanded(child: Divider(color: AppColors.outlineVariant)),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SecondaryPillButton(
          label: 'Continue with Google',
          icon: Icons.g_mobiledata_rounded,
          onPressed: isBusy ? null : onGoogle,
        ),
        if (!kIsWeb && Platform.isIOS) ...[
          const SizedBox(height: AppSpacing.sm),
          SecondaryPillButton(
            label: 'Continue with Apple',
            icon: Icons.apple_rounded,
            onPressed: isBusy ? null : onApple,
          ),
        ],
      ],
    );
  }
}
