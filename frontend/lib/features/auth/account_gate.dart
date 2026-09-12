import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/silen_button.dart';
import '../onboarding/widgets/intro_slide.dart' show OnboardingIconMark;
import 'auth_controller.dart';
import 'register_screen.dart';

/// The single place that implements "when the user wants to track
/// progress, buy, or use another gated feature, require an account".
///
/// Call [AccountGate.ensure] before navigating to a gated screen or firing
/// a gated action (Progress tab, Plan purchase, Split activation-for-real
/// if you decide to gate it later). It returns true only once the caller
/// actually holds a Registered-tier session.
class AccountGate {
  AccountGate._();

  static Future<bool> ensure(BuildContext context) async {
    final auth = context.read<AuthController>();
    if (auth.isRegistered) return true;

    final createdAccount = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _AccountRequiredSheet()),
    );
    return createdAccount ?? false;
  }
}

class _AccountRequiredSheet extends StatelessWidget {
  const _AccountRequiredSheet();

  @override
  Widget build(BuildContext context) {
    // No AppBar - matches onboarding's chrome-free language; the icon mark
    // sits in the same lime-outlined circle onboarding's intro slides use.
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: OnboardingIconMark(
                  size: 96,
                  child: Icon(Icons.lock_outline_rounded,
                      color: AppColors.accent, size: 36),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Create a free account',
                  style: AppTypography.headlineLg, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Your guest progress carries over - this just locks it to an account so you can track it long-term, purchase a plan, or use AI features.',
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryPillButton(
                label: 'Create Account',
                icon: Icons.arrow_forward_rounded,
                onPressed: () async {
                  final linked = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  );
                  if (context.mounted && linked == true) {
                    Navigator.of(context).pop(true);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryPillButton(
                  label: 'Not Now',
                  onPressed: () => Navigator.of(context).pop(false)),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}
