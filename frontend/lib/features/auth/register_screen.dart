import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../onboarding/onboarding_repository.dart';
import '../onboarding/widgets/onboarding_step_transition.dart';
import '../onboarding/widgets/question_scaffold.dart';
import 'auth_controller.dart';
import 'complete_profile_flow.dart';
import 'login_screen.dart';
import 'widgets/auth_blob_background.dart';
import 'widgets/oauth_sign_in_buttons.dart';
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
  final _nameFocusNode = FocusNode();
  bool _nameFieldFocused = false;

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
  void initState() {
    super.initState();
    _nameFocusNode.addListener(() {
      if (!mounted) return;
      setState(() => _nameFieldFocused = _nameFocusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameFocusNode.dispose();
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
          MaterialPageRoute(builder: (_) => CompleteProfileFlow(initialProfile: profile)),
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
      body: Stack(
        children: [
          // Present from the first frame (not faded in), and re-laid-out -
          // via AuthBlobBackground's own AnimatedAlign, an ease-in/ease-out
          // glide - only when _stepIndex changes, i.e. on Continue/Back
          // through the email wizard. The OAuth-only name step never
          // advances past index 0, so a Google/Apple sign-up never moves it.
          Positioned.fill(child: AuthBlobBackground(layout: _stepIndex)),
          ClipRect(
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 360),
              reverseDuration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                fit: StackFit.expand,
                children: [
                  for (final child in previousChildren)
                    ExcludeSemantics(child: IgnorePointer(child: child)),
                  if (currentChild != null) currentChild,
                ],
              ),
              // Same two-tier motion as OnboardingFlowScreen: the whole step
              // slides page-like via Transform.translate, while descendants
              // that opt in via OnboardingStepContentTransition
              // (QuestionScaffold's headline/body) get an additional
              // fade/fall - navigation chrome (back button, step counter,
              // CTA) stays solid instead of sliding with everything else.
              transitionBuilder: (child, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  child: child,
                  builder: (context, child) {
                    final incoming =
                        animation.status != AnimationStatus.reverse;
                    final progress = animation.value.clamp(0.0, 1.0);
                    final direction = _lastDirection.toDouble();
                    final horizontalOffset = incoming
                        ? direction * (1 - progress)
                        : -direction * (1 - progress);
                    return Transform.translate(
                      offset: Offset(
                        MediaQuery.sizeOf(context).width * horizontalOffset,
                        0,
                      ),
                      child: OnboardingStepTransitionScope(
                        animation: animation,
                        child: child!,
                      ),
                    );
                  },
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_stepIndex),
                child: _buildStep(auth),
              ),
            ),
          ),
        ],
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
          body: Column(
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
                focusNode: _nameFocusNode,
                style: AppTypography.bodyMd,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    hintText: 'Display name (optional)'),
                onSubmitted: (_) => _continueFromName(),
              ),
            ],
          ),
          ctaLabel: 'Continue',
          onCta: _continueFromName,
          hideBelowCta: _nameFieldFocused,
          belowCta: OAuthSignInButtons(
            isBusy: auth.isBusy,
            onGoogle: () => _withGoogle(auth),
            onApple: () => _withApple(auth),
          ),
          footer: _LoginLink(onTap: _goToLogin),
        );

      case _RegisterStep.email:
        return QuestionScaffold(
          onBack: () => _goBack(auth),
          progressStep: 2,
          progressStepCount: _stepCount,
          headline: "What's your email?",
          body: Column(
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
          ctaLabel: 'Continue',
          onCta: _continueFromEmail,
        );

      case _RegisterStep.password:
        return QuestionScaffold(
          onBack: () => _goBack(auth),
          progressStep: 3,
          progressStepCount: _stepCount,
          headline: 'Choose a password',
          body: Column(
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
          body: Column(
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

/// "Already have an account? Log in" - kept as its own always-visible
/// footer (separate from the OAuth buttons) so it stays on screen even
/// while the name field's focus collapses the OAuth row out of the way.
class _LoginLink extends StatelessWidget {
  final VoidCallback onTap;

  const _LoginLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style:
              AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          children: [
            const TextSpan(text: 'Already have an account? '),
            TextSpan(
              text: 'Log in',
              style: TextStyle(
                  color: AppColors.accent, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
