import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../notifications/notifications_repository.dart';
import '../onboarding/onboarding_controller.dart';
import '../onboarding/onboarding_repository.dart';
import '../onboarding/widgets/age_wheel_picker.dart';
import '../onboarding/onboarding_models.dart';
import '../onboarding/widgets/numeric_wheel_picker.dart';
import '../onboarding/widgets/onboarding_step_transition.dart';
import '../onboarding/widgets/option_row_selector.dart';
import '../onboarding/widgets/question_scaffold.dart';
import '../onboarding/widgets/training_preference_question.dart';

/// Walks a just-registered user through the same onboarding questions
/// (gender/age/height/weight/goal) when `GET api/profile` comes back
/// incomplete for their account - the only realistic way to hit this is an
/// account created through a path that bypassed first-launch onboarding
/// (e.g. a pre-onboarding install). Reuses onboarding's own controller and
/// question widgets verbatim, just without the intro slides or the closing
/// notification-permission screen, so the questions/copy/animation are
/// identical to onboarding rather than a re-implementation.
///
/// Pushed by `register_screen.dart` right after a successful sign-up, and
/// pops `true` once the answers are saved (or `false` if the user backs out
/// - registration itself already succeeded either way).
class CompleteProfileFlow extends StatelessWidget {
  final UserProfile? initialProfile;
  const CompleteProfileFlow({super.key, this.initialProfile});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => OnboardingController(
        OnboardingRepository(ctx.read<ApiClient>()),
        NotificationsRepository(ctx.read<ApiClient>()),
        autoAdvanceEnabled: false,
        initialProfile: initialProfile,
      ),
      child: const _CompleteProfileView(),
    );
  }
}

class _CompleteProfileView extends StatefulWidget {
  const _CompleteProfileView();

  @override
  State<_CompleteProfileView> createState() => _CompleteProfileViewState();
}

class _CompleteProfileViewState extends State<_CompleteProfileView> {
  // Local index over the nine question steps - separate from
  // OnboardingController's own step enum, which also carries intro/
  // notification steps this flow doesn't use.
  int _index = 0;
  int _direction = 1;
  static const _stepCount = 9;

  Future<void> _finish(OnboardingController controller) async {
    final saved = await controller.submit();
    if (!mounted) return;
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(controller.lastError ?? 'Please complete your profile.')));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<OnboardingController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ClipRect(
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
          transitionBuilder: (child, animation) => AnimatedBuilder(
            animation: animation,
            child: child,
            builder: (context, child) {
              final incoming = animation.status != AnimationStatus.reverse;
              final progress = animation.value.clamp(0.0, 1.0);
              final horizontalOffset = incoming
                  ? _direction * (1 - progress)
                  : -_direction * (1 - progress);
              return Transform.translate(
                offset: Offset(
                    MediaQuery.sizeOf(context).width * horizontalOffset, 0),
                child: OnboardingStepTransitionScope(
                  animation: animation,
                  child: child!,
                ),
              );
            },
          ),
          child: KeyedSubtree(
            key: ValueKey(_index),
            child: _buildStep(controller),
          ),
        ),
      ),
    );
  }

  void _back() {
    if (_index == 0) {
      Navigator.of(context).maybePop(false);
    } else {
      setState(() {
        _direction = -1;
        _index--;
      });
    }
  }

  void _next() {
    if (_index < _stepCount - 1) {
      setState(() {
        _direction = 1;
        _index++;
      });
    }
  }

  Widget _buildStep(OnboardingController controller) {
    if (_index >= 5) {
      return TrainingPreferenceQuestion(
        controller: controller,
        step: const [
          OnboardingStep.trainingDays,
          OnboardingStep.trainingExperience,
          OnboardingStep.equipmentAccess,
          OnboardingStep.dailyActivity
        ][_index - 5],
        progressStep: _index + 1,
        progressStepCount: _stepCount,
        onBack: _back,
        onNext: _index == 8 ? () => _finish(controller) : _next,
        isLast: _index == 8,
      );
    }
    switch (_index) {
      case 0:
        return QuestionScaffold(
          onBack: _back,
          progressStep: 1,
          progressStepCount: _stepCount,
          headline: "What's your gender?",
          body: OptionRowSelector(
            options: const ['Male', 'Female', 'Other'],
            selected: controller.gender,
            onSelected: controller.selectGender,
          ),
          ctaLabel: 'Continue',
          onCta: controller.gender != null ? _next : null,
        );
      case 1:
        return QuestionScaffold(
          onBack: _back,
          progressStep: 2,
          progressStepCount: _stepCount,
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
          onCta: _next,
        );
      case 2:
        return QuestionScaffold(
          onBack: _back,
          progressStep: 3,
          progressStepCount: _stepCount,
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
            ),
          ),
          ctaLabel: 'Continue',
          onCta: _next,
        );
      case 3:
        return QuestionScaffold(
          onBack: _back,
          progressStep: 4,
          progressStepCount: _stepCount,
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
            ),
          ),
          ctaLabel: 'Continue',
          onCta: _next,
        );
      case 4:
      default:
        return QuestionScaffold(
          onBack: _back,
          progressStep: 5,
          progressStepCount: _stepCount,
          headline: "What's your main goal?",
          body: OptionRowSelector(
            options: const ['BuildMuscle', 'LoseFat', 'MaintainActive'],
            labelFor: (value) =>
                const {
                  'BuildMuscle': 'Build muscle',
                  'LoseFat': 'Lose fat',
                  'MaintainActive': 'Maintain and stay active',
                }[value] ??
                value,
            selected: controller.goal,
            onSelected: controller.selectGoal,
          ),
          ctaLabel: 'Continue',
          ctaLoading: controller.isSubmitting,
          onCta: controller.goal != null ? _next : null,
        );
    }
  }
}
