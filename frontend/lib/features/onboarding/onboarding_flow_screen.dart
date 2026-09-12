import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/session/session_store.dart';
import '../../core/theme/app_colors.dart';
import '../auth/login_screen.dart';
import '../../root_shell.dart';
import 'onboarding_controller.dart';
import 'onboarding_repository.dart';
import 'widgets/intro_slide.dart';
import 'widgets/notification_permission_screen.dart';
import 'widgets/numeric_wheel_picker.dart';
import 'widgets/option_row_selector.dart';
import 'widgets/question_scaffold.dart';

/// The first-launch flow: 2 intro slides, 5 answer questions, then a
/// notification-permission screen. Owns its own [OnboardingController] -
/// nothing outside this flow needs the in-progress answers - and hands off
/// into [RootShell] once it's done, however the user got there (finished,
/// skipped, or logged into an existing account mid-flow).
class OnboardingFlowScreen extends StatelessWidget {
  const OnboardingFlowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) =>
          OnboardingController(OnboardingRepository(ctx.read<ApiClient>())),
      child: const _OnboardingFlowView(),
    );
  }
}

class _OnboardingFlowView extends StatelessWidget {
  const _OnboardingFlowView();

  Future<void> _enterApp(BuildContext context) async {
    await context.read<SessionStore>().markOnboardingComplete();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RootShell()),
    );
  }

  Future<void> _skip(BuildContext context) => _enterApp(context);

  Future<void> _finish(BuildContext context) async {
    final controller = context.read<OnboardingController>();
    await controller.submit();
    if (!context.mounted) return;
    await _enterApp(context);
  }

  Future<void> _goToLogin(BuildContext context) async {
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (loggedIn == true && context.mounted) {
      await _enterApp(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<OnboardingController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          // Each child (incoming and outgoing) gets its own controller in
          // AnimatedSwitcher - the outgoing one runs in reverse - so this is
          // how a single builder tells which side of the swap it's drawing
          // and pushes it the right way: forward nav pulls the new step in
          // from the right while the old one recedes left, back nav mirrors
          // it, like a real navigation stack rather than a plain crossfade.
          final incoming = animation.status != AnimationStatus.reverse;
          final sign = (incoming ? 1 : -1) * controller.lastDirection;
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
          key: ValueKey(controller.step),
          child: _buildStep(context, controller),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, OnboardingController controller) {
    switch (controller.step) {
      case OnboardingStep.intro1:
        return IntroSlide(
          iconMark: const DumbbellIconMark(),
          headline: 'Track every rep.\nSee real progress.',
          subhead:
              'Personalized splits, meal planning, and AI powered monthly insights, built for serious progress.',
          dotIndex: 0,
          dotCount: 2,
          ctaLabel: 'Get started',
          onCta: controller.goNext,
          onSkip: () => _skip(context),
          onLogin: () => _goToLogin(context),
        );

      case OnboardingStep.intro2:
        return IntroSlide(
          iconMark: const BarChartIconMark(),
          headline: 'Splits built around you.',
          subhead:
              'Push, pull, legs, or full body: follow a structured split and watch your strength curve climb week over week.',
          dotIndex: 1,
          dotCount: 2,
          ctaLabel: 'Continue',
          onCta: controller.goNext,
          onSkip: () => _skip(context),
          onLogin: () => _goToLogin(context),
        );

      case OnboardingStep.gender:
        return QuestionScaffold(
          onBack: controller.goBack,
          progressStep: controller.questionProgressStep!,
          progressStepCount: controller.questionStepCount,
          headline: "What's your gender?",
          body: OptionRowSelector(
            options: const ['Male', 'Female', 'Other'],
            selected: controller.gender,
            onSelected: controller.selectGender,
          ),
          ctaLabel: 'Continue',
          onCta: controller.canContinue ? controller.goNext : null,
        );

      case OnboardingStep.age:
        return QuestionScaffold(
          onBack: controller.goBack,
          progressStep: controller.questionProgressStep!,
          progressStepCount: controller.questionStepCount,
          headline: 'How old are you?',
          body: Center(
            child: NumericWheelPicker(
              value: controller.ageYears,
              min: 13,
              max: 100,
              onChanged: controller.setAge,
              suffixLabel: 'years',
            ),
          ),
          ctaLabel: 'Continue',
          onCta: controller.goNext,
        );

      case OnboardingStep.height:
        return QuestionScaffold(
          onBack: controller.goBack,
          progressStep: controller.questionProgressStep!,
          progressStepCount: controller.questionStepCount,
          headline: "What's your height?",
          body: Center(
            child: NumericWheelPicker(
              value: controller.heightCm,
              min: 100,
              max: 250,
              onChanged: controller.setHeightCm,
              valueColor: AppColors.onSurface,
              unitOptions: const ['cm', 'ft'],
              selectedUnit: controller.heightUnit,
              onUnitChanged: controller.setHeightUnit,
              displayFormatter: (cm) =>
                  _formatHeight(cm, controller.heightUnit),
            ),
          ),
          ctaLabel: 'Continue',
          onCta: controller.goNext,
        );

      case OnboardingStep.weight:
        return QuestionScaffold(
          onBack: controller.goBack,
          progressStep: controller.questionProgressStep!,
          progressStepCount: controller.questionStepCount,
          headline: "What's your current weight?",
          body: Center(
            child: NumericWheelPicker(
              value: controller.weightKg,
              min: 30,
              max: 300,
              onChanged: controller.setWeightKg,
              valueColor: AppColors.onSurface,
              unitOptions: const ['kg', 'lb'],
              selectedUnit: controller.weightUnit,
              onUnitChanged: controller.setWeightUnit,
              displayFormatter: (kg) =>
                  _formatWeight(kg, controller.weightUnit),
            ),
          ),
          ctaLabel: 'Continue',
          onCta: controller.goNext,
        );

      case OnboardingStep.goal:
        return QuestionScaffold(
          onBack: controller.goBack,
          progressStep: controller.questionProgressStep!,
          progressStepCount: controller.questionStepCount,
          headline: "What's your main goal?",
          body: OptionRowSelector(
            options: const ['BuildMuscle', 'LoseFat', 'MaintainActive'],
            labelFor: (value) => _goalLabels[value] ?? value,
            selected: controller.goal,
            onSelected: controller.selectGoal,
          ),
          ctaLabel: 'Continue',
          onCta: controller.canContinue ? controller.goNext : null,
        );

      case OnboardingStep.notifications:
        return NotificationPermissionScreen(
          onBack: controller.goBack,
          progressStep: controller.questionProgressStep!,
          progressStepCount: controller.questionStepCount,
          isSubmitting: controller.isSubmitting,
          onFinish: () => _finish(context),
        );
    }
  }
}

// Backend-canonical goal value -> the reference screenshot's display copy.
const _goalLabels = {
  'BuildMuscle': 'Build muscle',
  'LoseFat': 'Lose fat',
  'MaintainActive': 'Maintain and stay active',
};

// Display-only unit conversion for the height/weight pickers - canonical
// storage (and the picker's drag granularity) always stays cm/kg; only the
// on-screen label changes when the ft/lb pill is selected.
String _formatHeight(int cm, String unit) {
  if (unit == 'cm') return '$cm';
  final totalInches = (cm / 2.54).round();
  final feet = totalInches ~/ 12;
  final inches = totalInches % 12;
  return "$feet'$inches\"";
}

String _formatWeight(int kg, String unit) {
  if (unit == 'kg') return '$kg';
  return '${(kg * 2.20462).round()}';
}
