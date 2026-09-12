import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/silen_button.dart';
import '../onboarding/onboarding_repository.dart';
import 'auth_controller.dart';
import 'complete_profile_flow.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// After any successful sign-up (email, Google, or Apple - "same details
  /// will be used" for all three), checks `GET api/profile`. Guests almost
  /// always already have a complete row from first-launch onboarding, so
  /// this is a no-op in the common case; it only re-asks gender/age/height/
  /// weight/goal when a row genuinely doesn't exist yet (an account created
  /// through a path that bypassed onboarding).
  Future<void> _finishAfterAuth() async {
    final repository = OnboardingRepository(context.read<ApiClient>());
    try {
      final profile = await repository.getProfile();
      if (!profile.isComplete && mounted) {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => const CompleteProfileFlow()),
        );
      }
    } catch (_) {
      // Non-fatal - the account itself is already created either way; skip
      // the profile-completion detour rather than block on it.
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _submitEmail(AuthController auth) async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await auth.registerEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      displayName: _nameController.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      await _finishAfterAuth();
    } else {
      _showError(auth.lastError);
    }
  }

  Future<void> _withGoogle(AuthController auth) async {
    final ok = await auth.loginWithGoogle();
    if (!mounted) return;
    if (ok) {
      await _finishAfterAuth();
    } else {
      _showError(auth.lastError);
    }
  }

  Future<void> _withApple(AuthController auth) async {
    final ok = await auth.loginWithApple();
    if (!mounted) return;
    if (ok) {
      await _finishAfterAuth();
    } else {
      _showError(auth.lastError);
    }
  }

  void _showError(String? message) {
    if (message == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    // No AppBar - matches onboarding's chrome-free, circular-back-button
    // language instead of a bar-plus-title.
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.marginMobile),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.sm),
                _BackButton(onTap: () => Navigator.of(context).maybePop()),
                const SizedBox(height: AppSpacing.xxl),
                Text('Lock in your progress', style: AppTypography.headlineLg),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Your guest history carries over automatically.',
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xl),
                TextFormField(
                  controller: _nameController,
                  style: AppTypography.bodyMd,
                  decoration: const InputDecoration(
                      hintText: 'Display name (optional)'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _emailController,
                  style: AppTypography.bodyMd,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(hintText: 'Email'),
                  validator: (value) => (value == null || !value.contains('@'))
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _passwordController,
                  style: AppTypography.bodyMd,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: 'Password'),
                  validator: (value) => (value == null || value.length < 8)
                      ? 'At least 8 characters'
                      : null,
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryPillButton(
                  label: 'Create Account',
                  isLoading: auth.isBusy,
                  onPressed: () => _submitEmail(auth),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(child: Divider(color: AppColors.outlineVariant)),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Text('OR', style: AppTypography.labelCaps),
                    ),
                    Expanded(child: Divider(color: AppColors.outlineVariant)),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                SecondaryPillButton(
                  label: 'Continue with Google',
                  icon: Icons.g_mobiledata_rounded,
                  onPressed: auth.isBusy ? null : () => _withGoogle(auth),
                ),
                const SizedBox(height: AppSpacing.sm),
                SecondaryPillButton(
                  label: 'Continue with Apple',
                  icon: Icons.apple_rounded,
                  onPressed: auth.isBusy ? null : () => _withApple(auth),
                ),
                const SizedBox(height: AppSpacing.xl),
                Center(
                  child: GestureDetector(
                    onTap: () async {
                      final loggedIn = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                      if (context.mounted && loggedIn == true) {
                        Navigator.of(context).pop(true);
                      }
                    },
                    child: RichText(
                      text: TextSpan(
                        style: AppTypography.bodyMd
                            .copyWith(color: AppColors.onSurfaceVariant),
                        children: [
                          const TextSpan(text: 'Already have an account? '),
                          TextSpan(
                              text: 'Log in',
                              style: TextStyle(
                                  color: AppColors.secondary,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Same 40x40 circular back button as `QuestionScaffold`'s, kept local
/// since Auth doesn't share the progress-bar chrome that widget also owns.
class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: AppColors.surfaceContainerHigh),
        child: Icon(Icons.arrow_back, size: 18, color: AppColors.onSurface),
      ),
    );
  }
}
