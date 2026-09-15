import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/silen_button.dart';
import '../onboarding/onboarding_repository.dart';
import 'auth_controller.dart';
import 'complete_profile_flow.dart';
import 'register_screen.dart';
import 'widgets/auth_blob_background.dart';
import 'widgets/oauth_sign_in_buttons.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late final AnimationController _entrance;
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
    );
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only ever fires the entrance once - `forward()` on an already-forward
    // controller is a no-op, and jumping straight to 1 when the platform has
    // reduced motion enabled skips the animation without skipping the state.
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
    } else if (_entrance.status == AnimationStatus.dismissed) {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _shake.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Staggered slices of the shared entrance controller - each group starts
  // a little after the previous one so the screen builds itself up top to
  // bottom instead of every element fading in at once.
  Animation<double> _stagger(double start, double end) => CurvedAnimation(
        parent: _entrance,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );

  /// After any successful sign-in (email, Google, or Apple), checks
  /// `GET api/profile`. An email/password account is only ever reachable
  /// here once it already exists with a complete profile, but Google/Apple
  /// can silently create a brand-new account on first use - same as
  /// RegisterScreen's identical method - so this still has to check.
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
      // Non-fatal - the session itself is already established either way;
      // skip the profile-completion detour rather than block on it.
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _submit(AuthController auth) async {
    if (!_formKey.currentState!.validate()) {
      _shakeFields();
      return;
    }
    final ok = await auth.loginEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      _shakeFields();
      if (auth.lastError != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(auth.lastError!)));
      }
    }
  }

  Future<void> _withGoogle(AuthController auth) async {
    final ok = await auth.loginWithGoogle();
    if (!mounted) return;
    if (ok) {
      await _finishAfterAuth();
    } else if (auth.lastError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(auth.lastError!)));
    }
  }

  Future<void> _withApple(AuthController auth) async {
    final ok = await auth.loginWithApple();
    if (!mounted) return;
    if (ok) {
      await _finishAfterAuth();
    } else if (auth.lastError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(auth.lastError!)));
    }
  }

  Future<void> _goToRegister() async {
    final registered = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
    if (mounted && registered == true) {
      Navigator.of(context).pop(true);
    }
  }

  // A wrong email/password reads as a reject-shake on the fields - same
  // decaying-sine-wave feel as the register wizard's OTP boxes - instead of
  // the snackbar being the only signal something was wrong.
  void _shakeFields() {
    HapticFeedback.mediumImpact();
    _shake.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    final headerIn = _stagger(0.0, 0.55);
    final fieldsIn = _stagger(0.2, 0.75);
    final ctaIn = _stagger(0.4, 1.0);

    // Once the keyboard is up, a centered column re-centers itself into the
    // shrunken viewport on every animation frame as the keyboard slides in,
    // which is what was carrying the email field down under it. Anchoring
    // to the bottom instead keeps the column's bottom edge glued to the
    // viewport's bottom edge - which is exactly the keyboard's top edge,
    // every frame - so content tracks the keyboard up with no jitter and
    // no gap, and any overflow scrolls off the top (the header) rather
    // than hiding the field being typed into. Centered look is only for
    // the resting, keyboard-down state.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    // No AppBar - matches onboarding's chrome-free, circular-back-button
    // language instead of a bar-plus-title.
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: AuthBlobBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.marginMobile),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.sm),
                  _BackButton(onTap: () => Navigator.of(context).maybePop()),
                  Expanded(
                    child: LayoutBuilder(builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              minHeight: constraints.maxHeight),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisAlignment: keyboardOpen
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.center,
                              children: [
                                _FadeUp(
                                  animation: headerIn,
                                  child: Text('Welcome back',
                                      style: AppTypography.headlineLg),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                _FadeUp(
                                  animation: headerIn,
                                  child: Text(
                                    'Log in to sync your training history across devices.',
                                    style: AppTypography.bodyMd.copyWith(
                                        color: AppColors.onSurfaceVariant),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xxl),
                                _FadeUp(
                                  animation: fieldsIn,
                                  child: _ShakeOnFail(
                                    shake: _shake,
                                    child: Column(
                                      children: [
                                        TextFormField(
                                          controller: _emailController,
                                          style: AppTypography.bodyMd,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          textInputAction:
                                              TextInputAction.next,
                                          // Forces the Flutter-drawn toolbar
                                          // instead of iOS 16's native
                                          // SystemContextMenu, which only
                                          // allows one instance visible at a
                                          // time and throws when focus moves
                                          // to the next field before it's
                                          // done dismissing.
                                          contextMenuBuilder:
                                              (context, editableTextState) =>
                                                  AdaptiveTextSelectionToolbar
                                                      .editableText(
                                            editableTextState:
                                                editableTextState,
                                          ),
                                          decoration: const InputDecoration(
                                              hintText: 'Email'),
                                          validator: (value) => (value ==
                                                      null ||
                                                  !value.contains('@'))
                                              ? 'Enter a valid email'
                                              : null,
                                        ),
                                        const SizedBox(
                                            height: AppSpacing.sm),
                                        TextFormField(
                                          controller: _passwordController,
                                          style: AppTypography.bodyMd,
                                          obscureText: true,
                                          textInputAction:
                                              TextInputAction.done,
                                          contextMenuBuilder:
                                              (context, editableTextState) =>
                                                  AdaptiveTextSelectionToolbar
                                                      .editableText(
                                            editableTextState:
                                                editableTextState,
                                          ),
                                          decoration: const InputDecoration(
                                              hintText: 'Password'),
                                          onFieldSubmitted: (_) =>
                                              _submit(auth),
                                          validator: (value) =>
                                              (value == null ||
                                                      value.isEmpty)
                                                  ? 'Enter your password'
                                                  : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xl),
                                _FadeUp(
                                  animation: ctaIn,
                                  child: PrimaryPillButton(
                                      label: 'Log In',
                                      isLoading: auth.isBusy,
                                      onPressed: () => _submit(auth)),
                                ),
                                // Collapsed while the keyboard is up: with
                                // the viewport already shrunk, keeping the
                                // OAuth row around fights the fields for
                                // space (that's what was overflowing) and
                                // there's nothing to tap while typing anyway.
                                // Reappears once the keyboard closes.
                                AnimatedSize(
                                  duration:
                                      const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topCenter,
                                  child: keyboardOpen
                                      ? const SizedBox(width: double.infinity)
                                      : Column(
                                          children: [
                                            const SizedBox(
                                                height: AppSpacing.lg),
                                            _FadeUp(
                                              animation: ctaIn,
                                              child: OAuthSignInButtons(
                                                isBusy: auth.isBusy,
                                                onGoogle: () =>
                                                    _withGoogle(auth),
                                                onApple: () =>
                                                    _withApple(auth),
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                _FadeUp(
                                  animation: ctaIn,
                                  child: GestureDetector(
                                    onTap: _goToRegister,
                                    child: RichText(
                                      textAlign: TextAlign.center,
                                      text: TextSpan(
                                        style: AppTypography.bodyMd.copyWith(
                                            color:
                                                AppColors.onSurfaceVariant),
                                        children: [
                                          const TextSpan(
                                              text:
                                                  "Don't have an account? "),
                                          TextSpan(
                                            text: 'Sign up',
                                            style: TextStyle(
                                                color: AppColors.accent,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades and rises a child in from [distance] logical pixels below its final
/// position, driven by an already-running (or reduced-motion, already-at-1)
/// [animation] slice - see `_LoginScreenState._stagger`.
class _FadeUp extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final double distance;

  const _FadeUp({
    required this.animation,
    required this.child,
    this.distance = 12,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) => Opacity(
        opacity: animation.value,
        child: Transform.translate(
          offset: Offset(0, distance * (1 - animation.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Same decaying-sine-wave reject-shake as `OtpCodeField`, driven by an
/// externally-triggered [shake] controller instead of owning its own -
/// [_LoginScreenState] fires it on both client-side validation failures and
/// a rejected server response, so one shake covers both.
class _ShakeOnFail extends StatelessWidget {
  final AnimationController shake;
  final Widget child;

  const _ShakeOnFail({required this.shake, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shake,
      child: child,
      builder: (context, child) {
        final progress = shake.value;
        final dx = math.sin(progress * math.pi * 6) * 8 * (1 - progress);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

/// Same squircle back button as `QuestionScaffold`'s - kept local since
/// Auth doesn't share the progress-bar chrome that widget also owns.
class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: Material(
        color: Colors.transparent,
        child: Ink(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.48),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(17),
            child: Center(
              child: Icon(Icons.chevron_left_rounded,
                  size: 28, color: AppColors.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
