import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/silen_button.dart';
import '../onboarding/onboarding_repository.dart';
import '../onboarding/widgets/question_scaffold.dart';
import 'auth_controller.dart';
import 'complete_profile_flow.dart';
import 'login_screen.dart';
import 'widgets/otp_code_field.dart';

/// Registration entry point. Google/Apple sign-up stays a single tap, right
/// on the first step; registering with an email/password instead becomes a
/// 4-step wizard (name -> email -> password -> emailed code) sharing
/// onboarding's [QuestionScaffold] chrome, since email is the one path that
/// needs a real server round-trip in the middle (send a code, confirm it)
/// before the account exists.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

enum _RegisterStep { name, email, password, verify }

class _RegisterScreenState extends State<RegisterScreen> {
  static final _stepCount = _RegisterStep.values.length;
  static const _resendCooldown = Duration(seconds: 30);

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _otpController = OtpCodeFieldController();

  int _stepIndex = 0;
  // 1 for a forward step (Continue), -1 for back - read by the step
  // transition to slide the incoming step in from the right or left,
  // mirroring the onboarding flow's own AnimatedSwitcher direction logic.
  int _lastDirection = 1;
  String _code = '';
  String? _fieldError;
  Timer? _resendTimer;
  int _resendSecondsLeft = 0;

