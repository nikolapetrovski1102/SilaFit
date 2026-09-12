import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../onboarding/onboarding_controller.dart';
import '../onboarding/onboarding_repository.dart';
import '../onboarding/widgets/numeric_wheel_picker.dart';
import '../onboarding/widgets/option_row_selector.dart';
import '../onboarding/widgets/question_scaffold.dart';

/// Walks a just-registered user through the same 5 onboarding questions
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
  const CompleteProfileFlow({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) =>
          OnboardingController(OnboardingRepository(ctx.read<ApiClient>())),
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
  // Local 0-4 index over just the 5 question steps - separate from
  // OnboardingController's own step enum, which also carries intro/
  // notification steps this flow doesn't use.
  int _index = 0;
  static const _stepCount = 5;

  Future<void> _finish(OnboardingController controller) async {
    await controller.submit();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<OnboardingController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
                .animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey(_index),
          child: _buildStep(controller),
        ),
      ),
    );
  }

  void _back() {
    if (_index == 0) {
      Navigator.of(context).maybePop(false);
    } else {
      setState(() => _index--);
    }
  }

  void _next() {
    if (_index < _stepCount - 1) {
      setState(() => _index++);
    }
  }

  Widget _buildStep(OnboardingController controller) {
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
            labelFor: (value) => const {
              'BuildMuscle': 'Build muscle',
              'LoseFat': 'Lose fat',
              'MaintainActive': 'Maintain and stay active',
            }[value] ?? value,
            selected: controller.goal,
            onSelected: controller.selectGoal,
          ),
          ctaLabel: 'Finish',
          ctaLoading: controller.isSubmitting,
          onCta: controller.goal != null ? () => _finish(controller) : null,
        );
    }
  }
}
