import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/session/session_store.dart';
import '../../core/theme/app_colors.dart';
import '../auth/login_screen.dart';
import '../auth/widgets/auth_blob_background.dart';
import '../notifications/notifications_repository.dart';
import '../notifications/push_messaging_service.dart';
import '../../root_shell.dart';
import 'onboarding_controller.dart';
import 'onboarding_repository.dart';
import 'widgets/age_wheel_picker.dart';
import 'widgets/intro_slide.dart';
import 'widgets/notification_permission_screen.dart';
import 'widgets/numeric_wheel_picker.dart';
import 'widgets/onboarding_step_transition.dart';
import 'widgets/option_row_selector.dart';
import 'widgets/question_scaffold.dart';
import 'widgets/training_preference_question.dart';

/// The first-launch flow: 2 intro slides, 9 profile questions, then a
/// notification-permission screen. Owns its own [OnboardingController] -
/// nothing outside this flow needs the in-progress answers - and hands off
/// into [RootShell] once it's done, however the user got there (finished,
/// skipped, or logged into an existing account mid-flow).
class OnboardingFlowScreen extends StatelessWidget {
  /// Set only by the Settings screen's dev-only onboarding replay toggle, so
  /// completing this replay re-runs the split recommender even if the
  /// current active split was manually picked. Never set for a real
  /// first-launch flow.
  final bool forceSplitReassign;

  const OnboardingFlowScreen({super.key, this.forceSplitReassign = false});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => OnboardingController(
        OnboardingRepository(ctx.read<ApiClient>()),
        ctx.read<NotificationsRepository>(),
        pushMessaging: ctx.read<PushMessagingService>(),
      ),
      child: _OnboardingFlowView(forceSplitReassign: forceSplitReassign),
    );
  }
}

class _OnboardingFlowView extends StatelessWidget {
  final bool forceSplitReassign;

  const _OnboardingFlowView({this.forceSplitReassign = false});

  Future<void> _enterApp(BuildContext context) async {
    await context.read<SessionStore>().markOnboardingComplete();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RootShell()),
    );
  }

  Future<void> _skip(BuildContext context) => _enterApp(context);

  Future<void> _finish(BuildContext context, bool notificationsAllowed) async {
    final controller = context.read<OnboardingController>();
    final saved =
        await controller.submit(forceSplitReassign: forceSplitReassign);
    if (!context.mounted) return;
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(controller.lastError ?? 'Please complete your profile.'),
      ));
      return;
    }
    await controller.submitNotificationOptIn(notificationsAllowed);
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
      body: Stack(
        children: [
          // Same premium floating-blob backdrop as login/register, present
          // from the first frame and re-laid-out - via AuthBlobBackground's
          // own AnimatedAlign glide - on every step change, so onboarding
          // shares that screen's dynamic-background language end to end.
          Positioned.fill(child: AuthBlobBackground(layout: controller.stepIndex)),
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
              // Screen navigation stays route-like and predictable. The softer
              // fade/fall treatment is supplied to opted-in content descendants,
              // never to the background, navigation chrome or bottom CTA.
              transitionBuilder: (child, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  child: child,
                  builder: (context, child) {
                    final incoming =
                        animation.status != AnimationStatus.reverse;
                    final progress = animation.value.clamp(0.0, 1.0);
                    final direction = controller.lastDirection.toDouble();
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
                key: ValueKey(controller.step),
                child: _buildStep(context, controller),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(BuildContext context, OnboardingController controller) {
    switch (controller.step) {
      case OnboardingStep.intro1:
        return IntroSlide(
          iconMark: const DumbbellIconMark(),
          headline: 'Track every rep.\nSee real progress.',
          subhead: 'Workouts, meals, and progress in one place.',
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
          headline: 'Make it your plan.',
          subhead:
              'Answer a few quick questions to find workouts that fit your life.',
          dotIndex: 1,
          dotCount: 2,
          ctaLabel: 'Continue',
          onCta: controller.goNext,
          onBack: controller.goBack,
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
            badgeAssetFor: (value) => const {
              'Male': 'gender_male',
              'Female': 'gender_female',
              'Other': 'gender_other',
            }[value],
          ),
          ctaLabel: 'Continue',
          onCta: controller.canContinue ? controller.goNext : null,
        );

      case OnboardingStep.age:
        return QuestionScaffold(
          onBack: controller.goBack,
          progressStep: controller.questionProgressStep!,
          progressStepCount: controller.questionStepCount,
          headline: 'What is your age?',
          body: Center(
            child: AgeWheelPicker(
              value: controller.ageYears,
              min: 13,
              max: 100,
              onChanged: controller.setAge,
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
            badgeAssetFor: (value) => const {
              'BuildMuscle': 'goal_build_muscle',
              'LoseFat': 'goal_lose_fat',
              'MaintainActive': 'goal_stay_active',
            }[value],
          ),
          ctaLabel: 'Continue',
          onCta: controller.canContinue ? controller.goNext : null,
        );

      case OnboardingStep.trainingDays:
      case OnboardingStep.trainingExperience:
      case OnboardingStep.equipmentAccess:
      case OnboardingStep.dailyActivity:
        return TrainingPreferenceQuestion(
          controller: controller,
          step: controller.step,
          progressStep: controller.questionProgressStep!,
          progressStepCount: controller.questionStepCount,
          onBack: controller.goBack,
          onNext: controller.goNext,
        );

      case OnboardingStep.notifications:
        return NotificationPermissionScreen(
          onBack: controller.goBack,
          isSubmitting: controller.isSubmitting,
          onFinish: (allowed) => _finish(context, allowed),
        );
    }
  }
}

// Backend-canonical goal value -> the reference screenshot's display copy.
const _goalLabels = {
  'BuildMuscle': 'Build muscle',
  'LoseFat': 'Lose fat',
  'MaintainActive': 'Stay active',
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