  _RegisterStep get _step => _RegisterStep.values[_stepIndex];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _goTo(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _lastDirection = index > _stepIndex ? 1 : -1;
      _stepIndex = index;
      _fieldError = null;
    });
  }

  void _goBack(AuthController auth) {
    if (_stepIndex == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    if (_step == _RegisterStep.verify) {
      _resendTimer?.cancel();
      auth.cancelEmailVerification();
    }
    _goTo(_stepIndex - 1);
  }

  void _continueFromName() => _goTo(_stepIndex + 1);

  void _continueFromEmail() {
    if (!_emailController.text.contains('@')) {
      setState(() => _fieldError = 'Enter a valid email');
      return;
    }
    _goTo(_stepIndex + 1);
  }

  Future<void> _submitPassword(AuthController auth) async {
    if (_passwordController.text.length < 8) {
      setState(() => _fieldError = 'At least 8 characters');
      return;
    }
    final ok = await auth.startEmailRegistration(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      displayName: _nameController.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      _goTo(_stepIndex + 1);
      _startResendCooldown();
    } else {
      _showError(auth.lastError);
    }
  }

  Future<void> _submitCode(AuthController auth) async {
    final ok = await auth.verifyEmailRegistration(_code);
    if (!mounted) return;
    if (ok) {
      await _finishAfterAuth();
    } else {
      // A wrong/expired code shakes the boxes and clears them for a retry
      // in addition to the usual error toast, rather than leaving the
      // rejected digits sitting there looking accepted.
      setState(() => _code = '');
      _otpController.shakeAndClear();
      _showError(auth.lastError);
    }
  }

  Future<void> _resendCode(AuthController auth) async {
    final ok = await auth.resendEmailVerification();
    if (!mounted) return;
    if (ok) {
      _startResendCooldown();
    } else {
      _showError(auth.lastError);
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsLeft = _resendCooldown.inSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendSecondsLeft -= 1);
      if (_resendSecondsLeft <= 0) timer.cancel();
    });
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

  Future<void> _goToLogin() async {
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (mounted && loggedIn == true) {
      Navigator.of(context).pop(true);
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
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        // See OnboardingFlowScreen's identical builder for why each side
        // needs its own sign: AnimatedSwitcher hands the outgoing child an
        // animation running in reverse, so this is what makes the swap read
        // as forward/back navigation instead of a plain crossfade.
        transitionBuilder: (child, animation) {
          final incoming = animation.status != AnimationStatus.reverse;
          final sign = (incoming ? 1 : -1) * _lastDirection;
          final offset = Tween<Offset>(
            begin: Offset(0.22 * sign, 0),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(_stepIndex),
          child: _buildStep(auth),
        ),
      ),
    );
  }

  Widget _buildStep(AuthController auth) {
    switch (_step) {
      case _RegisterStep.name:
        return QuestionScaffold(
          onBack: () => _goBack(auth),
          progressStep: 1,
          progressStepCount: _stepCount,
          headline: 'Lock in your progress',
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Your guest history carries over automatically.',
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xl),
                TextField(
                  controller: _nameController,
                  style: AppTypography.bodyMd,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                      hintText: 'Display name (optional)'),
                  onSubmitted: (_) => _continueFromName(),
                ),
              ],
            ),
          ),
          ctaLabel: 'Continue',
          onCta: _continueFromName,
          belowCta: _AlternateSignupBlock(
            isBusy: auth.isBusy,
            onGoogle: () => _withGoogle(auth),
            onApple: () => _withApple(auth),
            onLogin: _goToLogin,
          ),
        );

      case _RegisterStep.email:
        return QuestionScaffold(
          onBack: () => _goBack(auth),
          progressStep: 2,
          progressStepCount: _stepCount,
          headline: "What's your email?",
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _emailController,
                  style: AppTypography.bodyMd,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Email'),
                  onSubmitted: (_) => _continueFromEmail(),
                ),
                if (_fieldError != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(_fieldError!,
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.error)),
                ],
              ],
            ),
          ),
          ctaLabel: 'Continue',
          onCta: _continueFromEmail,
        );

      case _RegisterStep.password:
        return QuestionScaffold(
          onBack: () => _goBack(auth),
          progressStep: 3,
          progressStepCount: _stepCount,
          headline: 'Choose a password',
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _passwordController,
                  style: AppTypography.bodyMd,
                  obscureText: true,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(hintText: 'Password'),
                  onSubmitted: (_) => _submitPassword(auth),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _fieldError ?? 'At least 8 characters.',
                  style: AppTypography.bodySm.copyWith(
                      color: _fieldError != null
                          ? AppColors.error
                          : AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          ctaLabel: 'Create Account',
          ctaLoading: auth.isBusy,
          onCta: () => _submitPassword(auth),
        );

      case _RegisterStep.verify:
        return QuestionScaffold(
          onBack: () => _goBack(auth),
          progressStep: 4,
          progressStepCount: _stepCount,
          headline: 'Check your email',
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enter the 6-digit code we sent to '
                  '${_emailController.text.trim()}.',
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xl),
                OtpCodeField(
                  controller: _otpController,
                  onChanged: (value) => setState(() => _code = value),
                  onCompleted: (_) => _submitCode(auth),
                ),
              ],
            ),
          ),
          ctaLabel: 'Verify',
          ctaLoading: auth.isBusy,
          onCta: _code.length == 6 ? () => _submitCode(auth) : null,
          belowCta: Center(
            child: TextButton(
              onPressed: _resendSecondsLeft > 0 || auth.isBusy
                  ? null
                  : () => _resendCode(auth),
              child: Text(
                _resendSecondsLeft > 0
                    ? 'Resend code in ${_resendSecondsLeft}s'
                    : "Didn't get a code? Resend",
                style: AppTypography.bodyMd.copyWith(
                  color: _resendSecondsLeft > 0
                      ? AppColors.onSurfaceVariant
                      : AppColors.secondary,
                ),
              ),
            ),
          ),
        );
    }
  }
}

/// The Google/Apple/"already have an account" block shown under the name
/// step's CTA - unlike email, both OAuth paths create the account (or link
/// it to the current guest) in a single tap, with no further wizard steps.
class _AlternateSignupBlock extends StatelessWidget {
  final bool isBusy;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onLogin;

  const _AlternateSignupBlock({
    required this.isBusy,
    required this.onGoogle,
    required this.onApple,
    required this.onLogin,
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
        const SizedBox(height: AppSpacing.lg),
        GestureDetector(
          onTap: onLogin,
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
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
