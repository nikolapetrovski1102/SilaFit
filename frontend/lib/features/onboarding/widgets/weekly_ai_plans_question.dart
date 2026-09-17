import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/section_card.dart';
import 'question_scaffold.dart';

/// The AI weekly plans opt-in step - two independent toggles (mirrors the
/// pair in `settings_screen.dart`'s "AI Weekly Plans" section, since this is
/// the same preference, just asked once up front instead of only in
/// Settings): whether the Sunday batch should build this user a custom split
/// + diet plan at all, and whether each one auto-activates. Both default on
/// so the feature reads as opt-out rather than something a first-time user
/// has to go discover in Settings later - either can be flipped here or
/// changed anytime afterward.
class WeeklyAiPlansQuestion extends StatelessWidget {
  final VoidCallback onBack;
  final int progressStep;
  final int progressStepCount;
  final bool receiveWeeklyAiPlans;
  final bool autoActivateAiPlans;
  final ValueChanged<bool> onReceiveChanged;
  final ValueChanged<bool> onAutoActivateChanged;
  final VoidCallback onCta;

  const WeeklyAiPlansQuestion({
    super.key,
    required this.onBack,
    required this.progressStep,
    required this.progressStepCount,
    required this.receiveWeeklyAiPlans,
    required this.autoActivateAiPlans,
    required this.onReceiveChanged,
    required this.onAutoActivateChanged,
    required this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return QuestionScaffold(
      onBack: onBack,
      progressStep: progressStep,
      progressStepCount: progressStepCount,
      headline: 'Want AI to plan\nyour week?',
      ctaLabel: 'Continue',
      onCta: onCta,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Every Sunday, we can build you a fresh custom split and diet '
            'plan from what you actually trained and logged that week.',
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionCard(
            child: Column(
              children: [
                _ToggleRow(
                  label: 'Let AI build your weekly plan',
                  value: receiveWeeklyAiPlans,
                  onChanged: onReceiveChanged,
                ),
                if (receiveWeeklyAiPlans) ...[
                  Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
                  _ToggleRow(
                    label: 'Auto-activate it each week',
                    value: autoActivateAiPlans,
                    onChanged: onAutoActivateChanged,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Change either of these anytime in Settings.',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.bodyMd)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.onAccent,
          activeTrackColor: AppColors.accent,
          inactiveTrackColor: AppColors.surfaceContainerHigh,
        ),
      ],
    );
  }
}
