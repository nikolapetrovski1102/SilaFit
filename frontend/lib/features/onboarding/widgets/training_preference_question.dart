import 'package:flutter/material.dart';
import '../onboarding_controller.dart';
import 'arc_rating_slider.dart';
import 'option_row_selector.dart';
import 'question_scaffold.dart';

/// Uses the same answer rows, typography, progress and CTA as the original questions.
class TrainingPreferenceQuestion extends StatelessWidget {
  final OnboardingController controller;
  final OnboardingStep step;
  final int progressStep;
  final int progressStepCount;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final bool isLast;
  const TrainingPreferenceQuestion(
      {super.key,
      required this.controller,
      required this.step,
      required this.progressStep,
      required this.progressStepCount,
      required this.onBack,
      required this.onNext,
      this.isLast = false});

  static const _experienceLabels = {
    'Beginner': 'Getting started',
    'Intermediate': 'Somewhat athletic',
    'Advanced': 'Very athletic',
  };

  @override
  Widget build(BuildContext context) {
    if (step == OnboardingStep.trainingExperience) {
      return QuestionScaffold(
        onBack: onBack,
        progressStep: progressStep,
        progressStepCount: progressStepCount,
        headline: 'How would you rate your fitness level?',
        body: ArcRatingSlider(
          values: _experienceLabels.keys.toList(),
          labels: _experienceLabels,
          displayNumbers: const [1, 3, 5],
          selected: controller.trainingExperience,
          onSelected: (value) =>
              controller.setTrainingExperience(value, autoAdvance: false),
        ),
        ctaLabel: isLast ? 'Finish' : 'Continue',
        ctaLoading: isLast && controller.isSubmitting,
        onCta: controller.trainingExperience != null && !controller.isSubmitting
            ? onNext
            : null,
      );
    }

    final String headline;
    final Map<String, String> options;
    final String? selected;
    final ValueChanged<String> onSelected;
    final IconData? Function(String)? iconFor;
    switch (step) {
      case OnboardingStep.trainingDays:
        headline = 'Training days per week?';
        options = const {
          '2': '1–2 days',
          '4': '3–4 days',
          '5': '5 days',
          '6': '6+ days'
        };
        selected = controller.trainingDaysPerWeek?.toString();
        onSelected =
            (value) => controller.setTrainingDaysPerWeek(int.parse(value));
        iconFor = null;
        break;
      case OnboardingStep.equipmentAccess:
        headline = 'What equipment can you use?';
        options = const {
          'FullGym': 'Full gym',
          'Dumbbells': 'Dumbbells',
          'Bodyweight': 'Bodyweight only'
        };
        selected = controller.equipmentAccess;
        onSelected = (value) => controller.setEquipmentAccess(value);
        iconFor = (value) => const {
              'FullGym': Icons.storefront_outlined,
              'Dumbbells': Icons.fitness_center_rounded,
              'Bodyweight': Icons.accessibility_new_rounded,
            }[value];
        break;
      case OnboardingStep.dailyActivity:
        headline = 'How active is your day?';
        options = const {
          'Sedentary': 'Mostly sitting',
          'LightlyActive': 'Some walking',
          'Active': 'Mostly on my feet',
          'VeryActive': 'Physical work'
        };
        selected = controller.dailyActivityLevel;
        onSelected = (value) => controller.setDailyActivityLevel(value);
        iconFor = (value) => const {
              'Sedentary': Icons.weekend_rounded,
              'LightlyActive': Icons.directions_walk_rounded,
              'Active': Icons.directions_walk_rounded,
              'VeryActive': Icons.construction_rounded,
            }[value];
        break;
      default:
        throw ArgumentError('Not a training preference step: $step');
    }
    return QuestionScaffold(
      onBack: onBack,
      progressStep: progressStep,
      progressStepCount: progressStepCount,
      headline: headline,
      body: OptionRowSelector(
          options: options.keys.toList(),
          labelFor: (value) => options[value]!,
          selected: selected,
          onSelected: onSelected,
          iconFor: iconFor),
      ctaLabel: isLast ? 'Finish' : 'Continue',
      ctaLoading: isLast && controller.isSubmitting,
      onCta: selected != null && !controller.isSubmitting ? onNext : null,
    );
  }
}
